//
//  AudioExtractor.swift
//  BleepKit
//

import AVFoundation
import Foundation
import OSLog

/// Extracts a video's audio track into a standalone `.m4a` in the scratch
/// directory. The resulting file feeds transcription.
nonisolated struct AudioExtractor: Sendable {
    /// Failures specific to audio extraction.
    enum ExtractionError: LocalizedError {
        /// The system could not create an M4A export session for this asset.
        case exportSessionUnavailable

        var errorDescription: String? {
            switch self {
            case .exportSessionUnavailable:
                return "The audio in this video can't be read for transcription."
            }
        }
    }

    let tempFiles: TempFileManager

    /// Exports the audio of the video at `sourceURL` to a scratch `.m4a`.
    ///
    /// - Returns: The scratch file URL, or nil when the video has no audio
    ///   track (captions are still possible; audio censoring is skipped).
    /// - Throws: `ExtractionError` or the underlying export failure. On
    ///   cancellation or failure any partial output file is deleted.
    func extractAudio(from sourceURL: URL) async throws -> URL? {
        let asset = AVURLAsset(url: sourceURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else {
            Logger.audio.notice("Source has no audio track; skipping extraction")
            return nil
        }
        // Export sessions are single-use; a fresh one is created per attempt.
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ExtractionError.exportSessionUnavailable
        }
        let outputURL = tempFiles.makeScratchURL(fileExtension: "m4a")
        do {
            try await session.export(to: outputURL, as: .m4a)
        } catch {
            tempFiles.remove(outputURL)
            throw error
        }
        Logger.audio.info("Extracted audio to \(outputURL.lastPathComponent)")
        return outputURL
    }
}
