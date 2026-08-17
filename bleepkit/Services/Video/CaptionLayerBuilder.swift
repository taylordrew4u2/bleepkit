//
//  CaptionLayerBuilder.swift
//  BleepKit
//

import AVFoundation
import CoreMedia
import CoreText
import Foundation
import OSLog
import QuartzCore
import UIKit

// MARK: - Line grouping

/// One caption line: consecutive tokens grouped for display.
nonisolated struct CaptionLine: Sendable {
    var tokens: [WordToken]
    /// When the line appears — its first token's start.
    var startSeconds: Double
    /// When the line disappears. Extended to the next line's start so
    /// captions never flicker off between phrases.
    var displayEndSeconds: Double
}

/// Groups tokens into caption lines: a line breaks after
/// `maxWordsPerLine` words OR `maxSecondsPerLine` seconds, whichever limit
/// is reached first.
nonisolated enum CaptionLineGrouper {
    static func lines(
        tokens: [WordToken],
        maxWordsPerLine: Int,
        maxSecondsPerLine: Double
    ) -> [CaptionLine] {
        let sorted = tokens.sorted { $0.startSeconds < $1.startSeconds }
        var lines: [CaptionLine] = []
        var current: [WordToken] = []

        func closeLine() {
            guard let first = current.first, let last = current.last else { return }
            lines.append(CaptionLine(
                tokens: current,
                startSeconds: first.startSeconds,
                displayEndSeconds: last.endSeconds
            ))
            current = []
        }

        for token in sorted {
            if let first = current.first {
                let exceedsWords = current.count >= max(1, maxWordsPerLine)
                let exceedsSeconds = token.endSeconds - first.startSeconds > maxSecondsPerLine
                if exceedsWords || exceedsSeconds {
                    closeLine()
                }
            }
            current.append(token)
        }
        closeLine()

        // No gaps: each line stays visible until the next one begins.
        for index in lines.indices.dropLast() {
            lines[index].displayEndSeconds = lines[index + 1].startSeconds
        }
        return lines
    }
}

// MARK: - Layer building

/// Builds the burned-in caption layer tree.
///
/// The same builder serves export (`targetSize` = 1080×1920) and preview
/// (`targetSize` = the player's video rect) — only the coordinate scale
/// differs, which is what keeps the two trees from drifting apart.
///
/// All geometry is computed in top-left coordinates. The export parent
/// layer must set `isGeometryFlipped = true` so this math also holds under
/// the animation tool's bottom-left origin (mitigates the mirrored-Y
/// failure mode; verified visually at Gate 6/7).
///
/// Runs on the main actor: layer trees are UI objects, and this is the one
/// service allowed to touch UIKit (system font resolution only).
@MainActor
struct CaptionLayerBuilder {
    struct Configuration {
        var style: CaptionStyle
        var censorStyle: CensorStyle
        /// Image for the `.image` censor treatment, resolved by the caller;
        /// nil falls back to a black bar.
        var censorImage: CGImage?
        /// The coordinate space to build in.
        var targetSize: CGSize
        /// Rasterization scale for every layer — a missing contentsScale
        /// produces blurry text.
        var contentsScale: CGFloat
    }

    let configuration: Configuration

    /// Scale from the 1080-wide style space to the target space.
    private var renderScale: CGFloat {
        configuration.targetSize.width / CompositionBuilder.renderSize.width
    }

