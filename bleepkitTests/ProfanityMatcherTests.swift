//
//  ProfanityMatcherTests.swift
//  BleepKitTests
//

import Foundation
import Testing
@testable import bleepkit

@Suite("ProfanityMatcher")
struct ProfanityMatcherTests {
    private let matcher: ProfanityMatcher
    private let allTiers: Set<ProfanitySeverity> = [.mild, .strong, .slur]

    init() throws {
        // Bundle.main is the host app when tests run in the app host.
        let list = try ProfanityList.loadBundled(from: Bundle.main)
        matcher = ProfanityMatcher(list: list)
    }

    // MARK: Gate 3 requirements

    @Test("Clean words are not flagged", arguments: [
        "assassin", "class", "analysis", "cockpit", "shiitake", "passage",
        "hello", "shell", "passes", "assess", "document", "titan", "bass",
    ])
    func cleanWordsPass(word: String) {
        #expect(matcher.match(word: word, enabledSeverities: allTiers) == nil)
    }

    @Test("Obfuscated and cased profanity is flagged", arguments: [
        "f*ck", "fuuuck", "sh1t", "@ss", "FUCK", "Fucking",
    ])
    func obfuscatedProfanityFlagged(word: String) {
        #expect(matcher.match(word: word, enabledSeverities: allTiers) != nil)
    }

    @Test("Recognizer-masked tokens are flagged", arguments: ["f***", "s***"])
    func maskedTokensFlagged(word: String) {
        #expect(matcher.match(word: word, enabledSeverities: allTiers) != nil)
    }

    @Test("A mild term is not flagged when the mild tier is disabled")
    func mildTierDisabled() {
        let strongOnly: Set<ProfanitySeverity> = [.strong, .slur]
        #expect(matcher.match(word: "damn", enabledSeverities: strongOnly) == nil)
        #expect(matcher.match(word: "damn", enabledSeverities: allTiers) == .mild)
    }

    @Test("A userOverride of false on a detected term yields isCensored == false")
    func overrideForcesAllow() {
        var token = WordToken(text: "fuck", startSeconds: 1, durationSeconds: 0.3, confidence: 0.9)
        token.detectedProfane = true
        #expect(token.isCensored)
        token.userOverride = false
        #expect(!token.isCensored)
        token.userOverride = true
        #expect(token.isCensored)
        token.userOverride = nil
        #expect(token.isCensored)
    }

    // MARK: Additional coverage

    @Test("Inflections are matched by suffix stripping")
    func inflections() {
        #expect(matcher.match(word: "fuckin'", enabledSeverities: allTiers) == .strong)
        #expect(matcher.match(word: "bitchin", enabledSeverities: allTiers) == .strong)
    }

    @Test("Slur tier hits even when not passed as enabled")
    func slurAlwaysEnabled() {
        let none: Set<ProfanitySeverity> = []
        #expect(matcher.match(word: "retard", enabledSeverities: none) == .slur)
    }

    @Test("Multi-word phrases mark every token in the window")
    func phrases() {
        let tokens = [
            WordToken(text: "son", startSeconds: 0.0, durationSeconds: 0.2, confidence: 1),
            WordToken(text: "of", startSeconds: 0.2, durationSeconds: 0.1, confidence: 1),
            WordToken(text: "a", startSeconds: 0.3, durationSeconds: 0.1, confidence: 1),
            WordToken(text: "bitch", startSeconds: 0.4, durationSeconds: 0.3, confidence: 1),
            WordToken(text: "okay", startSeconds: 0.8, durationSeconds: 0.3, confidence: 1),
        ]
        let annotated = matcher.annotate(tokens: tokens, enabledSeverities: allTiers)
        // "bitch" hits alone; "of"/"a" only via the phrase window. The
        // 3-token window "of a bitch" plus 2-token windows cover the rest.
        #expect(annotated[3].detectedProfane)
        #expect(!annotated[4].detectedProfane)
    }

    @Test("Annotate leaves user overrides untouched")
    func annotatePreservesOverrides() {
        var token = WordToken(text: "fuck", startSeconds: 0, durationSeconds: 0.2, confidence: 1)
        token.userOverride = false
        let annotated = matcher.annotate(tokens: [token], enabledSeverities: allTiers)
        #expect(annotated[0].detectedProfane)
        #expect(annotated[0].userOverride == false)
        #expect(!annotated[0].isCensored)
    }
}
