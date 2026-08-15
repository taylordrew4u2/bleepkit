//
//  StateViews.swift
//  BleepKit
//

import SwiftUI
import UIKit

/// Full-screen progress state. Every long-running operation in the app
/// passes a cancel action — no spinner without an escape hatch.
struct LoadingStateView: View {
    let message: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text(message)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let onCancel {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-screen error state with an optional retry action.
struct ErrorStateView: View {
    let title: String
    let message: String
    var retryTitle: String = "Try Again"
    var onRetry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

/// Full-screen state for a denied or restricted permission, with a deep
/// link into the app's Settings page.
struct PermissionDeniedView: View {
    let title: String
    let message: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "lock.shield")
        } description: {
            Text(message)
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Full-screen empty state.
struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
