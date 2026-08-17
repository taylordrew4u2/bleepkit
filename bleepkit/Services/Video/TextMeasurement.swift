//
//  TextMeasurement.swift
//  BleepKit
//

import CoreGraphics
import CoreText
import Foundation

/// Exact text metrics via Core Text.
///
/// Black bars and censor images must align to the actual rendered glyph
/// rect, not an estimate from character count — an estimate is visibly
/// wrong at large font sizes.
nonisolated enum TextMeasurement {
    /// Layout of one caption line, in top-left coordinates with the line
    /// box's origin at (0, 0).
    struct LineLayout {
        /// Full typographic box per word (x advances left to right).
        let wordFrames: [CGRect]
        /// Tight glyph-path bounds per word, same coordinate space.
        let glyphBounds: [CGRect]
        /// Size of the whole line box.
        let size: CGSize
        /// Shared baseline, measured down from the top of the box.
        let ascent: CGFloat
    }

    /// Lays out words on one line with a single space between each.
    static func layout(words: [String], font: CTFont) -> LineLayout {
        let spaceWidth = measure(" ", font: font).width

        struct Measured {
            let width: CGFloat
            let glyph: CGRect
        }
        var maxAscent: CGFloat = 0
        var maxDescent: CGFloat = 0
        var measured: [Measured] = []
        for word in words {
            let line = ctLine(for: word, font: font)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            let glyph = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            measured.append(Measured(width: width, glyph: glyph))
            maxAscent = max(maxAscent, ascent)
            maxDescent = max(maxDescent, descent)
        }

        let height = maxAscent + maxDescent
        var wordFrames: [CGRect] = []
        var glyphBounds: [CGRect] = []
        var cursor: CGFloat = 0
        for item in measured {
            wordFrames.append(CGRect(x: cursor, y: 0, width: item.width, height: height))
            // Glyph-path bounds arrive baseline-relative with y pointing up;
            // convert into the top-left line box.
            glyphBounds.append(CGRect(
                x: cursor + item.glyph.minX,
                y: maxAscent - item.glyph.maxY,
                width: item.glyph.width,
                height: item.glyph.height
            ))
            cursor += item.width + spaceWidth
        }
        let totalWidth = measured.isEmpty ? 0 : max(0, cursor - spaceWidth)
        return LineLayout(
            wordFrames: wordFrames,
            glyphBounds: glyphBounds,
            size: CGSize(width: totalWidth, height: height),
            ascent: maxAscent
        )
    }

    /// Typographic size of a single string.
    static func measure(_ text: String, font: CTFont) -> CGSize {
        let line = ctLine(for: text, font: font)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        return CGSize(width: width, height: ascent + descent)
    }

    private static func ctLine(for text: String, font: CTFont) -> CTLine {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ])
        return CTLineCreateWithAttributedString(attributed)
    }
}
