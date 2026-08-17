//
//  CensorRangeCalculator.swift
//  BleepKit
//

import CoreMedia
import Foundation

/// Computes the padded, merged time ranges that drive all three censor
/// layers. A pure function — audio muting, beep insertion, caption
/// treatment, and the video overlay all consume this exact output, which
/// is what keeps them frame-aligned.
nonisolated enum CensorRangeCalculator {
    /// Builds censor ranges from the censored tokens.
    ///
    /// Algorithm:
    /// 1. Filter to tokens where `isCensored == true`.
    /// 2. Expand each token's range by ±`padding` seconds — recognizer word
    ///    boundaries drift relative to the actual audio, and without padding
    ///    the leading or trailing phoneme leaks past the beep.
    /// 3. Clamp to `[.zero, assetDuration]`.
    /// 4. Sort by start time.
    /// 5. Merge overlapping and adjacent ranges (`next.start <= current.end`),
    ///    accumulating `sourceTokenIDs` — back-to-back curses must become one
    ///    continuous beep, not two overlapping tones that sum to clipping.
    ///
    /// - Parameters:
    ///   - tokens: All transcript tokens; only censored ones contribute.
    ///   - padding: Seconds added before and after each word (0...0.2 in UI).
    ///   - assetDuration: Upper clamp bound; ranges never exceed the asset.
    static func censorRanges(
        tokens: [WordToken],
        padding: Double,
        assetDuration: CMTime
    ) -> [CensorRange] {
        let durationSeconds = assetDuration.seconds
        guard durationSeconds > 0 else { return [] }

        let expanded: [CensorRange] = tokens
            .filter(\.isCensored)
            .compactMap { token in
                let startSeconds = max(0, token.startSeconds - padding)
                let endSeconds = min(durationSeconds, token.endSeconds + padding)
                guard endSeconds > startSeconds else { return nil }
                return CensorRange(
                    start: .projectSeconds(startSeconds),
                    end: .projectSeconds(endSeconds),
                    sourceTokenIDs: [token.id]
                )
            }
            .sorted { $0.start < $1.start }

        var merged: [CensorRange] = []
        for range in expanded {
            if var current = merged.last, range.start <= current.end {
                current.end = max(current.end, range.end)
                current.sourceTokenIDs.append(contentsOf: range.sourceTokenIDs)
                merged[merged.count - 1] = current
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
