//
//  ProfanityMatcher.swift
//  BleepKit
//

import Foundation

/// Detects profanity in normalized tokens.
///
/// Matching is whole-word only — substring matching creates the Scunthorpe
/// problem and would censor "class" and "assassin". The allowlist is a
/// second line of defense on top of that.
nonisolated struct ProfanityMatcher: Sendable {
    /// Single-word terms and variants, normalized, mapped to severity.
    private let wordSeverity: [String: ProfanitySeverity]
    /// Multi-word phrases (normalized words joined by single spaces).
    private let phraseSeverity: [String: ProfanitySeverity]
    /// Normalized words that must never be flagged.
    private let allowlist: Set<String>

    /// Suffixes stripped (once, longest first) to catch inflections not
    /// covered by explicit variants. The apostrophe in "-in'" is gone by
    /// normalization time, so it reduces to "-in".
    private static let strippableSuffixes = ["ing", "in", "es", "ed", "er", "s"]

    init(list: ProfanityList) {
        var words: [String: ProfanitySeverity] = [:]
        var phrases: [String: ProfanitySeverity] = [:]
        for term in list.terms {
            for spelling in [term.term] + term.variants {
                let parts = spelling
                    .split(whereSeparator: \.isWhitespace)
                    .map { TextNormalizer.normalize(String($0)) }
                    .filter { !$0.isEmpty }
                guard !parts.isEmpty else { continue }
                if parts.count > 1 {
                    phrases[parts.joined(separator: " ")] = term.severity
                } else {
                    words[parts[0]] = term.severity
                }
            }
        }
        wordSeverity = words
        phraseSeverity = phrases
        allowlist = Set(list.allowlist.map(TextNormalizer.normalize))
    }

    /// Whether the token is a recognizer-masked word like "f***".
    ///
    /// Apple's recognizers are known to return profanity pre-masked; the
    /// mask itself is a reliable detection signal, and the token's timing
    /// remains valid. Masked tokens count as hits regardless of enabled
    /// severity tiers, since the underlying word is unknowable.
    static func isMasked(_ normalized: String) -> Bool {
        normalized.wholeMatch(of: /\w?\*{2,}\w?/) != nil
    }

    /// Matches one word (raw, un-normalized) against the vocabulary.
    ///
    /// - Returns: The hit's severity, or nil when the word is clean, is
    ///   allowlisted, or its severity tier is disabled.
    func match(word: String, enabledSeverities: Set<ProfanitySeverity>) -> ProfanitySeverity? {
        let normalized = TextNormalizer.normalize(word)
        guard !normalized.isEmpty else { return nil }
        guard !allowlist.contains(normalized) else { return nil }

        if Self.isMasked(normalized) { return .strong }

        if let severity = enabledLookup(normalized, enabledSeverities) {
            return severity
        }

        // Inflections not covered by explicit variants: strip one suffix
        // and retry, honoring the allowlist at every step ("passes" strips
        // to allowlisted "pass" and stops).
        for suffix in Self.strippableSuffixes
        where normalized.count > suffix.count && normalized.hasSuffix(suffix) {
            let stem = String(normalized.dropLast(suffix.count))
            if allowlist.contains(stem) { return nil }
            if let severity = enabledLookup(stem, enabledSeverities) {
                return severity
            }
        }

        // Partially masked words like "f*ck": each asterisk stands for
        // exactly one character.
        if normalized.contains("*") {
            for (term, severity) in wordSeverity where term.count == normalized.count {
                guard isEnabled(severity, enabledSeverities) else { continue }
                if zip(normalized, term).allSatisfy({ $0 == "*" || $0 == $1 }) {
                    return severity
                }
            }
        }
        return nil
    }

    /// Sets `detectedProfane` on every token: single words first, then
    /// multi-word phrases over consecutive windows of 2 and 3 tokens.
    /// User overrides are untouched.
    func annotate(tokens: [WordToken], enabledSeverities: Set<ProfanitySeverity>) -> [WordToken] {
        var result = tokens
        for index in result.indices {
            result[index].detectedProfane = match(
                word: result[index].text,
                enabledSeverities: enabledSeverities
            ) != nil
        }

        guard !phraseSeverity.isEmpty, tokens.count >= 2 else { return result }
        let normalizedWords = tokens.map { TextNormalizer.normalize($0.text) }
        for windowSize in 2...3 where tokens.count >= windowSize {
            for start in 0...(tokens.count - windowSize) {
                let phrase = normalizedWords[start..<(start + windowSize)].joined(separator: " ")
                if let severity = phraseSeverity[phrase], isEnabled(severity, enabledSeverities) {
                    for index in start..<(start + windowSize) {
                        result[index].detectedProfane = true
                    }
                }
            }
        }
        return result
    }

    private func enabledLookup(_ word: String, _ enabled: Set<ProfanitySeverity>) -> ProfanitySeverity? {
        guard let severity = wordSeverity[word], isEnabled(severity, enabled) else { return nil }
        return severity
    }

    /// A term counts only when its tier is enabled; the slur tier is
    /// always on.
    private func isEnabled(_ severity: ProfanitySeverity, _ enabled: Set<ProfanitySeverity>) -> Bool {
        severity == .slur || enabled.contains(severity)
    }
}
