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

/// The idle dashboard: the new-project actions up top, the most recent
/// project as a continue-editing hero, and the rest in a grid.
private struct ImportIdleView: View {
    let viewModel: ImportViewModel
    @Environment(AppEnvironment.self) private var environment
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @State private var photosSelection: PhotosPickerItem?
    @State private var showsFileImporter = false
    @State private var pendingDeletion: Project?
    @State private var deleteFailureMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.roomy) {
                newProjectControls
                if let current = projects.first {
                    continueEditingSection(current)
                }
                if projects.isEmpty {
                    firstImportCard
                } else if projects.count > 1 {
                    allProjectsSection
                }
                privacyFootnote
            }
            .padding(.horizontal)
            .padding(.vertical, Spacing.standard)
        }
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
        .mastheadTagline(subtitleText)
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
                    delete(pendingDeletion)
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

    // MARK: Header

    private var titleText: String {
        switch projects.count {
        case 0: return "Projects"
        case 1: return "1 project"
        default: return "\(projects.count) projects"
        }
    }

    /// "2.1 GB free · 3 need review" — the desk's vital signs.
    private var subtitleText: String {
        var parts: [String] = []
        if let free = Self.freeSpaceText() {
            parts.append(free)
        }
        let review = projects.count { project in
            project.tokens.contains { $0.detectedProfane && $0.userOverride == nil }
        }
        if review > 0 {
            parts.append(review == 1 ? "1 needs review" : "\(review) need review")
        }
        return parts.joined(separator: " · ")
    }

    private static func freeSpaceText() -> String? {
        let values = try? URL.documentsDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return "\(capacity.formatted(.byteCount(style: .file))) free"
    }

    // MARK: Sections

    /// The screen's primary action: a full-width accent pill for Photos,
    /// with the Files importer as a quieter chip beneath it.
    private var newProjectControls: some View {
        VStack(spacing: Spacing.standard) {
            PhotosPicker(selection: $photosSelection, matching: .videos) {
                Label("New project", systemImage: "plus")
                    .font(.bleepEmphasis)
                    .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .foregroundStyle(Color.bleepOnAccent)
            .accessibilityLabel("Choose from Photos")

            Button {
                showsFileImporter = true
            } label: {
                Label("Import from Files", systemImage: "square.and.arrow.down")
                    .font(.bleepControlLabel)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: .infinity)
        }
    }

    private func continueEditingSection(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text("Continue editing")
                    .font(.bleepEmphasis)
                Spacer()
                Text("Saved \(project.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.bleepFineprint)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            NavigationLink {
                EditorView(project: project)
            } label: {
                ContinueEditingCard(project: project)
            }
            .buttonStyle(.plain)
            .contextMenu {
                deleteMenuButton(for: project)
            }
        }
    }

    private var allProjectsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text("All projects")
                    .font(.bleepEmphasis)
                Spacer()
                Text("Recent")
                    .font(.bleepFineprint)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Spacing.standard),
                    GridItem(.flexible(), spacing: Spacing.standard),
                ],
                alignment: .leading,
                spacing: Spacing.standard
            ) {
                // The hero above is the newest project; the grid holds the rest.
                ForEach(Array(projects.dropFirst())) { project in
                    NavigationLink {
                        EditorView(project: project)
                    } label: {
                        ProjectGridCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        deleteMenuButton(for: project)
                    }
                }
            }
        }
    }

    /// Hero-sized invitation shown before the first import.
    private var firstImportCard: some View {
        Button {
            showsFileImporter = true
        } label: {
            VStack(spacing: Spacing.compact) {
                Image(systemName: "arrow.down.circle")
                    .font(.bleepTransportGlyph)
                    .foregroundStyle(Color.bleepAccent)
                Text("Drop in your first Reel")
                    .font(.bleepEmphasis)
                (Text("It gets transcribed and the ")
                    + Text("████").foregroundStyle(Color.bleepAccent)
                    + Text(" found for you — or browse files."))
                    .font(.bleepMetadata)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("It gets transcribed and the profanity found for you — or browse files.")
            }
            .multilineTextAlignment(.center)
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity)
            .frame(height: ThumbnailSize.heroHeight)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(.separator)
            )
        }
        .buttonStyle(.plain)
    }

    private var privacyFootnote: some View {
        Label(
            "Everything happens on this iPhone. Your video never leaves the device.",
            systemImage: "lock.iphone"
        )
        .font(.bleepFineprint)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    // MARK: Deletion

    private func deleteMenuButton(for project: Project) -> some View {
        Button("Delete Project…", systemImage: "trash", role: .destructive) {
            pendingDeletion = project
        }
    }

    private func delete(_ project: Project) {
        do {
            try environment.projectStore.delete(project)
        } catch {
            Logger.storage.error("Failed to delete project: \(error.localizedDescription)")
            deleteFailureMessage = error.localizedDescription
        }
    }
}

/// The most recent project as a full-width card: thumbnail backdrop,
/// duration chip, bleep stats, and a Resume pill.
private struct ContinueEditingCard: View {
    let project: Project
    /// "1080p · 60fps", loaded from the source video's track.
    @State private var formatText: String?

