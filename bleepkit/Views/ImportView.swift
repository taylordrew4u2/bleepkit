//
//  ImportView.swift
//  BleepKit
//

import AVFAudio
import AVFoundation
import CoreGraphics
import OSLog
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The import flow: pick a video, watch it ingest, inspect the result.
struct ImportView: View {
    let viewModel: ImportViewModel

    var body: some View {
        switch viewModel.phase {
        case .idle:
            ImportIdleView(viewModel: viewModel)
        case .importing(let step):
            LoadingStateView(message: step) {
                viewModel.cancelImport()
            }
        case .ready(let source):
            SourceDetailsView(source: source) {
                viewModel.reset()
            }
        case .failed(let message):
            ErrorStateView(title: "Import Failed", message: message, retryTitle: "Back") {
                viewModel.reset()
            }
        }
    }
}

/// The idle screen: import buttons plus the saved-project list.
private struct ImportIdleView: View {
    let viewModel: ImportViewModel
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @State private var photosSelection: PhotosPickerItem?
    @State private var showsFileImporter = false

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $photosSelection, matching: .videos) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    showsFileImporter = true
                } label: {
                    Label("Import from Files", systemImage: "folder")
                }
            } header: {
                Text("Import a Video")
            } footer: {
                Text("Everything happens on this iPhone. Your video never leaves the device.")
            }

            if projects.isEmpty {
                Section {
                    EmptyStateView(
                        title: "No Projects Yet",
                        systemImage: "video.badge.waveform",
                        message: "Import a Reel to transcribe it and censor profanity."
                    )
                }
            } else {
                Section("Projects") {
                    ForEach(projects) { project in
                        NavigationLink {
                            EditorView(project: project)
                        } label: {
                            ProjectRowView(project: project)
                        }
                    }
                    .onDelete(perform: deleteProjects)
                }
            }
        }
        .onChange(of: photosSelection) { _, newValue in
            guard let newValue else { return }
            photosSelection = nil
            viewModel.importPhotosSelection(newValue)
        }
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.movie]
        ) { result in
            switch result {
            case .success(let url):
                viewModel.importFile(
                    at: url,
                    suggestedTitle: url.deletingPathExtension().lastPathComponent
                )
            case .failure:
                viewModel.fail(with: result.failureMessage ?? "The file couldn't be opened.")
            }
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            do {
                try environment.projectStore.delete(projects[index])
            } catch {
                Logger.storage.error("Failed to delete project: \(error.localizedDescription)")
            }
        }
    }
}

/// One row in the saved-project list.
private struct ProjectRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.title)
            Text("\(project.durationSeconds.timecodeString) · \(project.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Details of a just-imported source: duration, geometry, frame rate, and
/// the extracted audio file with in-app playback.
private struct SourceDetailsView: View {
    let source: ImportViewModel.ImportedSource
    let onDone: () -> Void

    var body: some View {
        List {
            Section("Video") {
                LabeledContent("Title", value: source.project.title)
                LabeledContent("Duration", value: source.metadata.durationSeconds.timecodeString)
                LabeledContent("Source size", value: sizeText(source.metadata.naturalSize))
                LabeledContent("Oriented size", value: sizeText(source.metadata.displaySize))
                LabeledContent("Frame rate", value: String(format: "%.2f fps", source.metadata.nominalFrameRate))
                LabeledContent("Stored as", value: source.project.sourceFileName)
                    .font(.caption)
            }
            Section("Audio") {
                if let audioURL = source.extractedAudioURL {
                    LabeledContent("Extracted audio", value: FileSize.string(for: audioURL))
                    AudioPlaybackRow(url: audioURL)
                } else {
                    Text("This video has no audio track. Captions will still work; audio censoring will be skipped.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Imported")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
            }
        }
    }

    private func sizeText(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }
}

/// Plays the extracted `.m4a` so the import can be verified end to end.
private struct AudioPlaybackRow: View {
    let url: URL
    @State private var player: AVPlayer?

    private var isPlaying: Bool { player != nil }

    var body: some View {
        Button {
            if isPlaying {
                stop()
            } else {
                play()
            }
        } label: {
            Label(
                isPlaying ? "Stop" : "Play Extracted Audio",
                systemImage: isPlaying ? "stop.circle" : "play.circle"
            )
        }
        .onDisappear {
            stop()
        }
    }

    private func play() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            Logger.audio.error("Audio session activation failed: \(error.localizedDescription)")
        }
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        newPlayer.play()
    }

    private func stop() {
        player?.pause()
        player = nil
    }
}

/// Formats on-disk file sizes for display.
private enum FileSize {
    static func string(for url: URL) -> String {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard let bytes = values.fileSize else { return "—" }
            return Int64(bytes).formatted(.byteCount(style: .file))
        } catch {
            return "—"
        }
    }
}
