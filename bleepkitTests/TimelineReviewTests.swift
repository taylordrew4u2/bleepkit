import CoreMedia
import Testing
@testable import bleepkit

@Suite("Timeline review")
struct TimelineReviewTests {
    @Test("Next bleep honors effective overrides and chronological order")
    func effectiveCensoring() {
        let allowed = WordToken(text: "damn", startSeconds: 1, durationSeconds: 0.2, confidence: 1, detectedProfane: true, userOverride: false)
        let manual = WordToken(text: "word", startSeconds: 2, durationSeconds: 0.2, confidence: 1, userOverride: true)
        let detected = WordToken(text: "hell", startSeconds: 4, durationSeconds: 0.2, confidence: 1, detectedProfane: true)
        let tokens = [detected, allowed, manual]
        #expect(TimelineReview.nextCensoredToken(in: tokens, after: 0)?.id == manual.id)
        #expect(TimelineReview.nextCensoredToken(in: tokens, after: 2)?.id == detected.id)
        #expect(TimelineReview.nextCensoredToken(in: tokens, after: 5)?.id == manual.id)
        #expect(TimelineReview.nextCensoredToken(in: [allowed], after: 0) == nil)
    }

    @Test("Timeline markers clamp to the video and omit invalid spans")
    func markerGeometry() {
        let ranges = [
            CensorRange(start: CMTime(seconds: -1, preferredTimescale: 600), end: CMTime(seconds: 2, preferredTimescale: 600), sourceTokenIDs: []),
            CensorRange(start: CMTime(seconds: 8, preferredTimescale: 600), end: CMTime(seconds: 12, preferredTimescale: 600), sourceTokenIDs: []),
            CensorRange(start: .invalid, end: .invalid, sourceTokenIDs: []),
            CensorRange(start: CMTime(seconds: 15, preferredTimescale: 600), end: CMTime(seconds: 16, preferredTimescale: 600), sourceTokenIDs: []),
        ]
        #expect(TimelineReview.normalizedIntervals(for: ranges, durationSeconds: 10) == [0...0.2, 0.8...1])
        #expect(TimelineReview.normalizedIntervals(for: ranges, durationSeconds: 0).isEmpty)
        #expect(TimelineReview.normalizedIntervals(for: ranges, durationSeconds: .nan).isEmpty)
    }
}