    /// Builds the complete caption layer covering the whole asset timeline.
    func buildLayer(tokens: [WordToken], assetDurationSeconds: Double) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: configuration.targetSize)
        container.masksToBounds = false
        guard assetDurationSeconds > 0, renderScale > 0 else { return container }

        let lines = CaptionLineGrouper.lines(
            tokens: tokens,
            maxWordsPerLine: configuration.style.maxWordsPerLine,
            maxSecondsPerLine: configuration.style.maxSecondsPerLine
        )
        for line in lines {
            if let lineLayer = buildLineLayer(line, assetDuration: assetDurationSeconds) {
                container.addSublayer(lineLayer)
            }
        }
        return container
    }

    // MARK: Line geometry

    /// Everything geometric about one caption line, shared by the layer
    /// build and by `censoredWordFrames(tokens:)` so the overlay's follow
    /// mode can never drift from the rendered captions.
    private struct LineGeometry {
        let displayWords: [String]
        let layout: TextMeasurement.LineLayout
        /// The line layer's frame in target space.
        let frame: CGRect
        let padding: CGFloat
        let font: CTFont
        let uiFont: UIFont
        let fontSize: CGFloat
    }

    private func geometry(for line: CaptionLine) -> LineGeometry? {
        let style = configuration.style
        let scale = renderScale
        let fontSize = style.fontSize * scale
        let uiFont = Self.uiFont(family: style.fontFamily, size: fontSize, weight: style.fontWeight)
        let font = CTFontCreateWithFontDescriptor(uiFont.fontDescriptor as CTFontDescriptor, fontSize, nil)
        let displayWords = line.tokens.map { displayText(for: $0) }
        let layout = TextMeasurement.layout(words: displayWords, font: font)
        guard layout.size.width > 0 else { return nil }

        let padding = style.backgroundEnabled ? style.backgroundPadding * scale : 0
        let lineSize = CGSize(
            width: layout.size.width + padding * 2,
            height: layout.size.height + padding * 2
        )

        // Vertical position: 0 = top, 1 = bottom; clamped so captions never
        // render above 15% or below 88% of frame height.
        let normalizedY = min(max(style.verticalPositionNormalized, 0.15), 0.88)
        let centerY = configuration.targetSize.height * normalizedY
        let frame = CGRect(
            x: (configuration.targetSize.width - lineSize.width) / 2,
            y: centerY - lineSize.height / 2,
            width: lineSize.width,
            height: lineSize.height
        )
        return LineGeometry(
            displayWords: displayWords,
            layout: layout,
            frame: frame,
            padding: padding,
            font: font,
            uiFont: uiFont,
            fontSize: fontSize
        )
    }

    /// Target-space glyph frames of every censored word, keyed by token ID.
    /// Drives the overlay's follow-caption placement.
    func censoredWordFrames(tokens: [WordToken]) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        let lines = CaptionLineGrouper.lines(
            tokens: tokens,
            maxWordsPerLine: configuration.style.maxWordsPerLine,
            maxSecondsPerLine: configuration.style.maxSecondsPerLine
        )
        for line in lines {
            guard let geometry = geometry(for: line) else { continue }
            for (index, token) in line.tokens.enumerated() where token.isCensored {
                let glyph = geometry.layout.glyphBounds[index]
                    .offsetBy(dx: geometry.padding, dy: geometry.padding)
                frames[token.id] = glyph.offsetBy(
                    dx: geometry.frame.minX,
                    dy: geometry.frame.minY
                )
            }
        }
        return frames
    }

    // MARK: One line

    private func buildLineLayer(_ line: CaptionLine, assetDuration: Double) -> CALayer? {
        guard line.displayEndSeconds > line.startSeconds else { return nil }
        guard let geometry = geometry(for: line) else { return nil }
        let style = configuration.style
        let scale = renderScale
        let displayWords = geometry.displayWords
        let layout = geometry.layout
        let padding = geometry.padding
        let lineSize = geometry.frame.size

        let lineLayer = CALayer()
        lineLayer.frame = geometry.frame
        lineLayer.masksToBounds = false
        lineLayer.opacity = 0
        lineLayer.contentsScale = configuration.contentsScale
        lineLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        lineLayer.shadowOpacity = style.shadowOpacity
        lineLayer.shadowRadius = style.shadowRadius * scale
        lineLayer.shadowOffset = CGSize(width: 0, height: 2 * scale)

        if style.backgroundEnabled {
            let background = CALayer()
            background.frame = CGRect(origin: .zero, size: lineSize)
            background.backgroundColor = Self.color(
                hex: style.backgroundColorHex,
                alpha: CGFloat(style.backgroundOpacity)
            )
            background.cornerRadius = style.backgroundCornerRadius * scale
            background.contentsScale = configuration.contentsScale
            lineLayer.addSublayer(background)
        }

        for (index, token) in line.tokens.enumerated() {
            let wordFrame = layout.wordFrames[index].offsetBy(dx: padding, dy: padding)
            let glyphFrame = layout.glyphBounds[index].offsetBy(dx: padding, dy: padding)
            if token.isCensored, !censorTreatmentKeepsText {
                addCensorTreatment(to: lineLayer, glyphFrame: glyphFrame)
            } else {
                addWordLayers(
                    to: lineLayer,
                    text: displayWords[index],
                    frame: wordFrame,
                    uiFont: geometry.uiFont,
                    token: token,
                    assetDuration: assetDuration
                )
            }
        }

        lineLayer.add(
            Self.discreteAnimation(
                keyPath: "opacity",
                baseValue: 0,
                activeValue: 1,
                from: line.startSeconds,
                to: line.displayEndSeconds,
                totalDuration: assetDuration
            ),
            forKey: "bleepkit.visibility"
        )
        return lineLayer
    }

    // MARK: One word

    /// Adds one word as a pair of pre-rendered bitmap layers: the normal
    /// fill color below, the karaoke active color above with an opacity
    /// animation for exactly the word's spoken range.
    ///
    /// Bitmaps instead of `CATextLayer` on purpose: CATextLayer produces no
    /// output inside `AVVideoCompositionCoreAnimationTool` (verified
    /// empirically on iOS 26), while plain layer contents render everywhere
    /// — including the preview's `AVSynchronizedLayer` — so both trees stay
    /// pixel-identical. Stroke and fill happen in a single attributed-string
    /// pass (negative `.strokeWidth` means stroke-plus-fill).
    private func addWordLayers(
        to lineLayer: CALayer,
        text: String,
        frame: CGRect,
        uiFont: UIFont,
        token: WordToken,
        assetDuration: Double
    ) {
        let style = configuration.style
        // The stroke pokes out past the typographic bounds; pad the canvas
        // (and the layer frame, equally) so it isn't clipped.
        let strokePad = style.strokeWidth > 0 ? style.strokeWidth * renderScale + 1 : 0
        let paddedFrame = frame.insetBy(dx: -strokePad, dy: -strokePad)

        guard let normalImage = renderWordImage(
            text: text,
            font: uiFont,
            fillHex: style.fillColorHex,
            canvasSize: paddedFrame.size,
            drawOrigin: CGPoint(x: strokePad, y: strokePad)
        ) else { return }
        let wordLayer = CALayer()
        wordLayer.frame = paddedFrame
        wordLayer.contents = normalImage
        wordLayer.contentsScale = configuration.contentsScale
        lineLayer.addSublayer(wordLayer)

        // Karaoke highlight: the active-color rendition fades in discretely
        // for exactly the word's spoken range.
        guard token.durationSeconds > 0,
              style.activeColorHex.lowercased() != style.fillColorHex.lowercased(),
              let activeImage = renderWordImage(
                  text: text,
                  font: uiFont,
                  fillHex: style.activeColorHex,
                  canvasSize: paddedFrame.size,
                  drawOrigin: CGPoint(x: strokePad, y: strokePad)
              ) else { return }
        let activeLayer = CALayer()
        activeLayer.frame = paddedFrame
        activeLayer.contents = activeImage
        activeLayer.contentsScale = configuration.contentsScale
        activeLayer.opacity = 0
        activeLayer.add(
            Self.discreteAnimation(
                keyPath: "opacity",
                baseValue: 0,
                activeValue: 1,
                from: token.startSeconds,
                to: token.endSeconds,
                totalDuration: assetDuration
            ),
            forKey: "bleepkit.karaoke"
        )
        lineLayer.addSublayer(activeLayer)
    }

    /// Rasterizes one word — fill plus stroke in a single pass — at the
    /// configured contents scale.
    private func renderWordImage(
        text: String,
        font: UIFont,
        fillHex: String,
        canvasSize: CGSize,
        drawOrigin: CGPoint
    ) -> CGImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let style = configuration.style
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(cgColor: Self.color(hex: fillHex)),
        ]
        if style.strokeWidth > 0 {
            attributes[.strokeColor] = UIColor(cgColor: Self.color(hex: style.strokeColorHex))
            // Negative stroke width draws stroke and fill; doubled because
            // the fill covers the inner half. The value is a percentage of
            // the font size, so it is scale-invariant.
            attributes[.strokeWidth] = -(style.strokeWidth * 2 / style.fontSize) * 100
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = configuration.contentsScale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        let image = renderer.image { _ in
            NSAttributedString(string: text, attributes: attributes).draw(at: drawOrigin)
        }
        return image.cgImage
    }

    // MARK: Censor treatments

    /// Whether the selected treatment renders as text (and therefore goes
    /// through the normal word path with a masked string).
    private var censorTreatmentKeepsText: Bool {
        if case .asterisks = configuration.censorStyle { return true }
        return false
    }

    /// Adds the non-text censor treatment over the word's measured glyph
    /// bounds. The word still occupies its position in the line — only the
    /// rendering is replaced.
    private func addCensorTreatment(to lineLayer: CALayer, glyphFrame: CGRect) {
        let scale = renderScale
        switch configuration.censorStyle {
        case .asterisks:
            // Handled by the text path; never reaches here.
            break
        case .emoji(let emoji):
            // Bitmap, not CATextLayer — see addWordLayers for why.
            guard let image = StickerRenderer.emojiImage(emoji) else { return }
            let layer = CALayer()
            layer.contents = image
            layer.contentsGravity = .resizeAspect
            layer.contentsScale = configuration.contentsScale
            let emojiSize = glyphFrame.height * 1.2
            layer.frame = CGRect(
                x: glyphFrame.midX - emojiSize / 2,
                y: glyphFrame.midY - emojiSize / 2,
                width: emojiSize,
                height: emojiSize
            )
            lineLayer.addSublayer(layer)
        case .image(_) where configuration.censorImage != nil:
            let layer = CALayer()
            layer.contents = configuration.censorImage
            layer.contentsGravity = .resizeAspect
            layer.frame = glyphFrame
            layer.contentsScale = configuration.contentsScale
            lineLayer.addSublayer(layer)
        case .blackBar, .image:
            // Black bar — also the fallback when the image is unresolvable.
            let bar = CALayer()
            // Outset slightly beyond the glyph bounds for full coverage.
            let frame = glyphFrame.insetBy(dx: -2 * scale, dy: -2 * scale)
            bar.frame = frame
            bar.backgroundColor = CGColor(gray: 0, alpha: 1)
            bar.cornerRadius = min(frame.width, frame.height) * 0.2
            bar.contentsScale = configuration.contentsScale
            lineLayer.addSublayer(bar)
        }
    }

    // MARK: Text helpers

    private func displayText(for token: WordToken) -> String {
        guard token.isCensored, censorTreatmentKeepsText else { return token.text }
        return Self.maskedText(for: token.text)
    }

    /// "fuck" → "f***". Tokens the recognizer already masked keep their mask.
    nonisolated static func maskedText(for text: String) -> String {
        if text.contains("*") { return text }
        guard let first = text.first else { return text }
        return String(first) + String(repeating: "*", count: max(text.count - 1, 2))
    }

    // MARK: Animation

    /// A discrete keyframe animation on the global asset timeline that holds
    /// `activeValue` between `from` and `to` and `baseValue` elsewhere.
    ///
    /// Every animation in the project goes through here so the export rules
    /// hold everywhere: `beginTime = AVCoreAnimationBeginTimeAtZero` (a
    /// literal 0 means "now" and is silently dropped during export),
    /// `isRemovedOnCompletion = false`, and `fillMode = .both`.
    nonisolated static func discreteAnimation(
        keyPath: String,
        baseValue: Any,
        activeValue: Any,
        from start: Double,
        to end: Double,
        totalDuration: Double
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.calculationMode = .discrete
        animation.duration = totalDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both

        let clampedStart = min(max(start / totalDuration, 0), 1)
        let clampedEnd = min(max(end / totalDuration, 0), 1)
        // Discrete mode requires values.count == keyTimes.count - 1; zero
        // width segments are dropped so keyTimes stay strictly increasing.
        var values: [Any] = []
        var keyTimes: [NSNumber] = [0]
        if clampedStart > 0 {
            values.append(baseValue)
            keyTimes.append(NSNumber(value: clampedStart))
        }
        values.append(activeValue)
        if clampedEnd < 1 {
            keyTimes.append(NSNumber(value: clampedEnd))
            values.append(baseValue)
        }
        keyTimes.append(1)
        animation.values = values
        animation.keyTimes = keyTimes
        return animation
    }

    /// Like `discreteAnimation`, but active during several disjoint
    /// intervals — the overlay is visible during every censor range.
    nonisolated static func discreteIntervalsAnimation(
        keyPath: String,
        baseValue: Any,
        activeValue: Any,
        intervals: [(start: Double, end: Double)],
        totalDuration: Double
    ) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.calculationMode = .discrete
        animation.duration = totalDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both

        // Normalize, clamp, sort, and drop empty intervals.
        let normalized = intervals
            .map { (min(max($0.start / totalDuration, 0), 1), min(max($0.end / totalDuration, 0), 1)) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }

        var values: [Any] = []
        var keyTimes: [NSNumber] = [0]
        var cursor: Double = 0
        for (start, end) in normalized {
            guard start >= cursor else { continue }
            if start > cursor {
                values.append(baseValue)
                keyTimes.append(NSNumber(value: start))
            }
            values.append(activeValue)
            if end < 1 {
                keyTimes.append(NSNumber(value: end))
            }
            cursor = end
        }
        if cursor < 1 {
            values.append(baseValue)
        }
        keyTimes.append(1)
        // A trailing duplicate "1" appears when the last interval ends at 1;
        // drop it so keyTimes stay strictly increasing.
        if keyTimes.count >= 2, keyTimes[keyTimes.count - 1] == keyTimes[keyTimes.count - 2] {
            keyTimes.removeLast()
        }
        animation.values = values
        animation.keyTimes = keyTimes
        return animation
    }

    // MARK: Fonts and colors

    /// Resolves a caption font at a numeric weight. SF and New York come
    /// from the system font's designs; the classic families resolve by
    /// name to the closest installed weight. Nothing is bundled.
    nonisolated static func uiFont(
        family: CaptionStyle.FontFamily,
        size: CGFloat,
        weight: Int
    ) -> UIFont {
        let uiWeight: UIFont.Weight
        switch weight {
        case ..<150: uiWeight = .ultraLight
        case ..<250: uiWeight = .thin
        case ..<350: uiWeight = .light
        case ..<450: uiWeight = .regular
        case ..<550: uiWeight = .medium
        case ..<650: uiWeight = .semibold
        case ..<750: uiWeight = .bold
        case ..<850: uiWeight = .heavy
        default: uiWeight = .black
        }
        if let familyName = family.familyName {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: familyName,
                .traits: [UIFontDescriptor.TraitKey.weight: uiWeight],
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
        let base = UIFont.systemFont(ofSize: size, weight: uiWeight)
        let design: UIFontDescriptor.SystemDesign?
        switch family {
        case .sfPro: design = nil
        case .sfProRounded: design = .rounded
        case .newYork: design = .serif
        case .sfMono: design = .monospaced
        // Named families never reach here; they resolve above.
        default: design = nil
        }
        if let design, let designed = base.fontDescriptor.withDesign(design) {
            return UIFont(descriptor: designed, size: size)
        }
        return base
    }

    /// The Core Text view of the same font, for measurement.
    nonisolated static func font(
        family: CaptionStyle.FontFamily,
        size: CGFloat,
        weight: Int
    ) -> CTFont {
        let resolved = uiFont(family: family, size: size, weight: weight)
        return CTFontCreateWithFontDescriptor(resolved.fontDescriptor as CTFontDescriptor, size, nil)
    }

    /// Parses "#RRGGBB" into an sRGB CGColor; white on malformed input.
    nonisolated static func color(hex: String, alpha: CGFloat = 1) -> CGColor {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).lowercased()
        var value: UInt64 = 0
        guard trimmed.count == 6, Scanner(string: trimmed).scanHexInt64(&value) else {
            Logger.video.error("Malformed color hex \"\(hex, privacy: .public)\"; using white")
            return CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha)
        }
        return CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }
}
