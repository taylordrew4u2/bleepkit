//
//  BleepKitApp.swift
//  BleepKit
//

import SwiftData
import SwiftUI
import UIKit

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
        Self.applyMastheadNavigationTitles()
    }

    /// New York (serif) navigation titles — the app's masthead. Fonts are
    /// derived from the preferred text styles so Dynamic Type keeps
    /// driving their size.
    private static func applyMastheadNavigationTitles() {
        let bar = UINavigationBar.appearance()
        if let descriptor = UIFont.preferredFont(forTextStyle: .headline)
            .fontDescriptor.withDesign(.serif) {
            bar.titleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 0)]
        }
        if let descriptor = UIFont.preferredFont(forTextStyle: .largeTitle)
            .fontDescriptor.withDesign(.serif)?
            .withSymbolicTraits(.traitBold) {
            bar.largeTitleTextAttributes = [.font: UIFont(descriptor: descriptor, size: 0)]
        }
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
