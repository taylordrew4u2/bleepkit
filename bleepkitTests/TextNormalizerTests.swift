//
//  TextNormalizerTests.swift
//  BleepKitTests
//

import Testing
@testable import bleepkit

@Suite("TextNormalizer")
struct TextNormalizerTests {
    @Test("Lowercases input")
    func lowercases() {
        #expect(TextNormalizer.normalize("FUCK") == "fuck")
        #expect(TextNormalizer.normalize("Fucking") == "fucking")
    }

    @Test("Strips diacritics via NFKD")
    func stripsDiacritics() {
        #expect(TextNormalizer.normalize("fúck") == "fuck")
        #expect(TextNormalizer.normalize("shït") == "shit")
    }

    @Test("Collapses runs of three or more identical characters to one")
    func collapsesRuns() {
        #expect(TextNormalizer.normalize("fuuuuck") == "fuck")
        #expect(TextNormalizer.normalize("shiiit") == "shit")
        // Runs of exactly two survive.
        #expect(TextNormalizer.normalize("ass") == "ass")
        #expect(TextNormalizer.normalize("hello") == "hello")
    }

    @Test("Applies leetspeak substitutions")
    func leetspeak() {
        #expect(TextNormalizer.normalize("sh1t") == "shit")
        #expect(TextNormalizer.normalize("@ss") == "ass")
        #expect(TextNormalizer.normalize("fu(k") == "fuk")  // ( is not mapped, only stripped
        #expect(TextNormalizer.normalize("b!tch") == "bitch")
        #expect(TextNormalizer.normalize("a$$") == "ass")
        #expect(TextNormalizer.normalize("5h17") == "shit")
    }

    @Test("Strips punctuation but keeps the meaningful asterisk")
    func punctuationAndAsterisks() {
        #expect(TextNormalizer.normalize("damn,") == "damn")
        #expect(TextNormalizer.normalize("f***") == "f***")
        #expect(TextNormalizer.normalize("f*ck!") == "f*ck")
        #expect(TextNormalizer.normalize("\"hell\"") == "hell")
        // A trailing "!" is punctuation, not leetspeak…
        #expect(TextNormalizer.normalize("hell!") == "hell")
        // …but boundary leet characters like "$" stay meaningful.
        #expect(TextNormalizer.normalize("a$$") == "ass")
    }

    @Test("Empty and symbol-only input yields empty output")
    func degenerateInput() {
        #expect(TextNormalizer.normalize("") == "")
        #expect(TextNormalizer.normalize("—…") == "")
    }
}
