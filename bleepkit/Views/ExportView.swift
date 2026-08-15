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
                        viewModel?.cancel()
                        viewModel?.cleanUp()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isWorking)
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
            VStack(spacing: 16) {
                ProgressView(value: fraction)
                    .padding(.horizontal, 32)
                Text("Exporting… \(Int((fraction * 100).rounded()))%")
                    .font(.headline)
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
            VStack(spacing: 24) {
                PermissionDeniedView(
                    title: "Can't Save to Photos",
                    message: "BleepKit isn't allowed to add videos to your Photo Library. Allow it in Settings, or share the file directly."
                )
                ShareLink(item: url) {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 24)
            }
        case .failed(let message):
            ErrorStateView(title: "Export Failed", message: message, retryTitle: "Try Again") {
                viewModel.startExport()
            }
        }
    }

    private func successView(title: String, message: String, url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text(title)
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            ShareLink(item: url) {
                Label("Share Video", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }
}
