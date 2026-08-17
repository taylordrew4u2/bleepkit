//
//  WordToken.swift
//  BleepKit
//

import CoreMedia
import Foundation

/// A single recognized word with its position on the source timeline.
///
/// `CMTime` values are not persisted directly; seconds are stored as `Double`
/// and reconstructed at timescale 600, which divides evenly into 24, 25, 30,
/// and 60 fps timelines.
nonisolated struct WordToken: Identifiable, Hashable, Sendable, Codable {
    let id: UUID
    /// The word as recognized. May arrive pre-masked as "f***".
    var text: String
    /// What the caption renders after censor treatment.
    var displayText: String
    /// Start of the word, in seconds from the start of the audio.
    var startSeconds: Double
    /// Length of the word, in seconds.
    var durationSeconds: Double
    /// Recognizer confidence, 0...1. Zero when the engine reports none.
    var confidence: Float
    /// Result of `ProfanityMatcher` detection.
    var detectedProfane: Bool
    /// nil = use detection, true = force censor, false = force allow.
    var userOverride: Bool?

    /// Whether this word is censored after applying any user override.
    var isCensored: Bool { userOverride ?? detectedProfane }

    /// End of the word, in seconds from the start of the audio.
    var endSeconds: Double { startSeconds + durationSeconds }

    /// The word's position as a `CMTimeRange` at the project timescale.
    var range: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: startSeconds, preferredTimescale: 600),
            duration: CMTime(seconds: durationSeconds, preferredTimescale: 600)
        )
    }

    init(
        id: UUID = UUID(),
        text: String,
        displayText: String? = nil,
        startSeconds: Double,
        durationSeconds: Double,
        confidence: Float,
        detectedProfane: Bool = false,
        userOverride: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.displayText = displayText ?? text
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.confidence = confidence
        self.detectedProfane = detectedProfane
        self.userOverride = userOverride
    }
}
