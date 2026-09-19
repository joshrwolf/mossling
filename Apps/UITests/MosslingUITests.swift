import XCTest

/// These tests drive the shipped forms and verify changes after a new process
/// reads the on-disk document. No test-only model setters or seeded UI state.
@MainActor
final class MosslingUITests: XCTestCase {
    func testExploreFirstDoesNotRequestNotificationPermission() {
        let app = launchFresh()
        capture("Welcome", app: app)
        exploreFirst(in: app)
        capture("Forest", app: app)

        app.tabBars.buttons["Rhythm"].tap()
        // LabeledContent exposes the label and current value as one AX element.
        XCTAssertTrue(app.staticTexts["Notifications, Not requested"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists,
                       "Exploring first must not show a system notification permission prompt")
        capture("Rhythm without notification permission", app: app)

        relaunch(app)
        XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Explore first"].exists, "Welcome dismissal must survive relaunch")
    }

    func testCreatedAndEditedSnackPersistsAcrossRelaunch() {
        let app = launchFresh()
        exploreFirst(in: app)
        app.tabBars.buttons["Snacks"].tap()
        reveal(app.buttons["createActivity"], in: app)
        app.buttons["createActivity"].tap()

        let title = app.textFields["activityTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Kitchen wiggle")
        let instructions = app.descendants(matching: .any).matching(identifier: "activityInstructions").firstMatch
        instructions.tap()
        instructions.typeText("Move gently to a favorite song.")
        app.buttons["saveActivity"].tap()

        let original = app.buttons["Edit Kitchen wiggle, 2 min"]
        reveal(original, in: app)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        capture("Custom snack in rotation", app: app)

        relaunch(app)
        app.tabBars.buttons["Snacks"].tap()
        reveal(original, in: app)
        original.tap()
        XCTAssertEqual(app.textFields["activityTitle"].value as? String, "Kitchen wiggle")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "activityInstructions").firstMatch.value as? String,
                       "Move gently to a favorite song.")
        app.buttons["30 sec"].tap()
        capture("Editing a custom snack", app: app)
        app.buttons["saveActivity"].tap()
        let edited = app.buttons["Edit Kitchen wiggle, 30 sec"]
        reveal(edited, in: app)
        XCTAssertTrue(edited.waitForExistence(timeout: 5))

        relaunch(app)
        app.tabBars.buttons["Snacks"].tap()
        reveal(edited, in: app)
        XCTAssertTrue(edited.exists, "The edited target must survive a new app process")
        XCTAssertFalse(original.exists, "Editing must update the existing snack instead of duplicating it")
        capture("Persisted custom snack", app: app)
    }

    func testScheduleChangesPersistAcrossRelaunch() {
        let app = launchFresh()
        exploreFirst(in: app)
        app.tabBars.buttons["Rhythm"].tap()
        app.buttons["editSchedule"].tap()

        let monday = app.switches["scheduleDay2"]
        XCTAssertTrue(monday.waitForExistence(timeout: 5))
        XCTAssertEqual(monday.value as? String, "1")
        // SwiftUI exposes the entire Toggle row as the switch's AX frame.
        // Tap its trailing control; the center is the noninteractive row gap.
        monday.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let mondayTurnedOff = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "0"), object: monday
        )
        XCTAssertEqual(XCTWaiter.wait(for: [mondayTurnedOff], timeout: 5), .completed,
                       "Tapping Monday's switch must deselect the day before saving")
        let interval = app.buttons["scheduleInterval"]
        reveal(interval, in: app)
        interval.tap()
        app.buttons["90 minutes"].tap()
        XCTAssertEqual(monday.value as? String, "0", "Changing the interval must preserve selected days")
        capture("Schedule editor", app: app)
        app.buttons["saveSchedule"].tap()
        XCTAssertTrue(app.staticTexts["Every 90 minutes"].waitForExistence(timeout: 5))

        relaunch(app)
        app.tabBars.buttons["Rhythm"].tap()
        XCTAssertTrue(app.staticTexts["Every 90 minutes"].waitForExistence(timeout: 5))
        app.buttons["editSchedule"].tap()
        XCTAssertTrue(monday.waitForExistence(timeout: 5))
        XCTAssertEqual(monday.value as? String, "0", "The saved active days must survive relaunch")
        capture("Persisted schedule", app: app)
    }

    private func launchFresh() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments + ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["Explore first"].waitForExistence(timeout: 15))
        return app
    }

    private var arguments: [String] {
        ["--ui-testing", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 15))
    }

    private func exploreFirst(in app: XCUIApplication) {
        let button = app.buttons["Explore first"]
        reveal(button, in: app)
        button.tap()
        XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable,
                      "Could not reveal \(element)", file: file, line: line)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
