//
//  OverlayLayerBuilder.swift
//  BleepKit
//

import AVFoundation
import CoreGraphics
import Foundation
import QuartzCore
import UIKit

/// Renders overlay stickers at runtime. Bundled stickers are emoji rendered
/// to bitmaps on demand — nothing ships as a binary asset, and user-picked
/// emoji work exactly the same way.
@MainActor
enum StickerRenderer {
    /// The bundled sticker choices.
    static let bundledEmoji = ["🤬", "😡", "💥", "🙊"]

    /// Renders an emoji to a bitmap suitable for a layer's contents.
    static func emojiImage(_ emoji: String, pointSize: CGFloat = 256) -> CGImage? {
        let attributed = NSAttributedString(string: emoji, attributes: [
            .font: UIFont.systemFont(ofSize: pointSize),
        ])
        let size = attributed.size()
        guard size.width > 0, size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { _ in
            attributed.draw(at: .zero)
        }
        return image.cgImage
    }
}

/// Builds the video-censor overlay layer: a user-chosen image composited
/// over the frame for exactly the duration of each censor range.
///
/// Visibility is keyed to the same merged `CensorRange` array that drives
/// the beep — reusing those ranges is what guarantees the overlay and the
/// beep start and end on the same frame.
///
/// Sits between the video layer and the caption layer. Same top-left
/// coordinate convention as `CaptionLayerBuilder`.
@MainActor
struct OverlayLayerBuilder {
    struct Configuration {
        var image: CGImage
        /// Pinned center, normalized 0...1 in target space.
        var normalizedCenter: CGPoint
        /// Overlay width as a fraction of the frame width.
        var normalizedWidth: CGFloat = 0.35
        var targetSize: CGSize
        var contentsScale: CGFloat
        /// When true, the overlay jumps to each censored caption word.
        var followsCaption: Bool = false
        /// Per-range caption-word rects (target space), parallel to the
        /// ranges passed to `buildLayer`. Consulted only in follow mode.
        var captionTargets: [CGRect] = []
    }

    let configuration: Configuration

    /// Builds the overlay layer for the whole asset timeline.
    func buildLayer(ranges: [CensorRange], assetDurationSeconds: Double) -> CALayer {
        let container = CALayer()
        container.frame = CGRect(origin: .zero, size: configuration.targetSize)
        container.masksToBounds = false
        guard assetDurationSeconds > 0, !ranges.isEmpty else { return container }

        let imageSize = CGSize(
            width: configuration.image.width,
            height: configuration.image.height
        )
        guard imageSize.width > 0, imageSize.height > 0 else { return container }

        let width = configuration.targetSize.width * configuration.normalizedWidth
        let height = width * imageSize.height / imageSize.width
        let pinnedCenter = CGPoint(
            x: configuration.targetSize.width * configuration.normalizedCenter.x,
            y: configuration.targetSize.height * configuration.normalizedCenter.y
        )

        let imageLayer = CALayer()
        imageLayer.contents = configuration.image
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.contentsScale = configuration.contentsScale
        imageLayer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        imageLayer.position = pinnedCenter
        imageLayer.opacity = 0

        let intervals = ranges.map { ($0.start.seconds, $0.end.seconds) }
        imageLayer.add(
            CaptionLayerBuilder.discreteIntervalsAnimation(
                keyPath: "opacity",
                baseValue: 0,
                activeValue: 1,
                intervals: intervals,
                totalDuration: assetDurationSeconds
            ),
            forKey: "bleepkit.overlayVisibility"
        )

        // Follow mode: jump to each censored word's caption position at the
        // start of its range. Positions between ranges are irrelevant — the
        // layer is invisible there.
        if configuration.followsCaption, configuration.captionTargets.count == ranges.count {
            let positions: [CGPoint] = configuration.captionTargets.map { rect in
                rect.isEmpty ? pinnedCenter : CGPoint(x: rect.midX, y: rect.midY)
            }
            if let positionAnimation = Self.steppedPositionAnimation(
                positions: positions,
                startTimes: ranges.map { $0.start.seconds },
                totalDuration: assetDurationSeconds
            ) {
                imageLayer.add(positionAnimation, forKey: "bleepkit.overlayPosition")
            }
        }

        container.addSublayer(imageLayer)
        return container
    }

    /// A discrete position animation that holds `positions[i]` from
    /// `startTimes[i]` until the next start time.
    private static func steppedPositionAnimation(
        positions: [CGPoint],
        startTimes: [Double],
        totalDuration: Double
    ) -> CAKeyframeAnimation? {
        guard !positions.isEmpty, positions.count == startTimes.count, totalDuration > 0 else {
            return nil
        }
        let animation = CAKeyframeAnimation(keyPath: "position")
        animation.calculationMode = .discrete
        animation.duration = totalDuration
        animation.beginTime = AVCoreAnimationBeginTimeAtZero
        animation.isRemovedOnCompletion = false
        animation.fillMode = .both

        // The first position also covers 0..<startTimes[0] (invisible there
        // anyway); subsequent positions switch at their range's start.
        var values: [NSValue] = [NSValue(cgPoint: positions[0])]
        var keyTimes: [NSNumber] = [0]
        for index in 1..<positions.count {
            let time = min(max(startTimes[index] / totalDuration, 0), 1)
            keyTimes.append(NSNumber(value: time))
            values.append(NSValue(cgPoint: positions[index]))
        }
        keyTimes.append(1)
        animation.values = values
        animation.keyTimes = keyTimes
        return animation
    }
}
