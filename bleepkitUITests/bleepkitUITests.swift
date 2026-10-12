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
        XCTAssertEqual(app.buttons["Choose from Photos"].count, 1, "Photos import should have one clear entry point")
        XCTAssertEqual(app.buttons["Import from Files"].count, 1, "Files import should have one entry point")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "refined-first-import"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testHelpAndTrashRemainReachable() throws {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["Help & Trash"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let help = app.descendants(matching: .any)["Help & FAQ"].firstMatch
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.navigationBars["FAQ"].waitForExistence(timeout: 5))

        app.navigationBars["FAQ"].buttons.firstMatch.tap()
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        let trash = app.descendants(matching: .any)["Trash"].firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.tap()
        XCTAssertTrue(app.navigationBars["Trash"].waitForExistence(timeout: 5))
    }

    /// Opening an existing project reaches the editor with its transport
    /// controls; skipped on a fresh install with no projects.
    @MainActor
    func testEditorOpensForExistingProject() throws {
        let app = XCUIApplication()
        app.launch()

        let firstProject = app.buttons["projectCard"].firstMatch
        try XCTSkipUnless(
            firstProject.waitForExistence(timeout: 5),
            "No saved projects on this device; import one to exercise the editor"
        )
        firstProject.tap()

        XCTAssertTrue(
            app.buttons["Export censored video"].waitForExistence(timeout: 90),
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
