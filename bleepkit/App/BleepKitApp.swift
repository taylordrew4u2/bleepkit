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
    /// The animated splash shown once per cold launch, over the live app.
    @State private var showsLaunchSplash = true

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
            ZStack {
                switch bootstrap {
                case .success(let environment):
                    RootView()
                        .environment(environment)
                        .modelContainer(environment.modelContainer)
                case .failure(let error):
                    ErrorStateView(
                        title: "Could Not Start",
                        message: error.localizedDescription
                    )
                }
                if showsLaunchSplash {
                    LaunchSplashView {
                        showsLaunchSplash = false
                    }
                    // Decorative only: taps land on the app beneath, so
                    // the splash never delays a fast-fingered user (or
                    // the UI smoke test).
                    .allowsHitTesting(false)
                }
            }
            // Explicit root tint: the AccentColor asset alone isn't honored
            // at runtime on iOS 26 (verified in the simulator), so every
            // tinted control takes the accent from here.
            .tint(.bleepAccent)
            // The Studio Booth direction is dark-only — black surfaces
            // under the bleep-yellow accent, in both system appearances.
            .preferredColorScheme(.dark)
            .task {
                if case .success(let environment) = bootstrap {
                    environment.startStoreObservation()
                }
            }
        }
    }
}
