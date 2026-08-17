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
            .navigationTitle("BleepKit")
            // The masthead's tagline — set here so it sits under the large
            // serif title on the dashboard only, not on pushed screens.
            .mastheadTagline("Your on-device redaction desk")
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

private extension View {
    /// A navigation-bar tagline under the masthead, on OS versions that
    /// can render one; a no-op below iOS 26.
    @ViewBuilder
    func mastheadTagline(_ text: String) -> some View {
        if #available(iOS 26.0, *) {
            navigationSubtitle(text)
        } else {
            self
        }
    }
}
