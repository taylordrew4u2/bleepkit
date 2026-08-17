//
//  ImportView.swift
//  BleepKit
//

import AVFoundation
import OSLog
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The import flow: pick a video, watch it ingest, land in the editor.
struct ImportView: View {
    let viewModel: ImportViewModel

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .ready:
                ImportIdleView(viewModel: viewModel)
            case .importing(let step):
                LoadingStateView(message: step) {
                    viewModel.cancelImport()
                }
            case .failed(let message):
                ErrorStateView(title: "Import Failed", message: message, retryTitle: "Back") {
                    viewModel.reset()
                }
            }
        }
        // A successful import opens the editor immediately; going back
        // returns to the project list (audit 1.1).
        .navigationDestination(isPresented: editorPresented) {
            if case .ready(let source) = viewModel.phase {
                EditorView(project: source.project)
            }
        }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: {
                if case .ready = viewModel.phase { return true }
                return false
            },
            set: { if !$0 { viewModel.reset() } }
        )
    }
}

/// The idle screen: import buttons plus the saved-project list.
private struct ImportIdleView: View {
    let viewModel: ImportViewModel
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @State private var photosSelection: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var pendingDeletion: IndexSet?
    @State private var deleteFailureMessage: String?

    var body: some View {
        List {
            importSection
            projectsSection
        }
        .confirmationDialog(
            "Delete this project?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project and Video", role: .destructive) {
                if let pendingDeletion {
                    deleteProjects(at: pendingDeletion)
                }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text("The imported video and every edit are removed permanently. This can't be undone.")
        }
        .alert(
            "Couldn't Delete Project",
            isPresented: Binding(
                get: { deleteFailureMessage != nil },
                set: { if !$0 { deleteFailureMessage = nil } }
            )
        ) {
            Button("OK") { deleteFailureMessage = nil }
        } message: {
            Text(deleteFailureMessage ?? "")
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

    /// Two source cards side by side — the screen's primary action, given
    /// the visual weight of one instead of two plain list rows.
    private var importSection: some View {
        Section {
            HStack(spacing: Spacing.standard) {
                PhotosPicker(selection: $photosSelection, matching: .videos) {
                    ImportSourceCard(
                        icon: "photo.on.rectangle",
                        title: "Photos",
                        caption: "From your camera roll"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose from Photos")

                Button {
                    showsFileImporter = true
                } label: {
                    ImportSourceCard(
                        icon: "folder",
                        title: "Files",
                        caption: "Browse for a movie"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Import from Files")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } header: {
            Text("New Project")
        } footer: {
            Label(
                "Everything happens on this iPhone. Your video never leaves the device.",
                systemImage: "lock.iphone"
            )
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        if projects.isEmpty {
            Section("Projects") {
                HStack(spacing: Spacing.standard) {
                    Image(systemName: "film")
                        .font(.bleepTransportGlyph)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text("No projects yet")
                        // The blocks are the app's redaction motif in
                        // miniature; the accessibility label reads plainly.
                        (Text("Import a Reel and BleepKit finds the ")
                            + Text("████").foregroundStyle(Color.bleepAccent)
                            + Text(" for you."))
                            .font(.bleepMetadata)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Import a Reel and BleepKit finds the profanity for you.")
                    }
                }
                .padding(.vertical, Spacing.compact)
            }
        } else {
            Section {
                ForEach(projects) { project in
                    NavigationLink {
                        EditorView(project: project)
                    } label: {
                        ProjectRowView(project: project)
                    }
                }
                .onDelete { offsets in
                    pendingDeletion = offsets
                }
            } header: {
                HStack {
                    Text("Projects")
                    Spacer()
                    Text(projects.count, format: .number)
                        .monospacedDigit()
                }
            }
        }
    }

    private func deleteProjects(at offsets: IndexSet) {
        for index in offsets {
            do {
                try environment.projectStore.delete(projects[index])
            } catch {
                Logger.storage.error("Failed to delete project: \(error.localizedDescription)")
                deleteFailureMessage = error.localizedDescription
            }
        }
    }
}

/// One import source: an accented glyph over a title and caption, framed
/// as a sharp near-rectangle card.
private struct ImportSourceCard: View {
    let icon: String
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            Image(systemName: icon)
                .font(.bleepTransportGlyph)
                .foregroundStyle(Color.bleepAccent)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(title)
                    .font(.bleepEmphasis)
                    .foregroundStyle(.primary)
                Text(caption)
                    .font(.bleepMetadata)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum, alignment: .leading)
        .padding(Spacing.standard)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.control))
        // A hairline frame over the fill — the print-like rule that gives
        // the card its Redaction Desk edge.
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(.separator)
        )
        .accessibilityElement(children: .combine)
    }
}

/// One row in the saved-project list: source thumbnail, title, duration
/// and last-edit metadata, and where the project stands on censoring.
private struct ProjectRowView: View {
    let project: Project

    var body: some View {
        HStack(spacing: Spacing.standard) {
            ProjectThumbnailView(project: project)
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(project.title)
                    .lineLimit(2)
                Text("\(project.durationSeconds.timecodeString) · Edited \(project.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.bleepMetadata)
                    .foregroundStyle(.secondary)
                censorStatus
            }
        }
        .padding(.vertical, Spacing.tight)
    }

    /// The row's one project-specific fact: how many words are bleeped.
    /// A red stamp when there are bleeps, quiet fineprint otherwise.
    @ViewBuilder
    private var censorStatus: some View {
        let tokens = project.tokens
        if tokens.isEmpty {
            Text("Not transcribed yet")
                .font(.bleepFineprint)
                .foregroundStyle(.secondary)
        } else {
            let bleeps = tokens.count(where: \.isCensored)
            if bleeps == 0 {
                Text("No profanity found")
                    .font(.bleepFineprint)
                    .foregroundStyle(.secondary)
            } else {
                Text(bleeps == 1 ? "1 BLEEP" : "\(bleeps) BLEEPS")
                    .font(.bleepFineprint)
                    .foregroundStyle(Color.bleepAccent)
                    .padding(.horizontal, Spacing.tight)
                    .padding(.vertical, Spacing.hairline)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.control)
                            .strokeBorder(Color.bleepAccent)
                    )
                    .accessibilityLabel(bleeps == 1 ? "1 bleep" : "\(bleeps) bleeps")
            }
        }
    }
}

/// A frame from the project's source video, letterboxed on the video
/// backdrop while it loads (or when the source can't be read).
private struct ProjectThumbnailView: View {
    let project: Project
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            Color.bleepVideoBackdrop
            if let thumbnail {
                Image(decorative: thumbnail, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "film")
                    .font(.bleepControlLabel)
                    .foregroundStyle(Color.bleepOnVideo)
            }
        }
        .frame(width: ThumbnailSize.projectWidth, height: ThumbnailSize.projectHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.control)
                .strokeBorder(.separator)
        )
        .accessibilityHidden(true)
        .task(id: project.sourceFileName) {
            thumbnail = await Self.loadThumbnail(
                fileName: project.sourceFileName,
                durationSeconds: project.durationSeconds
            )
        }
    }

    /// Grabs a frame 10% into the video — frame zero is often black or a
    /// fade-in. Any failure just leaves the placeholder in place.
    private nonisolated static func loadThumbnail(
        fileName: String,
        durationSeconds: Double
    ) async -> CGImage? {
        guard let url = try? ProjectStore.sourceURL(forFileName: fileName) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(
            width: ThumbnailSize.projectMaxPixels,
            height: ThumbnailSize.projectMaxPixels
        )
        let time = CMTime(seconds: durationSeconds * 0.1, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}

