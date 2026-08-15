//
//  BleepKitApp.swift
//  BleepKit
//

import SwiftData
import SwiftUI

/// Application entry point.
///
/// Builds the app-wide dependency container once at launch and hosts the root
/// view. A container construction failure (for example, a SwiftData store that
/// cannot be opened) is surfaced as a full-screen error instead of crashing.
@main
@MainActor
struct BleepKitApp: App {
    /// The dependency container, or the error that prevented it from being built.
    private let bootstrap: Result<AppEnvironment, Error>

    init() {
        let result = Result { try AppEnvironment() }
        if case .success(let environment) = result {
            // Scratch files never survive a launch; see TempFileManager.
            environment.tempFiles.purgeAndPrepare()
        }
        bootstrap = result
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let environment):
                RootView()
                    .environment(environment)
                    .modelContainer(environment.modelContainer)
            case .failure(let error):
                ErrorStateView(
                    title: "BleepKit Could Not Start",
                    message: error.localizedDescription
                )
            }
        }
    }
}
