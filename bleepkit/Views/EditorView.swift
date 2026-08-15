//
//  EditorView.swift
//  BleepKit
//

import SwiftUI

/// The project editor: censored preview with transport controls, overlay
/// and censor-style settings, and the transcript word list.
struct EditorView: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: EditorViewModel?

    var body: some View {
        Group {
            if let viewModel {
                EditorContentView(viewModel: viewModel)
            } else {
                // One frame at most; the view model needs the environment.
                ProgressView()
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if viewModel == nil {
                let model = EditorViewModel(project: project, environment: environment)
                viewModel = model
                model.loadOrTranscribe()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Interruptions (calls, backgrounding) pause the preview; the
            // playhead observer already reconciles isPlaying if the system
            // paused the player itself.
            if newPhase != .active {
                viewModel?.pausePlayback()
            }
        }
    }
}

private struct EditorContentView: View {
    let viewModel: EditorViewModel
    @State private var showsExportSheet = false

    var body: some View {
        VStack(spacing: Spacing.standard) {
            previewArea
            if viewModel.project.overlayEnabled && !viewModel.project.overlayFollowsCaption {
                stickerPlacementHint
            }
            transportControls
        }
        .padding(.bottom, Spacing.compact)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                settingsMenu
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(!viewModel.previewReady)
                .accessibilityLabel("Export censored video")
            }
        }
        .sheet(isPresented: $showsExportSheet) {
            ExportView(editor: viewModel)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewArea: some View {
        GeometryReader { proxy in
            ZStack {
                PlayerView(
                    player: viewModel.player,
                    renderSize: viewModel.renderSize,
                    revision: viewModel.previewRevision,
                    buildOverlayLayers: { size, scale in
                        viewModel.buildPreviewLayers(targetSize: size, contentsScale: scale)
                    }
                )
                .gesture(overlayDragGesture(viewSize: proxy.size))

                if case .working(let step) = viewModel.transcriptionState {
                    LoadingStateView(message: step) {
                        viewModel.cancelTranscription()
                    }
                    .background(Color.bleepScrim)
                } else if let previewError = viewModel.previewError {
                    ErrorStateView(title: "Preview Failed", message: previewError) {
                        viewModel.refreshPreview()
                    }
                    .background(Color.bleepScrim)
                } else if !viewModel.previewReady {
                    // Without a preview there is nothing usable on screen, so
                    // a stalled transcription must explain itself here — not
                    // only in the Transcript screen.
                    switch viewModel.transcriptionState {
                    case .permissionDenied:
                        PermissionDeniedView(
                            title: "Speech Recognition Is Off",
                            message: "BleepKit transcribes on this device only — audio never leaves your iPhone. Allow Speech Recognition in Settings to continue."
                        )
                        .background(Color.bleepScrim)
                        .environment(\.colorScheme, .dark)
                    case .failed(let message):
                        ErrorStateView(title: "Transcription Failed", message: message) {
                            viewModel.transcribe()
                        }
                        .background(Color.bleepScrim)
                        .environment(\.colorScheme, .dark)
                    case .idle:
                        // Reached when the user cancels the first run.
                        ContentUnavailableView {
                            Label("Not Transcribed", systemImage: "waveform")
                        } description: {
                            Text("Transcribe the video to detect words to censor.")
                        } actions: {
                            Button("Transcribe") {
                                viewModel.transcribe()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .background(Color.bleepScrim)
                        .environment(\.colorScheme, .dark)
                    case .working, .ready:
                        // Transcript in hand; the composition is still building.
                        ProgressView()
                            .controlSize(.large)
                            .tint(.bleepOnVideo)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// Surfaces the otherwise-invisible tap-to-place gesture, and points
    /// VoiceOver users at the slider equivalent in the Censoring screen.
    private var stickerPlacementHint: some View {
        Label("Tap the video to place the sticker", systemImage: "hand.tap")
            .font(.bleepControlLabel)
            .foregroundStyle(.secondary)
            .accessibilityHint("Sticker position sliders are available on the Censoring screen.")
    }

    /// Drag on the preview to pin the overlay sticker there. The video is
    /// letterboxed at its native aspect inside the view; the touch point is
    /// normalized to that rect, matching what `PlayerContainerView` shows.
    private func overlayDragGesture(viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard viewModel.project.overlayEnabled,
                      !viewModel.project.overlayFollowsCaption,
                      viewSize.width > 1, viewSize.height > 1,
                      viewModel.renderSize.height > 0 else { return }
                let aspect = viewModel.renderSize.width / viewModel.renderSize.height
                var videoRect = CGRect(origin: .zero, size: viewSize)
                if viewSize.width / viewSize.height > aspect {
                    // Pillarboxed: full height, centered horizontally.
                    let width = viewSize.height * aspect
                    videoRect = CGRect(x: (viewSize.width - width) / 2, y: 0, width: width, height: viewSize.height)
                } else {
                    // Letterboxed: full width, centered vertically.
                    let height = viewSize.width / aspect
                    videoRect = CGRect(x: 0, y: (viewSize.height - height) / 2, width: viewSize.width, height: height)
                }
                guard videoRect.contains(value.location) else { return }
                viewModel.setOverlayPosition(
                    x: (value.location.x - videoRect.minX) / videoRect.width,
                    y: (value.location.y - videoRect.minY) / videoRect.height
                )
            }
    }

    // MARK: Transport

    private var transportControls: some View {
        VStack(spacing: Spacing.compact) {
            ScrubberView(
                currentSeconds: viewModel.currentSeconds,
                durationSeconds: viewModel.assetDurationSeconds,
                onScrub: { viewModel.scrub(to: $0) }
            )
            .padding(.horizontal)

            HStack(spacing: Spacing.wide) {
                Button {
                    viewModel.stepFrames(-1)
                } label: {
                    Image(systemName: "backward.frame")
                }
                .accessibilityLabel("Step back one frame")

                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.bleepPlayGlyph)
                }
                .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")

                Button {
                    viewModel.stepFrames(1)
                } label: {
                    Image(systemName: "forward.frame")
                }
                .accessibilityLabel("Step forward one frame")
            }
            .font(.bleepTransportGlyph)
            .disabled(!viewModel.previewReady)

            HStack(spacing: Spacing.standard) {
                NavigationLink {
                    WordListView(viewModel: viewModel)
                } label: {
                    Label(transcriptLabel, systemImage: "text.quote")
                }
                NavigationLink {
                    CaptionStyleView(viewModel: viewModel)
                } label: {
                    Label("Captions", systemImage: "textformat")
                }
                NavigationLink {
                    CensorStyleView(viewModel: viewModel)
                } label: {
                    Label("Censoring", systemImage: "speaker.slash")
                }
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: Radius.control))
            .labelStyle(.titleAndIcon)
            .font(.bleepControlLabel)
        }
    }

    private var transcriptLabel: String {
        let tokens = viewModel.project.tokens
        guard !tokens.isEmpty else { return "Transcript" }
        return "Transcript · \(tokens.filter(\.isCensored).count) censored"
    }

    // MARK: Settings

    private var settingsMenu: some View {
        Menu {
            Section("Caption censor style") {
                Picker("Caption censor style", selection: censorStyleBinding) {
                    Text("Asterisks (f***)").tag(CensorStyleChoice.asterisks)
                    Text("Black bar").tag(CensorStyleChoice.blackBar)
                    Text("Emoji 🤬").tag(CensorStyleChoice.emoji)
                }
            }
            Section("Video overlay") {
                Toggle("Show sticker over video", isOn: overlayEnabledBinding)
                if viewModel.project.overlayEnabled {
                    Picker("Sticker", selection: overlayStickerBinding) {
                        ForEach(StickerRenderer.bundledEmoji, id: \.self) { emoji in
                            Text(emoji).tag(emoji)
                        }
                    }
                    Toggle("Follow captions", isOn: overlayFollowsBinding)
                }
            }
        } label: {
            Label("Style", systemImage: "paintbrush")
        }
    }

    /// The censor styles offered in the quick menu.
    private enum CensorStyleChoice: Hashable {
        case asterisks, blackBar, emoji

        init(_ style: CensorStyle) {
            switch style {
            case .asterisks: self = .asterisks
            case .blackBar, .image: self = .blackBar
            case .emoji: self = .emoji
            }
        }

        var style: CensorStyle {
            switch self {
            case .asterisks: .asterisks
            case .blackBar: .blackBar
            case .emoji: .emoji("🤬")
            }
        }
    }

    private var censorStyleBinding: Binding<CensorStyleChoice> {
        Binding(
            get: { CensorStyleChoice(viewModel.project.censorStyle) },
            set: { viewModel.setCensorStyle($0.style) }
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
}
