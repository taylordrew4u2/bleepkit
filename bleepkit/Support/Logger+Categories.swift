//
//  Logger+Categories.swift
//  BleepKit
//

import Foundation
import OSLog

/// Per-subsystem loggers. No `print` anywhere in the app.
nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "comedy.bleepkit"

    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let profanity = Logger(subsystem: subsystem, category: "profanity")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let video = Logger(subsystem: subsystem, category: "video")
    static let export = Logger(subsystem: subsystem, category: "export")
    /// Import flow: copying, metadata loading, project creation.
    static let importer = Logger(subsystem: subsystem, category: "importer")
    /// SwiftData persistence and file management.
    static let storage = Logger(subsystem: subsystem, category: "storage")
}
