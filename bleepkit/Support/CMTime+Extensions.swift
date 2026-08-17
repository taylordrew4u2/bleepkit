//
//  CMTime+Extensions.swift
//  BleepKit
//

import CoreMedia
import Foundation

nonisolated extension CMTime {
    /// Timescale used for every time value in the project; divides evenly
    /// into 24, 25, 30, and 60 fps timelines.
    static let projectTimescale: CMTimeScale = 600

    /// A time at the project-wide timescale.
    static func projectSeconds(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: projectTimescale)
    }
}

nonisolated extension Double {
    /// "m:ss.mmm" timecode for UI display.
    var timecodeString: String {
        guard isFinite, self >= 0 else { return "0:00.000" }
        let totalMilliseconds = Int((self * 1000).rounded())
        let minutes = totalMilliseconds / 60_000
        let seconds = (totalMilliseconds % 60_000) / 1_000
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "%d:%02d.%03d", minutes, seconds, milliseconds)
    }
}
