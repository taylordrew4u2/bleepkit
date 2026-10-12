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
        VStack(spacing: Spacing.tight) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(title)
                        .fixedSize()
                    Spacer()
                    readout
                        .fixedSize()
                }
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(title)
                    readout
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityHidden(true)
            if let step {
                Slider(value: $value, in: range, step: step)
                    .accessibilityLabel(title)
                    .accessibilityValue(format(value))
            } else {
                Slider(value: $value, in: range)
                    .accessibilityLabel(title)
                    .accessibilityValue(format(value))
            }
        }
    }

    private var readout: some View {
        Text(format(value))
            .font(.bleepDetailValue)
            .foregroundStyle(.secondary)
    }
}
