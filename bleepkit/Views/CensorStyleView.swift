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
                if viewModel.project.tokens.isEmpty {
                    Text("Transcribe the video to pick words.")
                        .foregroundStyle(.secondary)
                } else {
                    WordChipGrid(viewModel: viewModel)
                }
            } header: {
                Text("Words to bleep")
            } footer: {
                Text("Tap a word to bleep or unbleep it — the preview behind this sheet updates right away. Timing details and automatic-detection controls live in the Transcript.")
            }

            Section {
                Toggle("Show sticker during bleeps", isOn: overlayEnabledBinding)
                if viewModel.project.overlayEnabled {
                    Picker("Sticker", selection: overlayStickerBinding) {
                        ForEach(emojiChoices, id: \.self) { emoji in
                            Text(emoji).tag(emoji)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Follow captions", isOn: overlayFollowsBinding)
                }
            } header: {
                Text("Sticker")
            } footer: {
                Text("The sticker appears only while censored words are playing.")
            }

            if viewModel.project.overlayEnabled && !viewModel.project.overlayFollowsCaption {
                Section {
                    SliderRow(
                        title: "Horizontal",
                        value: overlayPositionXBinding,
                        range: 0...1,
                        step: 0.01,
                        format: { String(format: "%.0f%%", $0 * 100) }
                    )
                    SliderRow(
                        title: "Vertical",
                        value: overlayPositionYBinding,
                        range: 0...1,
                        step: 0.01,
                        format: { String(format: "%.0f%%", $0 * 100) }
                    )
                } header: {
                    Text("Sticker position")
                } footer: {
                    Text("Measured from the top-left of the video. You can also tap the video preview to place the sticker.")
                }
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

    private var overlayEnabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.project.overlayEnabled },
            set: { viewModel.setOverlayEnabled($0) }
        )
    }

    private var overlayStickerBinding: Binding<String> {
        Binding(
            get: {
                let identifier = viewModel.project.overlayAssetIdentifier ?? ""
                return identifier.hasPrefix("emoji:")
                    ? String(identifier.dropFirst("emoji:".count))
                    : StickerRenderer.bundledEmoji[0]
            },
            set: { viewModel.setOverlaySticker($0) }
        )
    }

    private var overlayFollowsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.project.overlayFollowsCaption },
            set: { viewModel.setOverlayFollowsCaption($0) }
        )
    }

    /// Slider equivalents of the tap-to-place gesture, so the sticker can be
    /// positioned with VoiceOver and Switch Control.
    private var overlayPositionXBinding: Binding<Double> {
        Binding(
            get: { viewModel.project.overlayPositionX },
            set: { viewModel.setOverlayPosition(x: $0, y: viewModel.project.overlayPositionY) }
        )
    }

    private var overlayPositionYBinding: Binding<Double> {
        Binding(
            get: { viewModel.project.overlayPositionY },
            set: { viewModel.setOverlayPosition(x: viewModel.project.overlayPositionX, y: $0) }
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

/// Every transcript word as a tappable chip: bleeped words are filled
/// accent capsules, clean words are quiet fills. Tapping toggles the
/// word's override and seeks the preview to it, so the change is heard
/// and seen immediately behind the sheet.
private struct WordChipGrid: View {
    let viewModel: EditorViewModel

    /// Uniform cell width the adaptive grid packs chips into.
    private static let chipMinWidth: CGFloat = 84

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Self.chipMinWidth), spacing: Spacing.compact)],
            spacing: Spacing.compact
        ) {
            ForEach(viewModel.project.tokens) { token in
                Button {
                    viewModel.setOverride(forTokenID: token.id, to: !token.isCensored)
                    viewModel.seekToToken(token)
                } label: {
                    Text(token.text)
                        .font(.bleepControlLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
                        .foregroundStyle(token.isCensored ? Color.bleepOnAccent : .primary)
                        .background(
                            token.isCensored
                                ? AnyShapeStyle(Color.bleepAccent)
                                : AnyShapeStyle(.tertiary),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(token.isCensored ? "\(token.text), bleeped" : "\(token.text), not bleeped")
                .accessibilityHint("Toggles the bleep and plays the word")
            }
        }
        .padding(.vertical, Spacing.tight)
    }
}
