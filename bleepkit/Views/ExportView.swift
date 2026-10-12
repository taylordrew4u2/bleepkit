//
//  ExportView.swift
//  BleepKit
//

import SwiftUI

/// The export sheet: progress with cancel, then success with sharing, or
/// the real failure reason with retry.
struct ExportView: View {
    let editor: EditorViewModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var viewModel: ExportViewModel?
    @State private var showsCancelConfirmation = false
    @State private var selectedResolution: ExportResolution = .fullHD

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(for: viewModel)
                } else {
                    exportOptions
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if isWorking {
                            // A stray tap must not silently discard the render.
                            showsCancelConfirmation = true
                        } else {
                            viewModel?.cleanUp()
                            dismiss()
                        }
                    }
                    // The Photos write can't be undone once it starts.
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
        .confirmationDialog(
            "Cancel this export?",
            isPresented: $showsCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Export", role: .destructive) {
                guard !isSaving else { return }
                viewModel?.cancel()
                viewModel?.cleanUp()
                dismiss()
            }
            .disabled(isSaving)
            Button("Continue Exporting", role: .cancel) {}
        } message: {
            Text("The current export will be discarded.")
        }
    }

    private var isSaving: Bool {
        if case .saving = viewModel?.phase { true } else { false }
    }

    private var isWorking: Bool {
        switch viewModel?.phase {
        case .preparing, .exporting, .saving: true
        default: false
        }
    }

    @ViewBuilder
    private func content(for viewModel: ExportViewModel) -> some View {
        switch viewModel.phase {
        case .idle:
            // Reached after a cancelled run.
            ContentUnavailableView {
                Label("Export Cancelled", systemImage: "xmark.circle")
            } actions: {
                Button("Export Again") {
                    viewModel.startExport()
                }
                .buttonStyle(.borderedProminent)
            }
        case .preparing:
            exportProgress(fraction: nil)
        case .exporting(let fraction):
            exportProgress(fraction: fraction)
        case .saving:
            LoadingStateView(message: "Saving to Photos…")
        case .completed(let url):
            successView(
                title: "Saved to Photos",
                message: "Your censored video is in the “BleepKit” album, ready to upload.",
                url: url
            )
        case .photosDenied(let url):
            VStack(spacing: Spacing.roomy) {
                PermissionDeniedView(
                    title: "Can't Save to Photos",
                    message: "BleepKit isn't allowed to add videos to your Photo Library. Allow it in Settings, or share the file directly."
                )
                ShareLink(item: url) {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, Spacing.roomy)
            }
        case .failed(let message):
            ErrorStateView(title: "Export Failed", message: message, retryTitle: "Try Again") {
                viewModel.startExport()
            }
        }
    }

    private var exportOptions: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Spacing.compact) {
                    Text(editor.project.title)
                        .font(.bleepEmphasis)
                        .accessibilityAddTraits(.isHeader)
                    Text("\(editor.project.durationSeconds.timecodeString) · \(censorSummary) · Up to \(selectedResolution.title)")
                        .font(.bleepDetail)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, Spacing.compact)
            } header: {
                Text("Video")
            }

            Section {
                Picker("Resolution", selection: $selectedResolution) {
                    ForEach(ExportResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Resolution")
            } footer: {
                Text("\(selectedResolution.detail). Your video's aspect ratio is preserved, and smaller videos keep their original resolution.")
                    .font(.bleepMetadata)
            }

            Section {
                Button {
                    startExport()
                } label: {
                    Label("Export Video", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: Radius.card))
            }
        }
    }

    private var censorSummary: String {
        let count = editor.project.tokens.count(where: \.isCensored)
        return count == 1 ? "1 censored word" : "\(count) censored words"
    }

    private func exportProgress(fraction: Double?) -> some View {
        VStack(spacing: Spacing.roomy) {
            if let fraction {
                VStack(spacing: Spacing.medium) {
                    Text("Exporting Video…")
                        .font(.bleepEmphasis)
                    ProgressView(value: fraction)
                        .accessibilityLabel("Export progress")
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.bleepDetailValue)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            } else {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: Spacing.compact) {
                    Text("Preparing Video…")
                        .font(.bleepEmphasis)
                    Text("Preparing your audio and visual edits for export.")
                        .font(.bleepDetail)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Cancel Export", role: .cancel) {
                showsCancelConfirmation = true
            }
            .buttonStyle(.bordered)
        }
        .multilineTextAlignment(.center)
        .padding(Spacing.wide)
        .frame(maxWidth: ContentWidth.dashboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startExport() {
        let model = ExportViewModel(
            editor: editor,
            environment: environment,
            resolution: selectedResolution,
            displayScale: displayScale
        )
        viewModel = model
        model.startExport()
    }

    /// Same visual language as the sheet's other states, with the primary
    /// action prominent (audit 7.2/7.3).
    private func successView(title: String, message: String, url: URL) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "checkmark.circle.fill")
        } description: {
            Text(message)
        } actions: {
            ShareLink(item: url) {
                Label("Share Video", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
