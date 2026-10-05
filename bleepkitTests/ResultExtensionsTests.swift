//
//  ResultExtensionsTests.swift
//  BleepKitTests
//

import Foundation
import Testing
@testable import bleepkit

@Suite("Result extensions")
struct ResultExtensionsTests {
    @Test("Detects Cocoa user cancellation")
    func detectsUserCancellation() {
        let result = Result<Void, Error>.failure(
            NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )

        #expect(result.isUserCancellation)
    }

    @Test("Does not treat unrelated failures as cancellation")
    func rejectsUnrelatedFailures() {
        let result = Result<Void, Error>.failure(
            NSError(domain: "BleepKitTests", code: NSUserCancelledError)
        )

        #expect(!result.isUserCancellation)
    }
}
