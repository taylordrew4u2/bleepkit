//
//  ImportFlowSmokeTests.swift
//  BleepKitUITests
//
//  End-to-end smoke test for the import flow: pick a video from the photo
//  library, land on the Imported screen, open the project, and require the
//  editor to reach a terminal state — preview ready or an explanatory
//  failure. A hang in the working state is the audit's #1 blocker
//  (an editor that spins forever) and fails this test.
//
//  Setup: the simulator's photo library must contain at least one video —
//  seed one from the host with:
//      xcrun simctl addmedia <udid> <clip.mov>
//  The test skips (not fails) when the library appears empty.
//

import XCTest

final class ImportFlowSmokeTests: XCTestCase {

    @MainActor
    func testImportReachesEditorTerminalState() throws {
        let app = XCUIApplication()
        app.launch()

        addUIInterruptionMonitor(withDescription: "permission alerts") { alert in
            for label in ["Allow", "OK", "Allow Access to All Photos", "Allow Full Access"] {
                if alert.buttons[label].exists {
                    alert.buttons[label].tap()
                    return true
                }
            }
            return false
        }

        // Open the Photos picker. Its remote hierarchy is opaque to element
        // queries (images.firstMatch matches the access banner's icon, not
        // the media grid), so tap the first grid cell by coordinate:
        // top-left cell below the "Private Access to Photos" banner.
        app.buttons["Choose from Photos"].firstMatch.tap()
        sleep(5) // let the remote picker settle
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.43)).tap()

        // The picker dismisses itself on selection. If it's still up after
        // the tap, the library has no video in that cell — a setup problem,
        // not an app regression.
        let done = app.buttons["Done"]
        if !done.waitForExistence(timeout: 60) {
            if app.staticTexts["Private Access to Photos"].exists
                || app.buttons["Close"].exists {
                throw XCTSkip("Photo library appears empty — seed a video with `xcrun simctl addmedia` before running.")
            }
            XCTFail("Import never reached the Imported screen.")
            return
        }

        // Imported details are present.
        XCTAssertTrue(app.staticTexts["Duration"].exists, "Imported screen is missing its metadata")
        done.tap()

        // The imported project appears in the list; open it.
        let row = app.cells.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No project row after import")
        row.tap()

        // Transcription auto-starts and may prompt for speech recognition.
        dismissSpringboardAlertIfPresent()
        app.tap() // nudge the interruption monitor if an alert is pending
        dismissSpringboardAlertIfPresent()

        // The editor must reach a terminal state: either the preview is
        // ready (Play enabled) or a failure explains itself with an action.
        // Anything else after the deadline is the infinite-spinner regression.
        let deadline = Date().addingTimeInterval(120)
        var reachedTerminalState = false
        while Date() < deadline {
            dismissSpringboardAlertIfPresent()
            let playButton = app.buttons["Play"]
            let previewReady = playButton.exists && playButton.isEnabled
            let failureExplained = app.buttons["Try Again"].exists
                || app.buttons["Transcribe"].exists
                || app.buttons["Open Settings"].exists
            if previewReady || failureExplained {
                reachedTerminalState = true
                break
            }
            sleep(3)
        }
        XCTAssertTrue(
            reachedTerminalState,
            "Editor never reached a terminal state — transcription stalled with no explanation or retry (audit finding 2.1)."
        )
    }

    @MainActor
    private func dismissSpringboardAlertIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow", "OK"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                return
            }
        }
    }
}
