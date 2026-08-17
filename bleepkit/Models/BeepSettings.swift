//
//  BeepSettings.swift
//  BleepKit
//

import Foundation

/// Parameters of the synthesized censor beep.
nonisolated struct BeepSettings: Codable, Hashable, Sendable {
    /// Beep tone frequency in hertz. UI range 400...2000.
    var frequencyHz: Double = 1000
    /// Beep loudness in dBFS. UI range -24...(-6).
    var levelDBFS: Double = -12
    /// Extra time added before and after each censored word, compensating
    /// for recognizer word-boundary drift. UI range 0...0.2.
    var paddingSeconds: Double = 0.06
    /// Length of the source-audio mute fade at each censor boundary.
    var rampSeconds: Double = 0.02

    /// Linear amplitude for the configured dBFS level.
    var amplitude: Double { pow(10, levelDBFS / 20) }
}
