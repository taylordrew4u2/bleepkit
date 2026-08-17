//
//  TempFileManager.swift
//  BleepKit
//

import Foundation
import OSLog

/// Owns every scratch file the app creates.
///
/// All transient artifacts — extracted audio, synthesized beeps, partial
/// exports — live in one directory under Caches. The directory is purged on
/// every launch so scratch files never outlive a session, and nothing
/// transient ever lands in Documents.
nonisolated struct TempFileManager: Sendable {
    /// `Caches/scratch`.
    let scratchDirectory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        scratchDirectory = base.appending(path: "scratch", directoryHint: .isDirectory)
    }

    /// Deletes all scratch content and recreates the directory. Called once
    /// at launch, before any service can hand out scratch URLs.
    func purgeAndPrepare() {
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: scratchDirectory.path) {
                try fileManager.removeItem(at: scratchDirectory)
            }
            try fileManager.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.storage.error("Failed to reset scratch directory: \(error.localizedDescription)")
        }
    }

    /// Returns a unique URL inside the scratch directory, creating the
    /// directory first in case a purge has not run yet.
    func makeScratchURL(fileExtension: String) -> URL {
        do {
            try FileManager.default.createDirectory(at: scratchDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.storage.error("Failed to create scratch directory: \(error.localizedDescription)")
        }
        return scratchDirectory
            .appending(path: UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    /// Removes a single scratch artifact; ignores files that are already gone.
    func remove(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.storage.error("Failed to remove scratch file \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}
