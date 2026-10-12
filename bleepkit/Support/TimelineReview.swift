import CoreMedia
import Foundation

/// Review geometry uses the same effective words and censor spans as export.
nonisolated enum TimelineReview {
    static func nextCensoredToken(in tokens: [WordToken], after seconds: Double) -> WordToken? {
        let ordered = tokens.filter {
            $0.isCensored && $0.startSeconds.isFinite && $0.startSeconds >= 0
        }.sorted { $0.startSeconds < $1.startSeconds }
        // A small tolerance skips the word already under the playhead.
        return ordered.first { $0.startSeconds > seconds + 0.05 } ?? ordered.first
    }

    static func normalizedIntervals(for ranges: [CensorRange], durationSeconds: Double) -> [ClosedRange<Double>] {
        guard durationSeconds.isFinite, durationSeconds > 0 else { return [] }
        return ranges.compactMap { range in
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite else { return nil }
            let lower = min(max(start / durationSeconds, 0), 1)
            let upper = min(max(end / durationSeconds, 0), 1)
            guard upper > lower else { return nil }
            return lower...upper
        }
    }
}
