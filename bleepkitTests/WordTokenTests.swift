//
//  WordTokenTests.swift
//  BleepKitTests
//

import CoreMedia
import Foundation
import Testing
@testable import bleepkit

@Suite("WordToken")
struct WordTokenTests {
    @Test("Codable round trip preserves every field")
    func codableRoundTrip() throws {
        var token = WordToken(
            text: "f***",
            displayText: "f***",
            startSeconds: 12.345,
            durationSeconds: 0.42,
            confidence: 0.87,
            detectedProfane: true,
            userOverride: false
        )
        token.userOverride = true

        let data = try JSONEncoder().encode(token)
        let decoded = try JSONDecoder().decode(WordToken.self, from: data)

        #expect(decoded == token)
        #expect(decoded.id == token.id)
        #expect(decoded.text == "f***")
        #expect(decoded.displayText == "f***")
        #expect(decoded.startSeconds == 12.345)
        #expect(decoded.durationSeconds == 0.42)
        #expect(decoded.confidence == 0.87)
        #expect(decoded.detectedProfane)
        #expect(decoded.userOverride == true)
    }

    @Test("Array round trip (the Project.tokensData format)")
    func arrayRoundTrip() throws {
        let tokens = [
            WordToken(text: "hello", startSeconds: 0, durationSeconds: 0.3, confidence: 0.9),
            WordToken(text: "world", startSeconds: 0.3, durationSeconds: 0.4, confidence: 0.8),
        ]
        let data = try JSONEncoder().encode(tokens)
        let decoded = try JSONDecoder().decode([WordToken].self, from: data)
        #expect(decoded == tokens)
    }

    @Test("CMTimeRange uses timescale 600")
    func timeRange() {
        let token = WordToken(text: "x", startSeconds: 1.5, durationSeconds: 0.5, confidence: 1)
        #expect(token.range.start.timescale == 600)
        #expect(token.range.start == CMTime(value: 900, timescale: 600))
        #expect(token.range.duration == CMTime(value: 300, timescale: 600))
    }

    @Test("isCensored honors override precedence")
    func censoredPrecedence() {
        var token = WordToken(text: "damn", startSeconds: 0, durationSeconds: 0.2, confidence: 1)
        #expect(!token.isCensored)
        token.detectedProfane = true
        #expect(token.isCensored)
        token.userOverride = false
        #expect(!token.isCensored)
    }
}
