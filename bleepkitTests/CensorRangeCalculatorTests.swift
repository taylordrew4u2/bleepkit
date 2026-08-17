//
//  CensorRangeCalculatorTests.swift
//  BleepKitTests
//

import CoreMedia
import Foundation
import Testing
@testable import bleepkit

@Suite("CensorRangeCalculator")
struct CensorRangeCalculatorTests {
    private let assetDuration = CMTime(seconds: 30, preferredTimescale: 600)

    private func censoredToken(start: Double, duration: Double) -> WordToken {
        WordToken(
            text: "x",
            startSeconds: start,
            durationSeconds: duration,
            confidence: 1,
            detectedProfane: true
        )
    }

    @Test("Two tokens 40ms apart with 60ms padding merge into one range")
    func closeTokensMerge() {
        let a = censoredToken(start: 1.0, duration: 0.3)   // ends 1.30
        let b = censoredToken(start: 1.34, duration: 0.3)  // 40ms gap
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [a, b], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.count == 1)
        #expect(ranges[0].sourceTokenIDs == [a.id, b.id])
    }

    @Test("Two tokens 500ms apart with 60ms padding remain two ranges")
    func distantTokensStaySeparate() {
        let a = censoredToken(start: 1.0, duration: 0.3)   // ends 1.30
        let b = censoredToken(start: 1.8, duration: 0.3)   // 500ms gap
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [a, b], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.count == 2)
    }

    @Test("A token at time zero clamps its start to zero")
    func clampsToZero() {
        let token = censoredToken(start: 0.0, duration: 0.2)
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [token], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.count == 1)
        #expect(ranges[0].start == .zero)
    }

    @Test("A token at the end clamps to the asset duration")
    func clampsToDuration() {
        let token = censoredToken(start: 29.9, duration: 0.2)  // would end at 30.16
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [token], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.count == 1)
        #expect(ranges[0].end == assetDuration)
    }

    @Test("sourceTokenIDs accumulates across a 3-way merge")
    func threeWayMergeAccumulatesIDs() {
        let a = censoredToken(start: 1.0, duration: 0.3)
        let b = censoredToken(start: 1.35, duration: 0.3)
        let c = censoredToken(start: 1.70, duration: 0.3)
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [a, b, c], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.count == 1)
        #expect(ranges[0].sourceTokenIDs == [a.id, b.id, c.id])
    }

    @Test("Non-censored tokens contribute nothing")
    func ignoresCleanTokens() {
        var clean = censoredToken(start: 2.0, duration: 0.3)
        clean.detectedProfane = false
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [clean], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.isEmpty)
    }

    @Test("Unsorted input still produces sorted, merged output")
    func unsortedInput() {
        let late = censoredToken(start: 5.0, duration: 0.2)
        let early = censoredToken(start: 1.0, duration: 0.2)
        let ranges = CensorRangeCalculator.censorRanges(
            tokens: [late, early], padding: 0.06, assetDuration: assetDuration
        )
        #expect(ranges.count == 2)
        #expect(ranges[0].start < ranges[1].start)
    }
}
