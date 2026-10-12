//
//  ExportViewModel.swift
//  BleepKit
//

import Foundation
import Observation
import OSLog
import QuartzCore
import UIKit

/// Drives one export run: render, save to the Photo Library, offer sharing.
@MainActor
@Observable
final class ExportViewModel {
    /// The export flow's UI state.
    enum Phase {
        case idle
        /// Composition, caption layers, and the export session are being prepared.
        case preparing
        case exporting(fraction: Double)
        case saving
        /// Saved to Photos; the file URL remains valid for the share sheet.
        case completed(URL)
        /// Photos permission denied — the file still exists for sharing.
        case photosDenied(URL)
        case failed(message: String)
    }

    private(set) var phase: Phase = .idle

    private let editor: EditorViewModel
    private let pipeline: ExportPipeline
    private let photoLibraryWriter: PhotoLibraryWriter
    private let tempFiles: TempFileManager
    private let displayScale: CGFloat
    private var exportTask: Task<Void, Never>?
    /// Identifies the attempt that owns UI updates and the background task.
    private var activeRunID: UUID?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    /// Output quality selected before export starts.
    let resolution: ExportResolution

    init(
        editor: EditorViewModel,
        environment: AppEnvironment,
        resolution: ExportResolution,
        displayScale: CGFloat
    ) {
        self.editor = editor
        self.resolution = resolution
        self.displayScale = displayScale
        pipeline = ExportPipeline(
            audioCensorBuilder: environment.audioCensorBuilder,
            tempFiles: environment.tempFiles
        )
        photoLibraryWriter = environment.photoLibraryWriter
        tempFiles = environment.tempFiles
    }

    /// Starts (or restarts) the export. Every attempt constructs a fresh
    /// export session inside the pipeline — sessions are single-use.
    func startExport() {
        exportTask?.cancel()
        let runID = UUID()
        activeRunID = runID
        phase = .preparing
        beginBackgroundExportTask(for: runID)
        exportTask = Task {
            // The run and its callbacks own UI and CALayer state on MainActor.
            guard self.activeRunID == runID else { return }
            await self.run(id: runID)
        }
    }

    /// Cancels the in-flight export; the pipeline deletes partial output.
    func cancel() {
        exportTask?.cancel()
        // A Photos write must finish before the sheet becomes dismissible.
        switch phase {
        case .preparing, .exporting: phase = .idle
        default: break
        }
        endBackgroundExportTask()
    }

    /// Removes the finished file when the user is done with it.
    func cleanUp() {
        switch phase {
        case .completed(let url), .photosDenied(let url):
            tempFiles.remove(url)
        default:
            break
        }
    }

    private func run(id runID: UUID) async {
        defer {
            // A previous attempt may finish cancelling after a retry starts.
            if activeRunID == runID {
                activeRunID = nil
                exportTask = nil
                endBackgroundExportTask()
            }
        }
        let project = editor.project
        do {
            try Task.checkCancellation()
            let sourceURL = try ProjectStore.sourceURL(forFileName: project.sourceFileName)
            let scale = displayScale
            let outputURL = try await pipeline.export(
                sourceURL: sourceURL,
                ranges: editor.censorRanges,
                beepSettings: project.beepSettings,
                resolution: resolution,
                maxDurationSeconds: nil,
                buildOverlayLayers: { [editor] _, renderSize in
                    // Identical builders to the preview, at the output's
                    // native size.
                    editor.buildPreviewLayers(
                        targetSize: renderSize,
                        contentsScale: scale
                    )
                },
                renderingStarted: { [weak self] in
                    guard let self, self.isCurrentRun(runID) else { return }
                    self.phase = .exporting(fraction: 0)
                },
                progress: { [weak self] fraction in
                    guard let self, self.isCurrentRun(runID),
                          case .exporting = self.phase else { return }
                    self.phase = .exporting(fraction: min(max(fraction, 0), 1))
                }
            )
            if Task.isCancelled || !isCurrentRun(runID) {
                tempFiles.remove(outputURL)
                throw CancellationError()
            }

            phase = .saving
            do {
                try await photoLibraryWriter.saveToAlbum(fileURL: outputURL)
                if Task.isCancelled || !isCurrentRun(runID) {
                    // The Photos operation has finished; discard the
                    // scratch render for a cancelled or superseded run.
                    tempFiles.remove(outputURL)
                    throw CancellationError()
                }
                phase = .completed(outputURL)
            } catch let error as PhotoLibraryWriter.WriteError {
                guard !Task.isCancelled, isCurrentRun(runID) else {
                    tempFiles.remove(outputURL)
                    throw CancellationError()
                }
                if case .notAuthorized = error {
                    phase = .photosDenied(outputURL)
                } else {
                    phase = .failed(message: error.localizedDescription)
                    tempFiles.remove(outputURL)
                }
            } catch {
                tempFiles.remove(outputURL)
                throw error
            }
        } catch is CancellationError {
            if activeRunID == runID {
                phase = .idle
            }
        } catch {
            // Surface the real failure — never a generic "something went
            // wrong".
            if activeRunID == runID {
                phase = Task.isCancelled ? .idle : .failed(message: error.localizedDescription)
            }
        }
    }

    private func isCurrentRun(_ runID: UUID) -> Bool {
        activeRunID == runID && exportTask?.isCancelled == false
    }

    private func beginBackgroundExportTask(for runID: UUID) {
        endBackgroundExportTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "BleepKit Export") { [weak self] in
            // UIKit requires the task to end before this handler returns.
            MainActor.assumeIsolated {
                guard let self, self.activeRunID == runID else { return }
                self.cancel()
            }
        }
    }

    private func endBackgroundExportTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
