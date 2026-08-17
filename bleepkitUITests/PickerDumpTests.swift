//
//  PickerDumpTests.swift
//  BleepKitUITests
//
//  Temporary diagnostic: dumps the Photos picker hierarchy to find a
//  reliable element handle for selecting the seeded video.
//

import XCTest

final class PickerDumpTests: XCTestCase {

    @MainActor
    func testDumpPickerHierarchy() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["Choose from Photos"].firstMatch.tap()
        sleep(6)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = "hierarchy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
