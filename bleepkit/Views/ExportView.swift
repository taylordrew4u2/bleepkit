//
//  ExportView.swift
//  BleepKit
//

import SwiftUI

/// The export sheet: progress with cancel, then success with sharing, or
/// the real failure reason with retry.
struct ExportView: View {
    let editor: EditorViewModel
    /// Free-tier cap in seconds; nil exports the full length.
    var limitSeconds: Double?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
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
                if let limit = viewModel.limitSeconds {
                    Text("Free export — first \(Int(limit)) seconds")
                        .font(.bleepFineprint)
                        .foregroundStyle(.secondary)
                }
                Button("Cancel", role: .cancel) {
                    showsCancelConfirmation = true
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Picker("Resolution", selection: $selectedResolution) {
                    ForEach(ExportResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                .pickerStyle(.segmented)

                Text(selectedResolution.detail)
                    .font(.bleepMetadata)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Output")
            }

            if let limitSeconds {
                Section {
                    Text("Free export renders the first \(Int(limitSeconds)) seconds.")
                        .font(.bleepDetail)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    startExport()
                } label: {
                    Label("Export \(selectedResolution.title)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: Radius.card))
            }
        }
    }

    private func startExport() {
        let model = ExportViewModel(
            editor: editor,
            environment: environment,
            limitSeconds: limitSeconds,
            resolution: selectedResolution
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