    var body: some View {
        SourceThumbnailView(
            fileName: project.sourceFileName,
            durationSeconds: project.durationSeconds,
            maxPixels: ThumbnailSize.heroMaxPixels
        )
        .frame(maxWidth: .infinity)
        .frame(height: ThumbnailSize.heroHeight)
        .overlay {
            LinearGradient(
                colors: [.clear, Color.bleepScrim],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .topTrailing) {
            TimecodeChip(seconds: project.durationSeconds)
                .padding(Spacing.compact)
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: Spacing.standard) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(project.title)
                        .font(.bleepEmphasis)
                        .foregroundStyle(Color.bleepOnVideo)
                        .lineLimit(1)
                    statsLine
                }
                Spacer()
                Label("Resume", systemImage: "play.fill")
                    .font(.bleepControlLabel)
                    .bold()
                    .foregroundStyle(Color.bleepOnAccent)
                    .padding(.horizontal, Spacing.standard)
                    .padding(.vertical, Spacing.compact)
                    .background(Color.bleepAccent, in: Capsule())
            }
            .padding(Spacing.standard)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .task(id: project.sourceFileName) {
            formatText = await Self.loadFormat(fileName: project.sourceFileName)
        }
    }

    private var statsLine: some View {
        let tokens = project.tokens
        let bleeps = tokens.count(where: \.isCensored)
        let review = tokens.count { $0.detectedProfane && $0.userOverride == nil }
        var line: Text
        if tokens.isEmpty {
            line = Text("Not transcribed yet")
        } else {
            line = Text(bleeps == 1 ? "1 bleep" : "\(bleeps) bleeps")
                .foregroundStyle(Color.bleepAccent)
            if review > 0 {
                line = line + Text(" · \(review) to review")
            }
        }
        if let formatText {
            line = line + Text(" · \(formatText)")
        }
        return line
            .font(.bleepMetadata)
            .foregroundStyle(Color.bleepOnVideo)
    }

    private nonisolated static func loadFormat(fileName: String) async -> String? {
        guard let url = try? ProjectStore.sourceURL(forFileName: fileName),
              let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
              let (size, frameRate) = try? await track.load(.naturalSize, .nominalFrameRate)
        else { return nil }
        let lines = Int(min(abs(size.width), abs(size.height)).rounded())
        return "\(lines)p · \(Int(frameRate.rounded()))fps"
    }
}

/// One tile in the all-projects grid: thumbnail, bleep-count badge,
/// duration chip, and the title beneath.
private struct ProjectGridCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            SourceThumbnailView(
                fileName: project.sourceFileName,
                durationSeconds: project.durationSeconds,
                maxPixels: ThumbnailSize.gridMaxPixels
            )
            .frame(maxWidth: .infinity)
            .frame(height: ThumbnailSize.gridHeight)
            .overlay(alignment: .topLeading) {
                bleepBadge
                    .padding(Spacing.tight)
            }
            .overlay(alignment: .bottomTrailing) {
                TimecodeChip(seconds: project.durationSeconds)
                    .padding(Spacing.tight)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
            Text(project.title)
                .font(.bleepMetadata)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var bleepBadge: some View {
        let bleeps = project.tokens.count(where: \.isCensored)
        if bleeps > 0 {
            Text(bleeps == 1 ? "1 BLEEP" : "\(bleeps) BLEEPS")
                .font(.bleepFineprint)
                .bold()
                .foregroundStyle(Color.bleepOnAccent)
                .padding(.horizontal, Spacing.tight)
                .padding(.vertical, Spacing.hairline)
                .background(Color.bleepAccent, in: Capsule())
                .accessibilityLabel(bleeps == 1 ? "1 bleep" : "\(bleeps) bleeps")
        }
    }
}

/// A duration readout on a scrim capsule, legible over any thumbnail.
private struct TimecodeChip: View {
    let seconds: Double

    var body: some View {
        Text(seconds.timecodeString)
            .font(.bleepTimecode)
            .foregroundStyle(Color.bleepOnVideo)
            .padding(.horizontal, Spacing.tight)
            .padding(.vertical, Spacing.hairline)
            .background(Color.bleepScrim, in: Capsule())
    }
}

/// A frame from a project's source video, letterboxed on the video
/// backdrop while it loads (or when the source can't be read).
private struct SourceThumbnailView: View {
    let fileName: String
    let durationSeconds: Double
    let maxPixels: CGFloat
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
        .accessibilityHidden(true)
        .task(id: fileName) {
            thumbnail = await Self.loadThumbnail(
                fileName: fileName,
                durationSeconds: durationSeconds,
                maxPixels: maxPixels
            )
        }
    }

    /// Grabs a frame 10% into the video — frame zero is often black or a
    /// fade-in. Any failure just leaves the placeholder in place.
    private nonisolated static func loadThumbnail(
        fileName: String,
        durationSeconds: Double,
        maxPixels: CGFloat
    ) async -> CGImage? {
        guard let url = try? ProjectStore.sourceURL(forFileName: fileName) else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixels, height: maxPixels)
        let time = CMTime(seconds: durationSeconds * 0.1, preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}

private extension View {
    /// A navigation-bar subtitle under the title, on OS versions that
    /// can render one; a no-op below iOS 26 and for empty text.
    @ViewBuilder
    func mastheadTagline(_ text: String) -> some View {
        if #available(iOS 26.0, *), !text.isEmpty {
            navigationSubtitle(text)
        } else {
            self
        }
    }
}
