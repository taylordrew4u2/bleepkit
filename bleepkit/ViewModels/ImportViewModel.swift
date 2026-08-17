//
//  ImportViewModel.swift
//  BleepKit
//

import AVFoundation
import CoreTransferable
import Foundation
import Observation
import OSLog
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A movie file received from the Photos picker.
///
/// `FileRepresentation` hands over a short-lived temporary file; the
/// importing closure copies it into the app's tmp directory (inside the
/// transfer machinery, off the main thread) so it survives until ingestion.
nonisolated struct PickedVideoFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let fileExtension = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appending(path: UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return PickedVideoFile(url: destination)
        }
    }
}

/// Failures specific to the import flow.
nonisolated enum ImportError: LocalizedError {
    /// The Photos selection could not be loaded as a movie file.
    case unreadableSelection

    var errorDescription: String? {
        switch self {
        case .unreadableSelection:
            return "This item couldn't be loaded as a video. Try picking a different one."
        }
    }
}

/// Drives the import flow: copy the video into the sandbox, read its
/// metadata, extract its audio, and create the `Project` record.
@MainActor
@Observable
final class ImportViewModel {
    /// The import flow's UI state.
    enum ImportPhase {
        case idle
        case importing(step: String)
        case ready(ImportedSource)
        case failed(message: String)
    }

    /// A freshly imported source, ready for inspection.
    struct ImportedSource {
        let project: Project
        let metadata: SourceVideoMetadata
        /// Scratch `.m4a`; nil when the video has no audio track.
        let extractedAudioURL: URL?
    }

    private(set) var phase: ImportPhase = .idle

    private let projectStore: ProjectStore
    private let audioExtractor: AudioExtractor
    private let tempFiles: TempFileManager
    private var importTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        projectStore = environment.projectStore
        audioExtractor = environment.audioExtractor
        tempFiles = environment.tempFiles
    }

    // MARK: Entry points

    /// Imports a video chosen in the Photos picker.
    func importPhotosSelection(_ item: PhotosPickerItem) {
        startImport(title: Self.defaultTitle()) {
            guard let picked = try await item.loadTransferable(type: PickedVideoFile.self) else {
                throw ImportError.unreadableSelection
            }
            return picked.url
        }
    }

    /// Imports a video from a file URL — the Files importer or a movie
    /// handed over by another app (share sheet / document types).
    func importFile(at url: URL, suggestedTitle: String? = nil) {
        let title = (suggestedTitle?.isEmpty == false ? suggestedTitle : nil) ?? Self.defaultTitle()
        // Files arriving through "Copy to BleepKit" land in Documents/Inbox
        // and are ours to clean up after copying.
        let removeOriginal = url.path().contains("/Documents/Inbox/")
        startImport(title: title) {
            try await Task.detached(priority: .userInitiated) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                let fileExtension = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appending(path: UUID().uuidString)
                    .appendingPathExtension(fileExtension)
                try FileManager.default.copyItem(at: url, to: destination)
                if removeOriginal {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        Logger.importer.warning("Could not remove inbox original: \(error.localizedDescription)")
                    }
                }
                return destination
            }.value
        }
    }

    /// Surfaces a failure that occurred before the flow could start (for
    /// example, a Files-importer error).
    func fail(with message: String) {
        phase = .failed(message: message)
    }

    /// Cancels an in-flight import; partial files are cleaned up by the task.
    func cancelImport() {
        importTask?.cancel()
    }

    /// Returns to the idle picker screen.
    func reset() {
        phase = .idle
    }

    // MARK: Flow

    private func startImport(title: String, makeLocalCopy: @escaping () async throws -> URL) {
        importTask?.cancel()
        phase = .importing(step: "Copying video…")
        importTask = Task {
            await self.performImport(title: title, makeLocalCopy: makeLocalCopy)
        }
    }

    private func performImport(title: String, makeLocalCopy: () async throws -> URL) async {
        var installedFileName: String?
        var extractedAudioURL: URL?
        do {
            let temporaryURL = try await makeLocalCopy()
            try Task.checkCancellation()

            phase = .importing(step: "Reading video info…")
            let fileName = try ProjectStore.installSource(from: temporaryURL)
            installedFileName = fileName
            let sourceURL = try ProjectStore.sourceURL(forFileName: fileName)
            let metadata = try await SourceVideoMetadata.load(from: sourceURL)
            try Task.checkCancellation()

            phase = .importing(step: "Extracting audio…")
            extractedAudioURL = try await audioExtractor.extractAudio(from: sourceURL)
            try Task.checkCancellation()

            let project = try projectStore.createProject(
                title: title,
                sourceFileName: fileName,
                durationSeconds: metadata.durationSeconds
            )
            Logger.importer.info("Imported \(fileName): \(metadata.durationSeconds, format: .fixed(precision: 2))s, \(Int(metadata.naturalSize.width))×\(Int(metadata.naturalSize.height)), \(metadata.nominalFrameRate, format: .fixed(precision: 2)) fps")
            phase = .ready(ImportedSource(
                project: project,
                metadata: metadata,
                extractedAudioURL: extractedAudioURL
            ))
        } catch is CancellationError {
            cleanUpPartialImport(installedFileName: installedFileName, extractedAudioURL: extractedAudioURL)
            Logger.importer.notice("Import canceled")
            phase = .idle
        } catch {
            cleanUpPartialImport(installedFileName: installedFileName, extractedAudioURL: extractedAudioURL)
            Logger.importer.error("Import failed: \(error.localizedDescription)")
            phase = .failed(message: error.localizedDescription)
        }
    }

    private func cleanUpPartialImport(installedFileName: String?, extractedAudioURL: URL?) {
        if let installedFileName {
            ProjectStore.removeSource(fileName: installedFileName)
        }
        if let extractedAudioURL {
            tempFiles.remove(extractedAudioURL)
        }
    }

    private static func defaultTitle() -> String {
        "Reel \(Date.now.formatted(date: .abbreviated, time: .shortened))"
    }
}
