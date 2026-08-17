//
//  TranscriptionService.swift
//  BleepKit
//

import Foundation
import OSLog
import Speech

/// Façade over the two transcription engines.
///
/// Selects `SpeechAnalyzerEngine` on iOS 26+ when the locale is supported,
/// falling back to `LegacySpeechEngine` when the OS is older, the locale is
/// unsupported, or the language model cannot be downloaded (for example,
/// no network on first run).
nonisolated struct TranscriptionService: Sendable {
    /// Requests speech-recognition authorization; returns the current status
    /// immediately if the user has already decided.
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// Transcribes the audio file with the best available engine.
    ///
    /// - Parameters:
    ///   - audioURL: The extracted `.m4a` produced by `AudioExtractor`.
    ///   - locale: The language to transcribe against.
    ///   - preparation: Receives progress milestones for the UI.
    /// - Returns: A transcript whose `engineIdentifier` names the engine
    ///   that actually ran.
    /// - Throws: `TranscriptionError`, `CancellationError`, or an underlying
    ///   recognizer failure.
    func transcribe(
        audioURL: URL,
        locale: Locale,
        preparation: (@Sendable (TranscriptionPreparationEvent) -> Void)? = nil
    ) async throws -> Transcript {
        let status = await Self.requestAuthorization()
        guard status == .authorized else {
            throw TranscriptionError.notAuthorized
        }

        if #available(iOS 26.0, *) {
            if await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil {
                let engine = SpeechAnalyzerEngine(preparationHandler: preparation)
                do {
                    let tokens = try await engine.transcribe(audioURL: audioURL, locale: locale)
                    return Transcript(
                        tokens: tokens,
                        localeIdentifier: locale.identifier,
                        engineIdentifier: engine.identifier
                    )
                } catch let error as TranscriptionError {
                    if Task.isCancelled { throw CancellationError() }
                    guard case .modelUnavailable = error else { throw error }
                    // Model download unavailable — fall through to the
                    // legacy engine so first-run-without-network still works.
                    Logger.transcription.warning("Language model unavailable; falling back to legacy engine: \(error.localizedDescription)")
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    throw error
                }
            } else {
                Logger.transcription.notice("SpeechTranscriber does not support \(locale.identifier); using legacy engine")
            }
        }

        let engine = LegacySpeechEngine()
        preparation?(.transcribing)
        do {
            let tokens = try await engine.transcribe(audioURL: audioURL, locale: locale)
            return Transcript(
                tokens: tokens,
                localeIdentifier: locale.identifier,
                engineIdentifier: engine.identifier
            )
        } catch {
            // A cancelled SFSpeechRecognitionTask surfaces a domain error,
            // not CancellationError; normalize it for callers.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
}
