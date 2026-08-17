//
//  CaptionStyleView.swift
//  BleepKit
//

import SwiftUI

/// Caption appearance controls. Every change persists immediately and
/// refreshes the preview's layer trees; system fonts only.
struct CaptionStyleView: View {
    let viewModel: EditorViewModel

    var body: some View {
        Form {
            Section("Font") {
                Picker("Family", selection: binding(\.fontFamily)) {
                    Text("SF Pro").tag(CaptionStyle.FontFamily.sfPro)
                    Text("SF Pro Rounded").tag(CaptionStyle.FontFamily.sfProRounded)
                    Text("New York").tag(CaptionStyle.FontFamily.newYork)
                }
                SliderRow(
                    title: "Size",
                    value: doubleBinding(get: { Double($0.fontSize) }, set: { $0.fontSize = CGFloat($1) }),
                    range: 40...120,
                    step: 2,
                    format: { String(format: "%.0f pt", $0) }
                )
                SliderRow(
                    title: "Weight",
                    value: doubleBinding(get: { Double($0.fontWeight) }, set: { $0.fontWeight = Int($1) }),
                    range: 100...900,
                    step: 100,
                    format: { String(format: "%.0f", $0) }
                )
            }

            Section("Colors") {
                ColorPickerRow(title: "Text", hex: binding(\.fillColorHex))
                ColorPickerRow(title: "Spoken word", hex: binding(\.activeColorHex))
                ColorPickerRow(title: "Outline", hex: binding(\.strokeColorHex))
                SliderRow(
                    title: "Outline width",
                    value: doubleBinding(get: { Double($0.strokeWidth) }, set: { $0.strokeWidth = CGFloat($1) }),
                    range: 0...12,
                    step: 1,
                    format: { String(format: "%.0f pt", $0) }
                )
            }

            Section("Shadow") {
                SliderRow(
                    title: "Opacity",
                    value: doubleBinding(get: { Double($0.shadowOpacity) }, set: { $0.shadowOpacity = Float($1) }),
                    range: 0...1,
                    step: 0.05,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
                SliderRow(
                    title: "Radius",
                    value: doubleBinding(get: { Double($0.shadowRadius) }, set: { $0.shadowRadius = CGFloat($1) }),
                    range: 0...20,
                    step: 1,
                    format: { String(format: "%.0f pt", $0) }
                )
            }

            Section("Background pill") {
                Toggle("Show background", isOn: binding(\.backgroundEnabled))
                if viewModel.project.captionStyle.backgroundEnabled {
                    ColorPickerRow(title: "Color", hex: binding(\.backgroundColorHex))
                    SliderRow(
                        title: "Opacity",
                        value: doubleBinding(get: { Double($0.backgroundOpacity) }, set: { $0.backgroundOpacity = Float($1) }),
                        range: 0...1,
                        step: 0.05,
                        format: { String(format: "%.0f%%", $0 * 100) }
                    )
                    SliderRow(
                        title: "Corner radius",
                        value: doubleBinding(get: { Double($0.backgroundCornerRadius) }, set: { $0.backgroundCornerRadius = CGFloat($1) }),
                        range: 0...40,
                        step: 2,
                        format: { String(format: "%.0f pt", $0) }
                    )
                    SliderRow(
                        title: "Padding",
                        value: doubleBinding(get: { Double($0.backgroundPadding) }, set: { $0.backgroundPadding = CGFloat($1) }),
                        range: 0...48,
                        step: 2,
                        format: { String(format: "%.0f pt", $0) }
                    )
                }
            }

            Section {
                SliderRow(
                    title: "Vertical position",
                    value: doubleBinding(get: { Double($0.verticalPositionNormalized) }, set: { $0.verticalPositionNormalized = CGFloat($1) }),
                    range: 0.15...0.88,
                    step: nil,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
                Stepper(
                    "Words per line: \(viewModel.project.captionStyle.maxWordsPerLine)",
                    value: doubleBinding(get: { Double($0.maxWordsPerLine) }, set: { $0.maxWordsPerLine = Int($1) }),
                    in: 1...5,
                    step: 1
                )
                SliderRow(
                    title: "Max seconds per line",
                    value: doubleBinding(get: { $0.maxSecondsPerLine }, set: { $0.maxSecondsPerLine = $1 }),
                    range: 0.8...3.0,
                    step: 0.1,
                    format: { String(format: "%.1f s", $0) }
                )
            } header: {
                Text("Layout")
            } footer: {
                Text("The default position sits below center to clear Instagram's interface.")
            }
        }
        .navigationTitle("Caption Style")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A binding straight into one caption-style property; writing persists
    /// the style and refreshes the preview.
    private func binding<Value>(_ keyPath: WritableKeyPath<CaptionStyle, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.project.captionStyle[keyPath: keyPath] },
            set: { newValue in
                var style = viewModel.project.captionStyle
                style[keyPath: keyPath] = newValue
                viewModel.setCaptionStyle(style)
            }
        )
    }

    /// A Double-typed binding for sliders over non-Double properties.
    private func doubleBinding(
        get: @escaping (CaptionStyle) -> Double,
        set: @escaping (inout CaptionStyle, Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { get(viewModel.project.captionStyle) },
            set: { newValue in
                var style = viewModel.project.captionStyle
                set(&style, newValue)
                viewModel.setCaptionStyle(style)
            }
        )
    }
}
