//
//  TextNormalizer.swift
//  BleepKit
//

import Foundation

/// Canonicalizes a token before profanity matching. Pure and synchronous.
///
/// Steps, in order:
/// 1. Lowercase.
/// 2. Unicode-normalize to NFKD and strip combining marks.
/// 3. Trim word-boundary punctuation ("hell!" → "hell") so boundary
///    characters are not mistaken for leetspeak; interior ones still are
///    ("sh!t" → "shit").
/// 4. Collapse runs of 3+ identical characters to one — "fuuuuck" → "fuck".
///    Asterisks are exempt: "f***" must survive as a recognizer mask.
/// 5. Leetspeak substitution — "sh1t" → "shit", "@ss" → "ass".
/// 6. Strip all non-alphanumerics except the asterisk, which is meaningful:
///    recognizers return profanity pre-masked as "f***".
nonisolated enum TextNormalizer {
    /// Leetspeak characters mapped to the letters they stand in for.
    private static let leetMap: [Character: Character] = [
        "@": "a", "4": "a",
        "0": "o",
        "1": "i", "!": "i", "|": "i",
        "3": "e",
        "$": "s", "5": "s",
        "7": "t", "+": "t",
    ]

    /// Returns the canonical form of `text` for matching.
    static func normalize(_ text: String) -> String {
        // 1. Lowercase.
        let lowered = text.lowercased()

        // 2. NFKD, then drop combining marks (category Mn).
        let decomposed = lowered.decomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars
        where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        let unmarked = String(scalars)

        // 3. Trim boundary punctuation before leet substitution so a
        //    trailing "!" is treated as punctuation, not as an "i".
        let trimmed = trimBoundaryPunctuation(unmarked)

        // 4. Collapse runs of 3+ identical characters to a single character.
        let collapsed = collapseRuns(trimmed)

        // 5. Leetspeak substitution.
        let deleeted = String(collapsed.map { leetMap[$0] ?? $0 })

        // 6. Keep letters, digits, and the meaningful asterisk.
        return deleeted.filter { $0.isLetter || $0.isNumber || $0 == "*" }
    }

    /// Drops word-boundary punctuation. Leetspeak characters stay ("@ss",
    /// "a$$") with one exception: "!" is dropped at boundaries because a
    /// trailing "hell!" is punctuation far more often than an "i".
    private static func trimBoundaryPunctuation(_ text: String) -> String {
        func isTrimmable(_ character: Character) -> Bool {
            if character == "!" { return true }
            if character.isLetter || character.isNumber || character == "*" { return false }
            return leetMap[character] == nil
        }
        var result = Substring(text)
        while let first = result.first, isTrimmable(first) {
            result = result.dropFirst()
        }
        while let last = result.last, isTrimmable(last) {
            result = result.dropLast()
        }
        return String(result)
    }

    /// Runs of the same character 3 or longer become one character; runs of
    /// 2 are kept intact ("ass" stays "ass", "shiiit" becomes "shit").
    /// Asterisk runs are preserved: "f***" is a recognizer mask, and the
    /// run length is what distinguishes it from a single wildcard.
    private static func collapseRuns(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            var runEnd = index
            var runLength = 0
            while runEnd < text.endIndex, text[runEnd] == character {
                runLength += 1
                runEnd = text.index(after: runEnd)
            }
            let keptLength = (character == "*" || runLength < 3) ? runLength : 1
            result.append(contentsOf: repeatElement(character, count: keptLength))
            index = runEnd
        }
        return result
    }
}
