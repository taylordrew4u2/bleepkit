//
//  LegacySpeechEngine.swift
//  BleepKit
//

import Foundation
import os
import OSLog
import Speech

/// Transcription engine backed by `SFSpeechRecognizer`, for iOS 18–25 and
/// as a fallback when the iOS 26 language model cannot be downloaded.
///
/// This file contains the only completion-handler code in the project,
/// bridged to async through a continuation that is guarded against
/// double-resume — a misconfigured recognition task can fire its handler
/// more than once.
nonisolated struct LegacySpeechEngine: TranscriptionEngine {
    /// `SFSpeechRecognizer` exists on every OS version this app supports.
    static var isAvailable: Bool { true }

    let identifier = "SFSpeechRecognizer"

    func transcribe(audioURL: URL, locale: Locale) async throws -> [WordToken] {
        guard let recognizer = SFSpeechRecognizer(locale: locale)
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            throw TranscriptionError.recognizerUnavailable
        }
        guard recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        Logger.transcription.info("Legacy engine starting (onDevice: \(recognizer.supportsOnDeviceRecognition))")
        return try await Self.run(recognizer: recognizer, request: request)
    }

    /// State shared between the recognition callback, the continuation, and
    /// the cancellation handler. Protected by an unfair lock.
    private struct RecognitionState {
        var task: SFSpeechRecognitionTask?
        var resumed = false
        var cancelled = false
    }

    /// Bridges the callback API to async, cancelling the recognition task
    /// when the surrounding Swift task is cancelled.
    private static func run(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> [WordToken] {
        let state = OSAllocatedUnfairLock(uncheckedState: RecognitionState())
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[WordToken], any Error>) in
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        let shouldResume = state.withLockUnchecked { s -> Bool in
                            guard !s.resumed else { return false }
                            s.resumed = true
                            return true
                        }
                        if shouldResume {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let result, result.isFinal else { return }
                    let shouldResume = state.withLockUnchecked { s -> Bool in
                        guard !s.resumed else { return false }
                        s.resumed = true
                        return true
                    }
                    if shouldResume {
                        continuation.resume(returning: wordTokens(in: result.bestTranscription))
                    }
                }
                let alreadyCancelled = state.withLockUnchecked { s -> Bool in
                    s.task = task
                    return s.cancelled
                }
                // The surrounding task may have been cancelled before the
                // recognition task existed; honor that now.
                if alreadyCancelled {
                    task.cancel()
                }
            }
        } onCancel: {
            state.withLockUnchecked { s in
                s.cancelled = true
                s.task?.cancel()
            }
        }
    }

    /// Maps `SFTranscriptionSegment`s — the legacy API's word-timing source —
    /// to word tokens.
    private static func wordTokens(in transcription: SFTranscription) -> [WordToken] {
        transcription.segments.map { segment in
            WordToken(
                text: segment.substring,
                startSeconds: segment.timestamp,
                durationSeconds: segment.duration,
                confidence: segment.confidence
            )
        }
    }
}
