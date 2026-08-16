//
//  ImportView.swift
//  BleepKit
//

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
                    Text("No projects yet. Import a Reel to transcribe it and censor profanity.")
                        .foregroundStyle(.secondary)
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
                    .onDelete { offsets in
                        pendingDeletion = offsets
                    }
                }
            }
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

/// One row in the saved-project list.
private struct ProjectRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(project.title)
            Text("\(project.durationSeconds.timecodeString) · \(project.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.bleepMetadata)
                .foregroundStyle(.secondary)
        }
    }
}

