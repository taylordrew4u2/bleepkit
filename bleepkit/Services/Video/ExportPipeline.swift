//
//  ExportPipeline.swift
//  BleepKit
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog
import QuartzCore

/// Renders the final 1080×1920 MP4: the censored composition (same builder
/// as the preview) with the caption and overlay trees burned in through
/// `AVVideoCompositionCoreAnimationTool`.
///
/// Main-actor bound because it assembles `CALayer` trees. The export itself
/// is asynchronous and does not block the main thread.
@MainActor
struct ExportPipeline {
    enum ExportError: LocalizedError {
        /// The system could not create an export session for this asset.
        case sessionUnavailable
        /// The export ran and failed; carries the session's real error.
        case failed(underlying: any Error)

        var errorDescription: String? {
            switch self {
            case .sessionUnavailable:
                return "This video can't be exported on this device."
            case .failed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    let audioCensorBuilder: AudioCensorBuilder
    let tempFiles: TempFileManager

    /// Exports the censored video to a scratch `.mp4` and returns its URL.
    ///
    /// - Parameters:
    ///   - buildOverlayLayers: Builds the burn-in trees (overlay below,
    ///     captions on top) for the given asset duration and output size —
    ///     the source's native size, untouched. Must come from the same
    ///     builders as the preview.
    ///   - progress: Receives fraction-complete updates.
    /// - Throws: `ExportError`, `VideoSourceError`, or `CancellationError`.
    ///   Partial output is deleted on failure or cancellation.
    func export(
        sourceURL: URL,
        ranges: [CensorRange],
        beepSettings: BeepSettings,
        buildOverlayLayers: @MainActor (Double, CGSize) -> [CALayer],
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let built = try await CompositionBuilder.makeCensoredComposition(
            sourceURL: sourceURL,
            ranges: ranges,
            beepSettings: beepSettings,
            audioCensorBuilder: audioCensorBuilder
        )
        try Task.checkCancellation()

        // Parent and video layers must exactly equal the render size.
        let renderFrame = CGRect(origin: .zero, size: built.renderSize)
        let parentLayer = CALayer()
        parentLayer.frame = renderFrame
        // The animation tool evaluates layers in a bottom-left coordinate
        // space; the builders produce top-left geometry (shared with the
        // preview), so flip the parent once here.
        parentLayer.isGeometryFlipped = true
        let videoLayer = CALayer()
        videoLayer.frame = renderFrame
        parentLayer.addSublayer(videoLayer)
        for layer in buildOverlayLayers(built.durationSeconds, built.renderSize) {
            parentLayer.addSublayer(layer)
        }
        #if DEBUG
        Self.assertAnimationsExportSafe(parentLayer)
        #endif
        built.videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        // An export session is single-use; every attempt gets a fresh one.
        guard let session = Self.makeSession(for: built.composition) else {
            throw ExportError.sessionUnavailable
        }
        session.videoComposition = built.videoComposition
        session.audioMix = built.audioMix
        session.shouldOptimizeForNetworkUse = true

        let outputURL = tempFiles.makeScratchURL(fileExtension: "mp4")

        // Progress consumption must start BEFORE awaiting the export, or
        // the stream yields nothing and progress sits at zero.
        let progressTask = Task {
            for await state in session.states(updateInterval: 0.1) {
                if case .exporting(let exportProgress) = state {
                    progress(exportProgress.fractionCompleted)
                }
            }
        }
        defer { progressTask.cancel() }

        do {
            try await session.export(to: outputURL, as: .mp4)
        } catch {
            tempFiles.remove(outputURL)
            if error is CancellationError {
                Logger.export.notice("Export cancelled")
                throw error
            }
            Logger.export.error("Export failed: \(error.localizedDescription)")
            throw ExportError.failed(underlying: error)
        }
        Logger.export.info("Exported \(outputURL.lastPathComponent) at \(built.frameRate) fps")
        return outputURL
    }

    /// Export presets in descending quality order. The output raster is
    /// fixed at 1080×1920 by the video composition regardless of preset;
    /// the preset governs codec and bitrate. The highest-quality presets
    /// preserve far more of the source's detail through the unavoidable
    /// re-encode — HEVC first (best quality per bit; Instagram accepts it),
    /// then H.264 highest quality, then the standard 1080p preset as the
    /// floor for devices that support neither.
    private static let presetPreferenceOrder = [
        AVAssetExportPresetHEVCHighestQuality,
        AVAssetExportPresetHighestQuality,
        AVAssetExportPreset1920x1080,
    ]

    /// Creates the export session with the best supported preset.
    private static func makeSession(for asset: AVAsset) -> AVAssetExportSession? {
        for preset in presetPreferenceOrder {
            if let session = AVAssetExportSession(asset: asset, presetName: preset) {
                Logger.export.info("Export preset: \(preset, privacy: .public)")
                return session
            }
        }
        return nil
    }

    #if DEBUG
    /// Pre-export check for the silent-drop failure mode: an animation with
    /// a literal 0 beginTime is interpreted as "now" and discarded during
    /// export with no error raised.
    private static func assertAnimationsExportSafe(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] {
            guard let animation = layer.animation(forKey: key) else { continue }
            assert(
                animation.beginTime == AVCoreAnimationBeginTimeAtZero,
                "Export-unsafe animation \(key): beginTime must be AVCoreAnimationBeginTimeAtZero"
            )
            assert(!animation.isRemovedOnCompletion, "Export-unsafe animation \(key): must not be removed on completion")
        }
        for sublayer in layer.sublayers ?? [] {
            assertAnimationsExportSafe(sublayer)
        }
    }
    #endif
}
