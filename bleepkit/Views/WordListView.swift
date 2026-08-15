//
//  WordListView.swift
//  BleepKit
//

import SwiftUI

/// The transcript screen: lists every token with its text, timestamp,
/// censor state, and a per-word override control. Tapping a word seeks the
/// editor's preview to it. Severity tiers are toggled from the toolbar
/// (slurs are always censored and cannot be toggled).
///
/// Shares the editor's view model so overrides refresh the preview live.
struct WordListView: View {
    let viewModel: EditorViewModel

    var body: some View {
        content
            .navigationTitle("Transcript")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.transcriptionState {
        case .idle:
            // Reached after a cancelled run.
            ContentUnavailableView {
                Label("Not Transcribed", systemImage: "waveform")
            } description: {
                Text("Transcribe the video to see every word with its timing.")
            } actions: {
                Button("Transcribe") {
                    viewModel.transcribe()
                }
                .buttonStyle(.borderedProminent)
            }
        case .working(let step):
            LoadingStateView(message: step) {
                viewModel.cancelTranscription()
            }
        case .ready(let tokens):
            tokenList(tokens)
        case .permissionDenied:
            PermissionDeniedView(
                title: "Speech Recognition Is Off",
                message: "BleepKit transcribes on this device only — audio never leaves your iPhone. Allow Speech Recognition in Settings to continue."
            )
        case .failed(let message):
            ErrorStateView(title: "Transcription Failed", message: message) {
                viewModel.transcribe()
            }
        }
    }

    @ViewBuilder
    private func tokenList(_ tokens: [WordToken]) -> some View {
        if tokens.isEmpty {
            // Audio exists but the engine heard no words.
            ContentUnavailableView {
                Label("No Speech Detected", systemImage: "waveform.slash")
            } description: {
                Text("The video's audio doesn't seem to contain any recognizable speech. The video can still be exported unchanged.")
            } actions: {
                Button("Try Again") {
                    viewModel.transcribe()
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            filledTokenList(tokens)
        }
    }

    private func filledTokenList(_ tokens: [WordToken]) -> some View {
        List {
            Section {
                ForEach(tokens) { token in
                    TokenRow(token: token, viewModel: viewModel)
                }
            } header: {
                Text("\(tokens.count) words · \(tokens.filter(\.isCensored).count) censored")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let notice = viewModel.localeNotice {
                        Text(notice)
                    }
                    if let engine = viewModel.engineIdentifier {
                        Text("Engine: \(engine)")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Censor severities") {
                        Toggle("Mild (damn, hell…)", isOn: severityBinding(.mild))
                        Toggle("Strong", isOn: severityBinding(.strong))
                        Label("Slurs: always censored", systemImage: "lock.fill")
                    }
                    Section {
                        Button("Re-transcribe", systemImage: "arrow.clockwise") {
                            viewModel.transcribe()
                        }
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func severityBinding(_ severity: ProfanitySeverity) -> Binding<Bool> {
        Binding(
            get: { viewModel.isSeverityEnabled(severity) },
            set: { viewModel.setSeverity(severity, enabled: $0) }
        )
    }
}

/// One transcript row: censor-state indicator, word, timing, and an
/// override picker (automatic / always censor / never censor). Tapping the
/// row seeks the preview to the word.
private struct TokenRow: View {
    let token: WordToken
    let viewModel: EditorViewModel

    /// The three override choices, bridged to `WordToken.userOverride`.
    private enum OverrideChoice: Hashable {
        case automatic, censor, allow

        init(_ override: Bool?) {
            switch override {
            case nil: self = .automatic
            case true?: self = .censor
            case false?: self = .allow
            }
        }

        var overrideValue: Bool? {
            switch self {
            case .automatic: nil
            case .censor: true
            case .allow: false
            }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.standard) {
            Button {
                viewModel.seekToToken(token)
            } label: {
                HStack(spacing: Spacing.standard) {
                    Image(systemName: token.isCensored ? "speaker.slash.fill" : "checkmark.circle")
                        .foregroundStyle(token.isCensored ? Color.bleepAccent : Color.secondary)
                        .accessibilityLabel(token.isCensored ? "Censored" : "Not censored")
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(token.text)
                            .foregroundStyle(token.isCensored ? Color.bleepAccent : .primary)
                        if token.userOverride != nil {
                            Text(token.userOverride == true ? "Always censored" : "Never censored")
                                .font(.bleepFineprint)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: Spacing.hairline) {
                        Text(token.startSeconds.timecodeString)
                            .font(.bleepTimecode)
                        Text("\(Int((token.durationSeconds * 1000).rounded())) ms")
                            .font(.bleepFineprintTimecode)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Seeks the preview to this word")

            Menu {
                Picker("Censoring", selection: choiceBinding) {
                    Label("Automatic", systemImage: "wand.and.stars").tag(OverrideChoice.automatic)
                    Label("Always censor", systemImage: "speaker.slash").tag(OverrideChoice.censor)
                    Label("Never censor", systemImage: "speaker.wave.2").tag(OverrideChoice.allow)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.tint)
            }
            .accessibilityLabel("Censor override for \(token.text)")
        }
    }

    private var choiceBinding: Binding<OverrideChoice> {
        Binding(
            get: { OverrideChoice(token.userOverride) },
            set: { viewModel.setOverride(forTokenID: token.id, to: $0.overrideValue) }
        )
    }
}
