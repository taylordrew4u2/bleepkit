//
//  CensorStyleView.swift
//  BleepKit
//

import SwiftUI

/// Censor treatment and beep controls. Beep changes rebuild the audio mix;
/// treatment changes rebuild the caption layers.
struct CensorStyleView: View {
    let viewModel: EditorViewModel

    /// Emoji offered for the emoji caption treatment (same set as the
    /// overlay stickers).
    private let emojiChoices = StickerRenderer.bundledEmoji

    var body: some View {
        Form {
            Section {
                Picker("Treatment", selection: treatmentBinding) {
                    Text("Asterisks (f***)").tag(Treatment.asterisks)
                    Text("Black bar").tag(Treatment.blackBar)
                    Text("Emoji").tag(Treatment.emoji)
                }
                if case .emoji(let current) = viewModel.project.censorStyle {
                    Picker("Emoji", selection: Binding(
                        get: { current },
                        set: { viewModel.setCensorStyle(.emoji($0)) }
                    )) {
                        ForEach(emojiChoices, id: \.self) { emoji in
                            Text(emoji).tag(emoji)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Censored words in captions")
            } footer: {
                Text("The censored word keeps its place in the line — only how it looks changes.")
            }

            Section {
                SliderRow(
                    title: "Beep tone",
                    value: beepBinding(get: \.frequencyHz, set: { $0.frequencyHz = $1 }),
                    range: 400...2000,
                    step: 50,
                    format: { String(format: "%.0f Hz", $0) }
                )
                SliderRow(
                    title: "Beep loudness",
                    value: beepBinding(get: \.levelDBFS, set: { $0.levelDBFS = $1 }),
                    range: -24...(-6),
                    step: 1,
                    format: { String(format: "%.0f dB", $0) }
                )
            } header: {
                Text("Beep")
            }

            Section {
                SliderRow(
                    title: "Padding",
                    value: beepBinding(get: \.paddingSeconds, set: { $0.paddingSeconds = $1 }),
                    range: 0...0.2,
                    step: 0.01,
                    format: { String(format: "%.0f ms", $0 * 1000) }
                )
                SliderRow(
                    title: "Fade length",
                    value: beepBinding(get: \.rampSeconds, set: { $0.rampSeconds = $1 }),
                    range: 0.005...0.05,
                    step: 0.005,
                    format: { String(format: "%.0f ms", $0 * 1000) }
                )
            } header: {
                Text("Timing")
            } footer: {
                Text("Padding extends the censored span on both sides so the start or end of a word never leaks past the beep. 60 ms works for most clips.")
            }
        }
        .navigationTitle("Censoring")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The caption treatments offered here.
    private enum Treatment: Hashable {
        case asterisks, blackBar, emoji
    }

    private var treatmentBinding: Binding<Treatment> {
        Binding(
            get: {
                switch viewModel.project.censorStyle {
                case .asterisks: .asterisks
                case .blackBar, .image: .blackBar
                case .emoji: .emoji
                }
            },
            set: { choice in
                switch choice {
                case .asterisks: viewModel.setCensorStyle(.asterisks)
                case .blackBar: viewModel.setCensorStyle(.blackBar)
                case .emoji: viewModel.setCensorStyle(.emoji(emojiChoices[0]))
                }
            }
        )
    }

    private func beepBinding(
        get: @escaping (BeepSettings) -> Double,
        set: @escaping (inout BeepSettings, Double) -> Void
    ) -> Binding<Double> {
        Binding(
            get: { get(viewModel.project.beepSettings) },
            set: { newValue in
                var settings = viewModel.project.beepSettings
                set(&settings, newValue)
                viewModel.setBeepSettings(settings)
            }
        )
    }
}
