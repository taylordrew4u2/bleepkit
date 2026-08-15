//
//  ScrubberView.swift
//  BleepKit
//

import SwiftUI

/// Timeline scrubber with a current-time readout.
struct ScrubberView: View {
    /// Playhead position in seconds (read from the player).
    let currentSeconds: Double
    let durationSeconds: Double
    /// Called as the user drags.
    let onScrub: (Double) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { min(currentSeconds, durationSeconds) },
                    set: { onScrub($0) }
                ),
                in: 0...max(durationSeconds, 0.01)
            )
            .disabled(durationSeconds <= 0)
            .accessibilityLabel("Timeline")
            HStack {
                Text(currentSeconds.timecodeString)
                Spacer()
                Text(durationSeconds.timecodeString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }
}
