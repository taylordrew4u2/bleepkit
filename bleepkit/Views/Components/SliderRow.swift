//
//  SliderRow.swift
//  BleepKit
//

import SwiftUI

/// A labeled slider with a live value readout, used across the style forms.
struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// Formats the readout; defaults to two decimals.
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let step {
                Slider(value: $value, in: range, step: step)
                    .accessibilityLabel(title)
            } else {
                Slider(value: $value, in: range)
                    .accessibilityLabel(title)
            }
        }
    }
}
