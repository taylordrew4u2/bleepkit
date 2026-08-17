//
//  TranscriptionEngine.swift
//  BleepKit
//

import Foundation
import Speech

/// A speech-to-text engine that produces word-level tokens with timing.
///
/// Two implementations exist: `SpeechAnalyzerEngine` (iOS 26+) and
/// `LegacySpeechEngine` (`SFSpeechRecognizer`). `TranscriptionService`
/// selects between them at runtime.
nonisolated protocol TranscriptionEngine: Sendable {
    /// Whether this engine can run at all on this device and OS.
    /// Deeper checks (locale support, model installation) happen inside
    /// `transcribe(audioURL:locale:)` because they are asynchronous.
    static var isAvailable: Bool { get }

    /// Human-readable engine name, surfaced in the editor debug label so
    /// behavior differences between engines are diagnosable in the field.
    var identifier: String { get }

    /// Transcribes the audio file, returning one token per recognized word
    /// in timeline order.
    func transcribe(audioURL: URL, locale: Locale) async throws -> [WordToken]
}

/// Progress milestones surfaced to the UI while an engine prepares and runs.
nonisolated enum TranscriptionPreparationEvent: Sendable {
    /// The iOS 26 language model is downloading (first run only).
    case downloadingModel
    /// Analysis of the audio is underway.
    case transcribing

    /// Text for the UI's progress state.
    var userDescription: String {
        switch self {
        case .downloadingModel: "Preparing language model…"
        case .transcribing: "Transcribing…"
        }
    }
}

/// Failures raised by the transcription pipeline.
nonisolated enum TranscriptionError: LocalizedError {
    /// The user declined (or policy restricts) speech recognition.
    case notAuthorized
    /// The recognizer exists but reports itself unavailable.
    case recognizerUnavailable
    /// Neither engine supports the requested locale.
    case localeUnsupported(String)
    /// The iOS 26 language model is not installed and could not be
    /// downloaded (for example, no network on first run).
    case modelUnavailable(underlying: any Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "BleepKit isn't allowed to use speech recognition. You can change this in Settings."
        case .recognizerUnavailable:
            return "Speech recognition isn't available right now. Try again in a moment."
        case .localeUnsupported(let identifier):
            return "Speech recognition doesn't support the \(identifier) language on this device."
        case .modelUnavailable(let underlying):
            return "The speech model isn't installed and couldn't be downloaded: \(underlying.localizedDescription)"
        }
    }
}
