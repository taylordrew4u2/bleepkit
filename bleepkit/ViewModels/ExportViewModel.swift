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
    private var exportTask: Task<Void, Never>?

    init(editor: EditorViewModel, environment: AppEnvironment) {
        self.editor = editor
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
        phase = .exporting(fraction: 0)
        exportTask = Task {
            await self.run()
        }
    }

    /// Cancels the in-flight export; the pipeline deletes partial output.
    func cancel() {
        exportTask?.cancel()
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

    private func run() async {
        let project = editor.project
        do {
            let sourceURL = try ProjectStore.sourceURL(forFileName: project.sourceFileName)
            let scale = UIScreen.main.scale
            let outputURL = try await pipeline.export(
                sourceURL: sourceURL,
                ranges: editor.censorRanges,
                beepSettings: project.beepSettings,
                buildOverlayLayers: { [editor] _, renderSize in
                    // Identical builders to the preview, at the output's
                    // native size.
                    editor.buildPreviewLayers(
                        targetSize: renderSize,
                        contentsScale: scale
                    )
                },
                progress: { [weak self] fraction in
                    if case .exporting = self?.phase {
                        self?.phase = .exporting(fraction: fraction)
                    }
                }
            )
            try Task.checkCancellation()

            phase = .saving
            do {
                try await photoLibraryWriter.saveToAlbum(fileURL: outputURL)
                phase = .completed(outputURL)
            } catch let error as PhotoLibraryWriter.WriteError {
                if case .notAuthorized = error {
                    phase = .photosDenied(outputURL)
                } else {
                    phase = .failed(message: error.localizedDescription)
                    tempFiles.remove(outputURL)
                }
            }
        } catch is CancellationError {
            phase = .idle
        } catch {
            // Surface the real failure — never a generic "something went
            // wrong".
            phase = .failed(message: error.localizedDescription)
        }
    }
}
