//
//  RootView.swift
//  BleepKit
//

import SwiftUI

/// Hosts the import flow and receives movie files opened from other apps.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var importViewModel: ImportViewModel?
    /// A movie handed over before the view model exists — `onOpenURL` can
    /// fire before `.task` on a cold launch. Replayed once the view model
    /// is created so the open-in path is never silently dropped.
    @State private var pendingImportURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let importViewModel {
                    ImportView(viewModel: importViewModel)
                } else {
                    // Visible for one frame at most: the view model is
                    // created in `.task` below because it needs the
                    // environment, which is unavailable in `init`.
                    ProgressView()
                }
            }
        }
        .task {
            if importViewModel == nil {
                importViewModel = ImportViewModel(environment: environment)
            }
            if let url = pendingImportURL {
                pendingImportURL = nil
                startImport(of: url)
            }
        }
        .onOpenURL { url in
            if importViewModel == nil {
                pendingImportURL = url
            } else {
                startImport(of: url)
            }
        }
    }

    private func startImport(of url: URL) {
        importViewModel?.importFile(
            at: url,
            suggestedTitle: url.deletingPathExtension().lastPathComponent
        )
    }
}
