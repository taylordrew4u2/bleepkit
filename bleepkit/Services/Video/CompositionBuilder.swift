//
//  CompositionBuilder.swift
//  BleepKit
//

import AVFoundation
import CoreGraphics
import Foundation

/// Failures raised while reading a source video or building a composition.
nonisolated enum VideoSourceError: LocalizedError {
    /// The file contains no video track at all.
    case noVideoTrack
    /// A composition track could not be created.
    case compositionTrackUnavailable

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "This file doesn't contain a video track."
        case .compositionTrackUnavailable:
            return "The video couldn't be prepared for playback."
        }
    }
}

/// A censored composition ready for playback or export: the source video
/// upright at its native size plus muted-and-beeped audio.
nonisolated struct CensoredComposition {
    let composition: AVMutableComposition
    let videoComposition: AVMutableVideoComposition
    /// nil when the source has no audio track.
    let audioMix: AVMutableAudioMix?
    let durationSeconds: Double
    /// Output frame rate, clamped to 24/25/30/60.
    let frameRate: Int32
    /// The output raster — the source's oriented display size, untouched.
    let renderSize: CGSize
}

/// Fixed output geometry and the orientation math shared by import,
/// composition, and export.
///
/// Grows in later phases into the full `AVMutableComposition` builder; the
/// geometry lives here from Phase 1 because the import flow already needs
/// orientation-normalized display sizes.
nonisolated enum CompositionBuilder {
    /// The style reference space: caption style values (font size, padding,
    /// stroke) are defined at this width and scaled proportionally to the
    /// actual target. It is NOT the output raster — output matches the
    /// source's native size, untouched.
    static let renderSize = CGSize(width: 1080, height: 1920)

    /// The size the source displays at once its `preferredTransform`
    /// (recorded orientation) is applied.
    static func displaySize(naturalSize: CGSize, preferredTransform: CGAffineTransform) -> CGSize {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        return CGSize(width: abs(transformed.width), height: abs(transformed.height))
    }

    /// The transform that renders the raw track upright at its native size —
    /// the recorded orientation applied, nothing scaled, nothing cropped.
    /// The source frame stays untouched; only captions, overlays, and audio
    /// are added on top.
    ///
    /// Works for all four `preferredTransform` orientations (0°, 90°, 180°,
    /// 270°): the transformed rect is translated so its origin sits at zero.
    static func orientationTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGAffineTransform {
        let transformed = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        guard transformed.width > 0, transformed.height > 0 else { return .identity }
        return preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformed.minX, y: -transformed.minY)
        )
    }

    /// Rounds a render dimension to the even integer video encoders require.
    static func evenDimension(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }
}

extension CompositionBuilder {
    /// Clamps a source's nominal frame rate to the supported output set.
    /// Unknown (zero) rates fall back to 30 fps.
    static func clampedFrameRate(_ nominal: Float) -> Int32 {
        guard nominal > 0 else { return 30 }
        switch nominal {
        case ..<24.5: return 24
        case ..<27.5: return 25
        case ..<45: return 30
        default: return 60
        }
    }

    /// Builds the censored composition shared by preview and export: the
    /// source video inserted full-length, upright, at its native size —
    /// aspect ratio and framing untouched — plus the censored audio tracks
    /// from `AudioCensorBuilder`.
    ///
    /// Preview applies the returned video composition and audio mix to an
    /// `AVPlayerItem`; export applies them to the export session — same
    /// inputs, which is what keeps the two in lockstep.
    static func makeCensoredComposition(
        sourceURL: URL,
        ranges: [CensorRange],
        beepSettings: BeepSettings,
        audioCensorBuilder: AudioCensorBuilder
    ) async throws -> CensoredComposition {
        let asset = AVURLAsset(url: sourceURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw VideoSourceError.noVideoTrack
        }
        let duration = try await asset.load(.duration)
        let (preferredTransform, naturalSize, nominalFrameRate) = try await sourceVideoTrack.load(
            .preferredTransform, .naturalSize, .nominalFrameRate
        )

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoSourceError.compositionTrackUnavailable
        }
        try videoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        let audioMix = try await audioCensorBuilder.addCensoredAudio(
            from: asset, to: composition, ranges: ranges, settings: beepSettings
        )

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layerInstruction.setTransform(
            orientationTransform(naturalSize: naturalSize, preferredTransform: preferredTransform),
            at: .zero
        )
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        // Output at the source's oriented size (rounded to the even pixels
        // encoders require) — no scaling, no cropping.
        let oriented = displaySize(naturalSize: naturalSize, preferredTransform: preferredTransform)
        let outputSize = CGSize(
            width: evenDimension(oriented.width),
            height: evenDimension(oriented.height)
        )
        videoComposition.renderSize = outputSize
        let frameRate = clampedFrameRate(nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: frameRate)
        videoComposition.instructions = [instruction]

        return CensoredComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            durationSeconds: duration.seconds,
            frameRate: frameRate,
            renderSize: outputSize
        )
    }
}

/// Everything the import flow needs to know about a source video, loaded
/// asynchronously — no synchronous `AVAsset` property access anywhere.
nonisolated struct SourceVideoMetadata: Sendable {
    let durationSeconds: Double
    /// Raw encoded pixel size, before orientation.
    let naturalSize: CGSize
    /// Size after applying `preferredTransform` — what the viewer sees.
    let displaySize: CGSize
    let nominalFrameRate: Float
    let preferredTransform: CGAffineTransform
    let hasAudioTrack: Bool

    /// Loads duration, track geometry, and audio presence from the file.
    static func load(from url: URL) async throws -> SourceVideoMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = videoTracks.first else { throw VideoSourceError.noVideoTrack }
        let (transform, naturalSize, frameRate) = try await track.load(
            .preferredTransform, .naturalSize, .nominalFrameRate
        )
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        return SourceVideoMetadata(
            durationSeconds: duration.seconds,
            naturalSize: naturalSize,
            displaySize: CompositionBuilder.displaySize(naturalSize: naturalSize, preferredTransform: transform),
            nominalFrameRate: frameRate,
            preferredTransform: transform,
            hasAudioTrack: !audioTracks.isEmpty
        )
    }
}
