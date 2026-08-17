//
//  bleepkitUITests.swift
//  BleepKitUITests
//

import XCTest

/// Smoke tests: the app launches and its core screens expose their
/// controls with accessible labels.
final class bleepkitUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The import screen shows both import paths and the navigation title.
    @MainActor
    func testImportScreenShowsCoreControls() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.navigationBars["BleepKit"].waitForExistence(timeout: 10),
            "Root navigation bar missing"
        )
        XCTAssertTrue(
            app.buttons["Choose from Photos"].exists,
            "Photos import button missing"
        )
        XCTAssertTrue(
            app.buttons["Import from Files"].exists,
            "Files import button missing"
        )
    }

    /// Opening an existing project reaches the editor with its transport
    /// controls; skipped on a fresh install with no projects.
    @MainActor
    func testEditorOpensForExistingProject() throws {
        let app = XCUIApplication()
        app.launch()

        let firstProject = app.cells.firstMatch
        try XCTSkipUnless(
            firstProject.waitForExistence(timeout: 5),
            "No saved projects on this device; import one to exercise the editor"
        )
        firstProject.tap()

        XCTAssertTrue(
            app.buttons["Export censored video"].waitForExistence(timeout: 15),
            "Export button missing from the editor"
        )
        XCTAssertTrue(
            app.buttons["Play"].exists || app.buttons["Pause"].exists,
            "Transport play/pause control missing"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
