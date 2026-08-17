//
//  CensorRange.swift
//  BleepKit
//

import CoreMedia
import Foundation

/// A padded, merged span of the timeline that all three censor layers share.
///
/// Produced only by `CensorRangeCalculator`. Audio muting, beep insertion,
/// caption treatment, and the video overlay all consume the same array of
/// these values, which is what keeps the three layers frame-aligned.
nonisolated struct CensorRange: Hashable, Sendable {
    /// Padded, clamped start of the censored span.
    var start: CMTime
    /// Padded, clamped end of the censored span.
    var end: CMTime
    /// IDs of every `WordToken` folded into this range; may be several
    /// after merging.
    var sourceTokenIDs: [UUID]

    /// The span as a `CMTimeRange`.
    var timeRange: CMTimeRange {
        CMTimeRange(start: start, end: end)
    }
}
