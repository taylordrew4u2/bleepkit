//
//  TrashView.swift
//  BleepKit
//

import OSLog
import SwiftData
import SwiftUI

/// Trashed projects: restore them to the dashboard, delete one for
/// good, or empty the whole trash. Videos stay on disk until a project
/// is permanently deleted, so trashing is always recoverable.
struct TrashView: View {
    @Environment(AppEnvironment.self) private var environment
    @Query(
        filter: #Predicate<Project> { $0.trashedAt != nil },
        sort: \Project.updatedAt,
        order: .reverse
    ) private var projects: [Project]
    @State private var pendingPermanentDelete: Project?
    @State private var showsEmptyTrashConfirmation = false
    @State private var failureMessage: String?

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("Trash Is Empty", systemImage: "trash")
                } description: {
                    Text("Deleted projects stay here — and keep their videos — until you empty the trash.")
                }
            } else {
                List {
                    ForEach(projects) { project in
                        TrashRowView(project: project)
                            .swipeActions(edge: .leading) {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    restore(project)
                                }
                                .tint(.bleepAccent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash.slash", role: .destructive) {
                                    pendingPermanentDelete = project
                                }
                            }
                            .contextMenu {
                                Button("Restore", systemImage: "arrow.uturn.backward") {
                                    restore(project)
                                }
                                Button("Delete Permanently…", systemImage: "trash.slash", role: .destructive) {
                                    pendingPermanentDelete = project
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Trash")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !projects.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty Trash", role: .destructive) {
                        showsEmptyTrashConfirmation = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this project permanently?",
            isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { if !$0 { pendingPermanentDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Project and Video", role: .destructive) {
                if let pendingPermanentDelete {
                    deletePermanently(pendingPermanentDelete)
                }
                pendingPermanentDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPermanentDelete = nil
            }
        } message: {
            Text("The video and every edit are removed for good. This can't be undone.")
        }
        .confirmationDialog(
            "Empty the trash?",
            isPresented: $showsEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(projects.count == 1 ? "1 Project" : "\(projects.count) Projects") Forever", role: .destructive) {
                emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every trashed project and its video are removed for good. This can't be undone.")
        }
        .alert(
            "Couldn't Update Trash",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { if !$0 { failureMessage = nil } }
            )
        ) {
            Button("OK") { failureMessage = nil }
        } message: {
            Text(failureMessage ?? "")
        }
    }

    private func restore(_ project: Project) {
        do {
            try environment.projectStore.restoreFromTrash(project)
        } catch {
            Logger.storage.error("Failed to restore project: \(error.localizedDescription)")
            failureMessage = error.localizedDescription
        }
    }

    private func deletePermanently(_ project: Project) {
        do {
            try environment.projectStore.delete(project)
        } catch {
            Logger.storage.error("Failed to delete project: \(error.localizedDescription)")
            failureMessage = error.localizedDescription
        }
    }

    private func emptyTrash() {
        do {
            try environment.projectStore.emptyTrash()
        } catch {
            Logger.storage.error("Failed to empty trash: \(error.localizedDescription)")
            failureMessage = error.localizedDescription
        }
    }
}

/// One trashed project: title, length, and when it was trashed.
private struct TrashRowView: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(project.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let trashedAt = project.trashedAt {
                Text("\(project.durationSeconds.timecodeString) · Deleted \(trashedAt.formatted(.relative(presentation: .named)))")
                    .font(.bleepMetadata)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
