//
//  SpeechAnalyzerEngine.swift
//  BleepKit
//

import AVFAudio
import CoreMedia
import Foundation
import OSLog
import Speech

/// Transcription engine backed by the iOS 26 `SpeechAnalyzer` API family.
///
/// Entirely on-device. Word timing comes from the `audioTimeRange` attribute
/// on the result's `AttributedString` runs — requesting that attribute option
/// is mandatory; without it the tokens have no timestamps and the entire
/// product is impossible.
@available(iOS 26.0, *)
nonisolated struct SpeechAnalyzerEngine: TranscriptionEngine {
    /// The API family exists on this OS; locale and model checks are
    /// asynchronous and happen inside `transcribe(audioURL:locale:)`.
    static var isAvailable: Bool { true }

    let identifier = "SpeechAnalyzer"

    /// Called as the engine moves through preparation milestones.
    var preparationHandler: (@Sendable (TranscriptionPreparationEvent) -> Void)?

    func transcribe(audioURL: URL, locale: Locale) async throws -> [WordToken] {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw TranscriptionError.localeUnsupported(locale.identifier)
        }

        // audioTimeRange is the source of word timing; transcriptionConfidence
        // feeds WordToken.confidence. Do not attach SpeechDetector — this app
        // needs no voice-activity detection, and the iOS 26.0 SDK has a known
        // SpeechModule conformance defect with it.
        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )

        // The language model is not bundled with the app binary. This returns
        // nil when the model is already installed; otherwise download it,
        // surfacing a "Preparing language model" state.
        do {
            if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                preparationHandler?(.downloadingModel)
                try await installationRequest.downloadAndInstall()
            }
        } catch {
            throw TranscriptionError.modelUnavailable(underlying: error)
        }

        preparationHandler?(.transcribing)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Start draining results before feeding audio so nothing is missed.
        async let collected = Self.collectTokens(from: transcriber)

        do {
            let audioFile = try AVAudioFile(forReading: audioURL)
            if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
                // Finalize so every remaining result is published, then end
                // the session, which terminates the results stream above.
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            // Tear the session down (also on cancellation) so the module's
            // result stream ends instead of leaking the analysis.
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let tokens = try await collected
        return tokens.sorted { $0.startSeconds < $1.startSeconds }
    }

    /// Drains the transcriber's result stream until the analyzer finishes
    /// the session.
    private static func collectTokens(from transcriber: SpeechTranscriber) async throws -> [WordToken] {
        var tokens: [WordToken] = []
        for try await result in transcriber.results {
            tokens.append(contentsOf: wordTokens(in: result.text))
        }
        return tokens
    }

    /// Maps an attributed transcription to word tokens.
    ///
    /// Results arrive as `AttributedString`, not a segments array. Each run
    /// carries an optional `audioTimeRange` (`CMTimeRange`). Runs without a
    /// time range (punctuation, whitespace) are skipped. Runs containing
    /// several words are split on whitespace, subdividing the run's time
    /// range proportionally by character count.
    private static func wordTokens(in text: AttributedString) -> [WordToken] {
        var tokens: [WordToken] = []
        for run in text.runs {
            guard let timeRange = run.audioTimeRange else { continue }
            let confidence: Float
            if let value = run.transcriptionConfidence {
                confidence = Float(value)
            } else {
                confidence = 0
            }
            let runText = String(text.characters[run.range])
            let words = runText.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !words.isEmpty else { continue }

            let startSeconds = timeRange.start.seconds
            let totalDuration = timeRange.duration.seconds
            if words.count == 1 {
                tokens.append(WordToken(
                    text: words[0],
                    startSeconds: startSeconds,
                    durationSeconds: totalDuration,
                    confidence: confidence
                ))
            } else {
                let totalCharacters = words.reduce(0) { $0 + $1.count }
                var cursor = startSeconds
                for word in words {
                    let fraction = Double(word.count) / Double(totalCharacters)
                    let wordDuration = totalDuration * fraction
                    tokens.append(WordToken(
                        text: word,
                        startSeconds: cursor,
                        durationSeconds: wordDuration,
                        confidence: confidence
                    ))
                    cursor += wordDuration
                }
            }
        }
        return tokens
    }
}
