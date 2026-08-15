//
//  RootView.swift
//  BleepKit
//

import SwiftUI

/// Hosts the import flow and receives movie files opened from other apps.
struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var importViewModel: ImportViewModel?

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
        }
        .task {
            if importViewModel == nil {
                importViewModel = ImportViewModel(environment: environment)
            }
        }
        .onOpenURL { url in
            importViewModel?.importFile(
                at: url,
                suggestedTitle: url.deletingPathExtension().lastPathComponent
            )
        }
    }
}
