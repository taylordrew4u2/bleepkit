//
//  Transcript.swift
//  BleepKit
//

import Foundation

/// The complete result of transcribing one source video.
nonisolated struct Transcript: Hashable, Sendable, Codable {
    /// Every recognized word in timeline order.
    var tokens: [WordToken]
    /// BCP-47 identifier of the locale the engine transcribed against.
    var localeIdentifier: String
    /// Identifier of the engine that produced this transcript
    /// (see `TranscriptionEngine.identifier`), surfaced in the editor so
    /// behavior differences between engines are diagnosable in the field.
    var engineIdentifier: String

    /// True when the engine produced no words at all.
    var isEmpty: Bool { tokens.isEmpty }

    /// End of the last token, in seconds; zero for an empty transcript.
    var lastTokenEndSeconds: Double {
        tokens.map(\.endSeconds).max() ?? 0
    }
}
