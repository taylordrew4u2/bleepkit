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
    @State private var viewModel: ExportViewModel?
    @State private var showsCancelConfirmation = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(for: viewModel)
                } else {
                    ProgressView()
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
                viewModel?.cancel()
                viewModel?.cleanUp()
                dismiss()
            }
            Button("Continue Exporting", role: .cancel) {}
        } message: {
            Text("The render so far is discarded.")
        }
        .task {
            if viewModel == nil {
                let model = ExportViewModel(editor: editor, environment: environment)
                viewModel = model
                model.startExport()
            }
        }
    }

    private var isWorking: Bool {
        switch viewModel?.phase {
        case .exporting, .saving: true
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
        case .exporting(let fraction):
            VStack(spacing: Spacing.medium) {
                ProgressView(value: fraction)
                    .padding(.horizontal, Spacing.wide)
                Text("Exporting… \(Int((fraction * 100).rounded()))%")
                    .font(.bleepEmphasis)
                    .monospacedDigit()
                Button("Cancel", role: .cancel) {
                    viewModel.cancel()
                }
                .buttonStyle(.bordered)
            }
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

    private func successView(title: String, message: String, url: URL) -> some View {
        VStack(spacing: 16) {
            // Monochrome result mark — the ink stamp; the accent stays
            // reserved for censor marks.
            Image(systemName: "checkmark.circle.fill")
                .font(.bleepResultGlyph)
                .foregroundStyle(.primary)
            Text(title)
                .font(.bleepMasthead)
            Text(message)
                .font(.bleepDetail)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.wide)
            ShareLink(item: url) {
                Label("Share Video", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }
}
