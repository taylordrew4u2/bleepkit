//
//  ProjectStore.swift
//  BleepKit
//

import Foundation
import OSLog
import SwiftData

/// CRUD façade over `Project` records and their on-disk source videos.
///
/// Source videos live in `Documents/sources` and are referenced by file name
/// only; absolute sandbox paths are dead after a reinstall or relaunch.
@MainActor
final class ProjectStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    private var context: ModelContext { modelContainer.mainContext }

    // MARK: Source files

    /// `Documents/sources`, created on first use.
    nonisolated static func sourcesDirectory() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = documents.appending(path: "sources", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Moves a temporary copy of an imported video into `Documents/sources`
    /// under a fresh UUID name and returns that file name for persistence.
    nonisolated static func installSource(from temporaryURL: URL) throws -> String {
        let ext = temporaryURL.pathExtension.isEmpty ? "mov" : temporaryURL.pathExtension.lowercased()
        let fileName = "\(UUID().uuidString).\(ext)"
        let destination = try sourcesDirectory().appending(path: fileName)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return fileName
    }

    /// Resolves a stored file name against the current sandbox container.
    nonisolated static func sourceURL(forFileName fileName: String) throws -> URL {
        try sourcesDirectory().appending(path: fileName)
    }

    /// Deletes an installed source file; ignores files that are already gone.
    nonisolated static func removeSource(fileName: String) {
        do {
            let url = try sourceURL(forFileName: fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try FileManager.default.removeItem(at: url)
        } catch {
            Logger.storage.error("Failed to remove source \(fileName): \(error.localizedDescription)")
        }
    }

    // MARK: Records

    /// Inserts and saves a new project for a just-imported source.
    func createProject(title: String, sourceFileName: String, durationSeconds: Double) throws -> Project {
        let project = Project(title: title, sourceFileName: sourceFileName, durationSeconds: durationSeconds)
        context.insert(project)
        try context.save()
        return project
    }

    /// Persists any pending edits to the given project.
    func save() throws {
        try context.save()
    }

    /// Deletes the record and its source video file.
    func delete(_ project: Project) throws {
        let fileName = project.sourceFileName
        context.delete(project)
        try context.save()
        Self.removeSource(fileName: fileName)
    }
}
