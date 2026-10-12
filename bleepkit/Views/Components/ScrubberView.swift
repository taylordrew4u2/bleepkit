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
    /// The same padded spans used by the audio censor and export.
    var censorRanges: [CensorRange] = []
    /// Called as the user drags.
    let onScrub: (Double) -> Void

    var body: some View {
        VStack(spacing: Spacing.tight) {
            Slider(
                value: Binding(
                    get: { min(currentSeconds, durationSeconds) },
                    set: { onScrub($0) }
                ),
                in: 0...max(durationSeconds, 0.01)
            )
            .disabled(durationSeconds <= 0)
            .accessibilityLabel("Timeline")
            .accessibilityValue("\(currentSeconds.timecodeString) of \(durationSeconds.timecodeString)")
            if !censorRanges.isEmpty {
                censorMarkers
                Label("Bleeped sections", systemImage: "speaker.slash")
                    .font(.bleepFineprint)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text(currentSeconds.timecodeString)
                Spacer()
                Text(durationSeconds.timecodeString)
            }
            .font(.bleepTimecode)
            .foregroundStyle(.secondary)
        }
    }

    private var censorMarkers: some View {
        Canvas { context, size in
            for interval in TimelineReview.normalizedIntervals(
                for: censorRanges,
                durationSeconds: durationSeconds
            ) {
                let start = CGFloat(interval.lowerBound) * size.width
                let end = CGFloat(interval.upperBound) * size.width
                let width = min(max(end - start, 2), size.width)
                let rect = CGRect(
                    x: min(start, size.width - width),
                    y: 0,
                    width: width,
                    height: size.height
                )
                context.fill(Path(roundedRect: rect, cornerRadius: Radius.control), with: .color(.bleepAccent))
            }
        }
        .frame(height: Spacing.compact)
        .padding(.horizontal, Spacing.compact)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
