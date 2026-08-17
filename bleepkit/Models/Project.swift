//
//  Project.swift
//  BleepKit
//

import Foundation
import OSLog
import SwiftData

/// A saved editing session: one imported source video plus everything the
/// user has done to it.
///
/// The source video is stored by file name relative to `Documents/sources`,
/// never as an absolute URL — sandbox container paths change between launches
/// and installs. Value-type sub-models (tokens, styles, beep settings) are
/// persisted as JSON blobs and surfaced through typed computed properties.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var title: String
    /// File name inside `Documents/sources`, e.g. "4A9C….mov".
    var sourceFileName: String
    var durationSeconds: Double
    /// JSON-encoded `[WordToken]`.
    var tokensData: Data
    /// JSON-encoded `CaptionStyle`.
    var captionStyleData: Data
    /// JSON-encoded `CensorStyle`.
    var censorStyleData: Data
    /// JSON-encoded `BeepSettings`.
    var beepSettingsData: Data
    var overlayEnabled: Bool
    /// Sticker identifier, e.g. "emoji:🤬".
    var overlayAssetIdentifier: String?
    /// Normalized overlay center X, 0...1 in render space.
    var overlayPositionX: Double
    /// Normalized overlay center Y, 0...1 in render space (top-left origin).
    var overlayPositionY: Double
    /// When true the overlay tracks the censored caption word instead of
    /// the pinned position.
    var overlayFollowsCaption: Bool = false
    /// Enabled profanity severity tiers, e.g. ["mild", "strong", "slur"].
    var enabledSeverities: [String]

    init(title: String, sourceFileName: String, durationSeconds: Double) {
        self.id = UUID()
        self.createdAt = .now
        self.updatedAt = .now
        self.title = title
        self.sourceFileName = sourceFileName
        self.durationSeconds = durationSeconds
        self.tokensData = Self.encoded([WordToken]())
        self.captionStyleData = Self.encoded(CaptionStyle())
        self.censorStyleData = Self.encoded(CensorStyle.asterisks)
        self.beepSettingsData = Self.encoded(BeepSettings())
        self.overlayEnabled = false
        self.overlayAssetIdentifier = nil
        self.overlayPositionX = 0.5
        self.overlayPositionY = 0.5
        self.overlayFollowsCaption = false
        self.enabledSeverities = ["mild", "strong", "slur"]
    }
}

extension Project {
    /// Recognized words, decoded from `tokensData`. Setting re-encodes and
    /// bumps `updatedAt`.
    var tokens: [WordToken] {
        get { Self.decoded([WordToken].self, from: tokensData) ?? [] }
        set {
            tokensData = Self.encoded(newValue)
            updatedAt = .now
        }
    }

    var captionStyle: CaptionStyle {
        get { Self.decoded(CaptionStyle.self, from: captionStyleData) ?? CaptionStyle() }
        set {
            captionStyleData = Self.encoded(newValue)
            updatedAt = .now
        }
    }

    var censorStyle: CensorStyle {
        get { Self.decoded(CensorStyle.self, from: censorStyleData) ?? .asterisks }
        set {
            censorStyleData = Self.encoded(newValue)
            updatedAt = .now
        }
    }

    var beepSettings: BeepSettings {
        get { Self.decoded(BeepSettings.self, from: beepSettingsData) ?? BeepSettings() }
        set {
            beepSettingsData = Self.encoded(newValue)
            updatedAt = .now
        }
    }

    /// Encodes a sub-model, logging (rather than crashing) on the practically
    /// impossible failure of encoding these plain value types.
    private static func encoded(_ value: some Encodable) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            Logger.storage.error("Failed to encode \(String(describing: type(of: value))): \(error.localizedDescription)")
            return Data()
        }
    }

    /// Decodes a sub-model, returning nil (so the caller supplies defaults)
    /// when the stored blob is empty or from an incompatible schema version.
    private static func decoded<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Logger.storage.error("Failed to decode \(String(describing: type)): \(error.localizedDescription)")
            return nil
        }
    }
}
