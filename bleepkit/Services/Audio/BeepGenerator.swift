//
//  BeepGenerator.swift
//  BleepKit
//

import AVFAudio
import Foundation
import OSLog

/// Synthesizes censor beep tones at runtime — no audio asset ships with the
/// app. Generated files are cached per (frequency, level, duration) for the
/// session; the launch-time scratch purge clears them.
actor BeepGenerator {
    /// Cache key with quantized components so float noise can't defeat it.
    private struct CacheKey: Hashable {
        let frequencyMilliHz: Int
        let levelCentiDB: Int
        let durationMilliseconds: Int
    }

    enum BeepError: LocalizedError {
        /// The standard PCM format or buffer could not be created.
        case synthesisUnavailable

        var errorDescription: String? {
            switch self {
            case .synthesisUnavailable:
                return "The censor beep could not be synthesized."
            }
        }
    }

    private let tempFiles: TempFileManager
    private var cache: [CacheKey: URL] = [:]

    init(tempFiles: TempFileManager) {
        self.tempFiles = tempFiles
    }

    /// Returns a `.caf` containing a mono sine tone of exactly `duration`
    /// seconds at `frequencyHz` and `levelDBFS`.
    ///
    /// A 5 ms cosine attack and release is applied — a raw sine that starts
    /// or ends at a non-zero sample produces an audible click at every
    /// censor boundary.
    func beepFile(frequencyHz: Double, levelDBFS: Double, duration: Double) throws -> URL {
        let key = CacheKey(
            frequencyMilliHz: Int((frequencyHz * 1000).rounded()),
            levelCentiDB: Int((levelDBFS * 100).rounded()),
            durationMilliseconds: Int((duration * 1000).rounded())
        )
        if let cached = cache[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        let url = tempFiles.makeScratchURL(fileExtension: "caf")
        try Self.synthesize(to: url, frequencyHz: frequencyHz, levelDBFS: levelDBFS, duration: duration)
        cache[key] = url
        return url
    }

    private static func synthesize(
        to url: URL,
        frequencyHz: Double,
        levelDBFS: Double,
        duration: Double
    ) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw BeepError.synthesisUnavailable
        }
        let frameCount = AVAudioFrameCount(max(1, (duration * sampleRate).rounded()))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else {
            throw BeepError.synthesisUnavailable
        }
        let channel = channelData[0]
        buffer.frameLength = frameCount

        let amplitude = pow(10, levelDBFS / 20)
        let envelopeFrames = Int(0.005 * sampleRate)  // 5 ms cosine attack/release
        let totalFrames = Int(frameCount)
        for frame in 0..<totalFrames {
            let time = Double(frame) / sampleRate
            var sample = sin(2.0 * .pi * frequencyHz * time) * amplitude
            // Cosine attack.
            if frame < envelopeFrames {
                sample *= 0.5 * (1 - cos(.pi * Double(frame) / Double(envelopeFrames)))
            }
            // Cosine release.
            let framesFromEnd = totalFrames - frame
            if framesFromEnd < envelopeFrames {
                sample *= 0.5 * (1 - cos(.pi * Double(framesFromEnd) / Double(envelopeFrames)))
            }
            channel[frame] = Float(sample)
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        Logger.audio.debug("Synthesized \(frequencyHz, format: .fixed(precision: 0))Hz beep, \(duration, format: .fixed(precision: 3))s at \(levelDBFS, format: .fixed(precision: 1))dBFS")
    }
}
