//
//  ProfanityList.swift
//  BleepKit
//

import Foundation

/// Severity tiers for profanity terms. The `slur` tier is enabled by
/// default and non-toggleable — creators almost never want those uncensored.
nonisolated enum ProfanitySeverity: String, Codable, Sendable, CaseIterable {
    case mild
    case strong
    case slur
}

/// The bundled profanity vocabulary, decoded from `profanity_en.json`.
/// Bundled with the app — never fetched from the network.
nonisolated struct ProfanityList: Codable, Sendable {
    /// One base term with its severity and explicit inflected variants.
    struct Term: Codable, Sendable {
        let term: String
        let severity: ProfanitySeverity
        let variants: [String]
    }

    let version: Int
    let terms: [Term]
    /// Whole words that must never be flagged, guarding against
    /// inflection-stripping accidents (the Scunthorpe problem's second
    /// line of defense; whole-word matching is the first).
    let allowlist: [String]

    /// Loads the list bundled with the app.
    static func loadBundled(from bundle: Bundle = .main) throws -> ProfanityList {
        guard let url = bundle.url(forResource: "profanity_en", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "profanity_en.json is missing from the app bundle."
            ])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ProfanityList.self, from: data)
    }
}
