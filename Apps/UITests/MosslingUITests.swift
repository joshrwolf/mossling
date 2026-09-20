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
        XCTAssertTrue(app.buttons["saveActivity"].waitForNonExistence(timeout: 10),
                      "A durable save must dismiss the editor without waiting for reminder delivery")

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
        XCTAssertTrue(app.buttons["saveActivity"].waitForNonExistence(timeout: 10),
                      "A durable save must dismiss the editor without waiting for reminder delivery")
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

    func testCompletedSnackEarnsGrowthOnceAndSurvivesRelaunch() {
        let app = launchFresh()
        exploreFirst(in: app)
        completeRepetitionSnack(in: app)

        assertGrowth(10, in: app)
        capture("Completed break and earned growth", app: app)

        relaunch(app)
        // This identifier belongs to Text. Keep the query typed and resolve it
        // against the new process rather than searching every element kind.
        XCTAssertTrue(app.staticTexts["completedSnackState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startSnack"].exists,
                       "A completed opportunity must not offer another rewarded snack")
        XCTAssertFalse(app.buttons["resumeSnack"].exists,
                       "The saved session must not reopen after completion")
        assertGrowth(10, in: app)

        app.tabBars.buttons["Journal"].tap()
        XCTAssertTrue(app.staticTexts["1 little moments"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Wall push-ups")).count, 1,
                       "One completion must create exactly one journal moment")
        capture("One persisted movement moment", app: app)
    }

    func testSkippedBreakPersistsWithoutSkippingTheNextBreak() {
        let app = launchFresh()
        exploreFirst(in: app)
        let skip = app.buttons["skipSnack"]
        reveal(skip, in: app)
        skip.tap()

        XCTAssertTrue(app.staticTexts["skippedSnackState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startSnack"].exists)
        assertGrowth(0, in: app)

        relaunch(app)
        XCTAssertTrue(app.staticTexts["skippedSnackState"].waitForExistence(timeout: 5),
                      "Skipping must survive a new process in the same opportunity")
        XCTAssertFalse(app.buttons["startSnack"].exists)
        capture("Skipped break after relaunch", app: app)

        // Advance only the clock. The next opportunity comes from the normal
        // schedule and the saved skip must still apply only to the earlier one.
        relaunch(app, now: activeWeekday + 60 * 60)
        let nextSnack = app.buttons["startSnack"]
        reveal(nextSnack, in: app)
        XCTAssertTrue(nextSnack.isEnabled)
        XCTAssertFalse(app.staticTexts["skippedSnackState"].exists)
        assertGrowth(0, in: app)
    }

    func testPauseTodayPersistsAndCanBeResumed() {
        let app = launchFresh()
        exploreFirst(in: app)
        let pause = app.buttons["pauseToday"]
        reveal(pause, in: app)
        pause.tap()

        let pausedState = element("pausedDayState", in: app)
        XCTAssertTrue(pausedState.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startSnack"].exists)

        relaunch(app)
        XCTAssertTrue(pausedState.waitForExistence(timeout: 5),
                      "Pausing today must survive process termination")
        let resume = app.buttons["resumeToday"]
        reveal(resume, in: app)
        capture("Paused day after relaunch", app: app)
        resume.tap()

        let currentSnack = app.buttons["startSnack"]
        XCTAssertTrue(currentSnack.waitForExistence(timeout: 5))
        reveal(currentSnack, in: app)
        XCTAssertTrue(currentSnack.isEnabled)
        XCTAssertFalse(pausedState.exists)
        assertGrowth(0, in: app)

        relaunch(app)
        XCTAssertTrue(currentSnack.waitForExistence(timeout: 5),
                      "Resuming must persist, rather than reapplying the day pause on launch")
        XCTAssertFalse(pausedState.exists)
    }

    func testEarnedAffinityChoicePersistsAndCanBeChanged() {
        let app = launchFresh()
        exploreFirst(in: app)
        let moonlit = app.buttons["affinityMoonlit"]
        let sunlit = app.buttons["affinitySunlit"]
        XCTAssertFalse(moonlit.exists, "Affinity choice must be earned through movement")
        XCTAssertFalse(sunlit.exists)

        for snack in 0..<3 {
            if snack > 0 {
                relaunch(app, now: activeWeekday + TimeInterval(snack * 60 * 60))
            }
            completeRepetitionSnack(in: app)
            if snack < 2 {
                XCTAssertFalse(moonlit.exists, "Affinity choice must stay locked before the third snack")
                XCTAssertFalse(sunlit.exists)
            }
        }

        assertGrowth(30, in: app)
        reveal(moonlit, in: app)
        moonlit.tap()
        assertSelectedAffinity(moonlit)
        capture("Earned Moonlit affinity", app: app)

        let thirdSnackTime = activeWeekday + 2 * 60 * 60
        relaunch(app, now: thirdSnackTime)
        assertGrowth(30, in: app)
        reveal(moonlit, in: app)
        assertSelectedAffinity(moonlit)
        XCTAssertEqual(sunlit.value as? String, "Not selected")
        reveal(sunlit, in: app)
        sunlit.tap()
        assertSelectedAffinity(sunlit)
        XCTAssertEqual(moonlit.value as? String, "Not selected")

        relaunch(app, now: thirdSnackTime)
        assertGrowth(30, in: app)
        reveal(sunlit, in: app)
        assertSelectedAffinity(sunlit)
        XCTAssertEqual(moonlit.value as? String, "Not selected")
        capture("Persisted Sunlit affinity", app: app)
    }

    private func launchFresh() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(now: activeWeekday) + ["--ui-testing-reset"]
        app.launch()
        XCTAssertTrue(app.buttons["Explore first"].waitForExistence(timeout: 15))
        return app
    }

    /// Monday, September 21, 2026 at 10:05 UTC, inside the real default rhythm.
    /// Clock injection avoids waiting an hour or relying on the CI runner's date.
    private let activeWeekday: TimeInterval = 1_789_985_100

    private func arguments(now: TimeInterval) -> [String] {
        ["--ui-testing", "--ui-testing-now", String(now),
         "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    private func relaunch(_ app: XCUIApplication, now: TimeInterval? = nil) {
        app.terminate()
        app.launchArguments = arguments(now: now ?? activeWeekday)
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 15))
    }

    private func exploreFirst(in app: XCUIApplication) {
        let button = app.buttons["Explore first"]
        reveal(button, in: app)
        button.tap()
        XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func completeRepetitionSnack(in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let chooseAnother = app.buttons["Choose another"]
        reveal(chooseAnother, in: app, file: file, line: line)
        chooseAnother.tap()
        app.buttons["Wall push-ups · 8 reps"].tap()
        let complete = app.buttons["completeSnack"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5), file: file, line: line)
        reveal(complete, in: app, file: file, line: line)
        XCTAssertTrue(complete.isEnabled, file: file, line: line)
        complete.tap()
        XCTAssertTrue(app.staticTexts["completedSnackState"].waitForExistence(timeout: 10),
                      file: file, line: line)
        XCTAssertFalse(complete.exists, "Completion must dismiss the movement session", file: file, line: line)
    }

    private func assertGrowth(_ expected: Int, in app: XCUIApplication,
                              file: StaticString = #filePath, line: UInt = #line) {
        let growth = app.staticTexts["earnedGrowthValue"]
        reveal(growth, in: app, file: file, line: line)
        XCTAssertEqual(growth.label, "\(expected) growth", file: file, line: line)
    }

    private func assertSelectedAffinity(_ button: XCUIElement,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Selected"), object: button
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "The saved affinity must be selected", file: file, line: line)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        // A full swipe can skip a short label, and reopening a screen can leave
        // its scroll position below the target. Use small drags in either
        // direction, checking the current accessibility frame after each one.
        for attempt in 0..<20 {
            if element.exists && element.isHittable { return }
            let target = element.exists ? element.frame : .zero
            let hasPosition = !target.isEmpty && !target.isNull && !target.isInfinite
            let scrollTowardEarlierContent = hasPosition
                ? target.midY < app.frame.midY
                : attempt >= 7
            // When an offscreen element has no frame, search forward first,
            // then back across the initial position. All scrolling is bounded.
            let startY: CGFloat = scrollTowardEarlierContent ? 0.38 : 0.62
            let endY: CGFloat = scrollTowardEarlierContent ? 0.62 : 0.38
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
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
