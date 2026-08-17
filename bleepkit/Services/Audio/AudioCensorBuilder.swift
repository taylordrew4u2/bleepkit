//
//  AudioCensorBuilder.swift
//  BleepKit
//

import AVFoundation
import CoreMedia
import Foundation
import OSLog

/// Builds the censored audio: the source's audio inserted full-length on
/// Track A and muted across every censor range with short volume ramps,
/// plus a synthesized beep on Track B over each range.
///
/// Both this and the video overlay consume the same merged `CensorRange`
/// array from `CensorRangeCalculator`, which is what keeps the beep and the
/// visual censoring frame-aligned.
nonisolated struct AudioCensorBuilder: Sendable {
    enum BuildError: LocalizedError {
        /// A composition track could not be created or a beep file had no
        /// readable audio track.
        case trackCreationFailed

        var errorDescription: String? {
            switch self {
            case .trackCreationFailed:
                return "The censored audio tracks could not be created."
            }
        }
    }

    let beepGenerator: BeepGenerator

    /// Builds an audio-only composition plus its mix — used for the
    /// censored-audio export check and the audio preview.
    ///
    /// - Returns: nil when the source has no audio track; audio censoring
    ///   is skipped entirely (captions still work).
    func buildAudioComposition(
        sourceURL: URL,
        ranges: [CensorRange],
        settings: BeepSettings
    ) async throws -> (composition: AVMutableComposition, audioMix: AVMutableAudioMix)? {
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        guard let audioMix = try await addCensoredAudio(
            from: asset, to: composition, ranges: ranges, settings: settings
        ) else {
            return nil
        }
        return (composition, audioMix)
    }

    /// Inserts censored audio into an existing composition (the full
    /// export composition reuses this) and returns the mix to apply.
    ///
    /// Track A carries the source audio for the full duration; Track B
    /// carries one beep per censor range, synthesized at exactly the
    /// range's length and already at target level, so it needs no mix
    /// parameters of its own.
    ///
    /// - Returns: nil when `asset` has no audio track.
    func addCensoredAudio(
        from asset: AVURLAsset,
        to composition: AVMutableComposition,
        ranges: [CensorRange],
        settings: BeepSettings
    ) async throws -> AVMutableAudioMix? {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = audioTracks.first else {
            Logger.audio.notice("Source has no audio track; skipping audio censoring")
            return nil
        }
        let assetDuration = try await asset.load(.duration)

        guard let trackA = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw BuildError.trackCreationFailed
        }
        try trackA.insertTimeRange(
            CMTimeRange(start: .zero, duration: assetDuration),
            of: sourceTrack,
            at: .zero
        )

        let parameters = AVMutableAudioMixInputParameters(track: trackA)

        if !ranges.isEmpty {
            guard let trackB = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw BuildError.trackCreationFailed
            }
            for range in ranges {
                let rangeDuration = range.end - range.start
                let beepURL = try await beepGenerator.beepFile(
                    frequencyHz: settings.frequencyHz,
                    levelDBFS: settings.levelDBFS,
                    duration: rangeDuration.seconds
                )
                let beepAsset = AVURLAsset(url: beepURL)
                let beepTracks = try await beepAsset.loadTracks(withMediaType: .audio)
                guard let beepTrack = beepTracks.first else {
                    throw BuildError.trackCreationFailed
                }
                let beepDuration = try await beepAsset.load(.duration)
                try trackB.insertTimeRange(
                    CMTimeRange(start: .zero, duration: min(beepDuration, rangeDuration)),
                    of: beepTrack,
                    at: range.start
                )
                addMuteRamps(
                    to: parameters,
                    range: range,
                    assetDuration: assetDuration,
                    rampSeconds: settings.rampSeconds
                )
            }
            Logger.audio.info("Censored audio built: \(ranges.count) range(s)")
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = [parameters]
        return audioMix
    }

    /// Mutes Track A across one censor range.
    ///
    /// Edge cases handled explicitly:
    /// - A range shorter than 2 × ramp gets proportionally shortened ramps
    ///   rather than overlapping ones.
    /// - A range starting at exactly zero begins muted with no lead-in ramp.
    /// - A range ending at the asset's end stays muted with no tail ramp.
    private func addMuteRamps(
        to parameters: AVMutableAudioMixInputParameters,
        range: CensorRange,
        assetDuration: CMTime,
        rampSeconds: Double
    ) {
        let rangeSeconds = (range.end - range.start).seconds
        var ramp = rampSeconds
        if rangeSeconds < ramp * 2 {
            ramp = rangeSeconds / 2
        }
        let rampTime = CMTime.projectSeconds(ramp)

        if range.start == .zero {
            parameters.setVolume(0, at: .zero)
        } else if ramp > 0 {
            parameters.setVolumeRamp(
                fromStartVolume: 1,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: range.start, duration: rampTime)
            )
            parameters.setVolume(0, at: range.start + rampTime)
        } else {
            parameters.setVolume(0, at: range.start)
        }

        guard range.end < assetDuration else { return }
        if ramp > 0 {
            parameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: 1,
                timeRange: CMTimeRange(start: range.end - rampTime, duration: rampTime)
            )
        } else {
            parameters.setVolume(1, at: range.end)
        }
    }
}
