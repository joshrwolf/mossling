import XCTest
import CoreGraphics
import MosslingCore

/// UI coverage owns control wiring, presentation, onboarding and one real process
/// restart. Store integration tests own workflow permutations and file persistence.
@MainActor
final class MosslingUITests: XCTestCase {
    func testExploreFirstDoesNotRequestNotificationPermission() {
        let app = launchFresh(skipWelcome: false)
        capture("Welcome", app: app)
        exploreFirst(in: app)
        capture("Forest", app: app)

        app.tabBars.buttons["Rhythm"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(springboard.alerts.firstMatch.exists,
                       "Exploring first must not show a system notification permission prompt")
        // A fresh hosted simulator can display the form while the system's
        // initial notification-settings query is still pending. Wait for that
        // real response, then require the exact unchanged authorization state.
        // This is a maximum readiness budget, not a sleep or a test retry.
        XCTAssertTrue(app.staticTexts["Notifications, Checking…"].waitForNonExistence(timeout: 180),
                      "The system notification settings query must finish")
        // LabeledContent exposes the label and current value as one AX element.
        XCTAssertTrue(app.staticTexts["Notifications, Not requested"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertFalse(springboard.alerts.firstMatch.exists,
                       "Exploring first must not show a system notification permission prompt")
        capture("Rhythm without notification permission", app: app)

        relaunch(app)
        XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Explore first"].exists, "Welcome dismissal must survive relaunch")
    }

    func testActivityEditorCreatesAndUpdatesSnack() {
        let app = launchFresh()
        app.tabBars.buttons["Snacks"].tap()
        reveal(app.buttons["createActivity"], in: app)
        app.buttons["createActivity"].tap()

        let title = app.textFields["activityTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Kitchen wiggle")
        let instructions = app.textFields["activityInstructions"]
        instructions.tap()
        instructions.typeText("Move gently to a favorite song.")
        app.buttons["saveActivity"].tap()
        XCTAssertTrue(app.buttons["saveActivity"].waitForNonExistence(timeout: 10),
                      "A durable save must dismiss the editor without waiting for reminder delivery")

        let original = app.buttons["Edit Kitchen wiggle, 2 min"]
        reveal(original, in: app)
        XCTAssertTrue(original.waitForExistence(timeout: 5))
        capture("Custom snack in rotation", app: app)

        original.tap()
        XCTAssertEqual(app.textFields["activityTitle"].value as? String, "Kitchen wiggle")
        XCTAssertEqual(app.textFields["activityInstructions"].value as? String,
                       "Move gently to a favorite song.")
        app.buttons["30 sec"].tap()
        capture("Editing a custom snack", app: app)
        app.buttons["saveActivity"].tap()
        XCTAssertTrue(app.buttons["saveActivity"].waitForNonExistence(timeout: 10),
                      "A durable save must dismiss the editor without waiting for reminder delivery")
        let edited = app.buttons["Edit Kitchen wiggle, 30 sec"]
        reveal(edited, in: app)
        XCTAssertTrue(edited.waitForExistence(timeout: 5), "The saved editor must display the changed target")
        XCTAssertFalse(original.exists, "Editing must update the existing snack instead of duplicating it")
        capture("Edited custom snack", app: app)
    }

    func testScheduleEditorUpdatesDaysAndInterval() {
        let app = launchFresh()
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
        app.buttons["editSchedule"].tap()
        XCTAssertTrue(monday.waitForExistence(timeout: 5))
        XCTAssertEqual(monday.value as? String, "0", "Reopening the editor must show the saved active days")
        capture("Saved schedule", app: app)
    }

    func testCompletedSnackEarnsGrowthOnceAndSurvivesRelaunch() {
        let app = launchFresh()
        app.buttons["forestDetails"].tap()
        XCTAssertFalse(app.buttons["affinityMoonlit"].exists)
        XCTAssertFalse(app.buttons["affinitySunlit"].exists)
        app.buttons["Done"].tap()
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
        XCTAssertTrue(app.staticTexts["1 snack completed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "Wall push-ups")).count, 1,
                       "One completion must create exactly one journal moment")
        capture("One persisted movement moment", app: app)
    }

    func testSkipButtonShowsSkippedStateWithoutGrowth() {
        let app = launchFresh()
        app.buttons["Snack options"].tap()
        let skip = app.buttons["skipSnack"]
        reveal(skip, in: app)
        skip.tap()

        XCTAssertTrue(app.staticTexts["skippedSnackState"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startSnack"].exists)
        assertGrowth(0, in: app)
    }

    func testPauseAndResumeButtonsUpdateAvailability() {
        let app = launchFresh()
        app.buttons["Snack options"].tap()
        let pause = app.buttons["pauseToday"]
        reveal(pause, in: app)
        pause.tap()

        let pausedState = element("pausedDayState", in: app)
        XCTAssertTrue(pausedState.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startSnack"].exists)

        let resume = app.buttons["resumeToday"]
        reveal(resume, in: app)
        capture("Paused day", app: app)
        resume.tap()

        let currentSnack = app.buttons["startSnack"]
        XCTAssertTrue(currentSnack.waitForExistence(timeout: 5))
        reveal(currentSnack, in: app)
        XCTAssertTrue(currentSnack.isEnabled)
        XCTAssertFalse(pausedState.exists)
        assertGrowth(0, in: app)
    }

    func testEarnedAffinityCanBeSelectedAndChanged() throws {
        // Start from a validated earned document. Thresholds and durable choices
        // are covered through the real Store without repeating three UI breaks.
        let app = launchFresh(document: try earnedAffinityDocument())
        app.buttons["forestDetails"].tap()
        let moonlit = app.buttons["affinityMoonlit"]
        let sunlit = app.buttons["affinitySunlit"]
        assertGrowth(30, in: app, details: true)
        reveal(moonlit, in: app)
        moonlit.tap()
        assertSelectedAffinity(moonlit)
        XCTAssertEqual(sunlit.value as? String, "Not selected")
        reveal(sunlit, in: app)
        sunlit.tap()
        assertSelectedAffinity(sunlit)
        XCTAssertEqual(moonlit.value as? String, "Not selected")
        assertGrowth(30, in: app, details: true)
        capture("Changed earned affinity", app: app)
    }

    func testThirdSnackEvolvesForestAndSurvivesRelaunch() throws {
        let app = launchFresh(document: try earnedAffinityDocument(snacks: 2))
        XCTAssertTrue(app.staticTexts["companionStage"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["companionStage"].label, "Seedling")
        completeRepetitionSnack(in: app)
        assertGrowth(30, in: app)
        XCTAssertEqual(app.staticTexts["companionStage"].label, "Sprout")
        let forest = app.buttons["forestScene"]
        XCTAssertTrue(forest.waitForExistence(timeout: 5))
        XCTAssertEqual(forest.value as? String, "Sprout; Home clearing; Stump home")
        assertForestRendered(forest)
        if app.buttons["skipForestAnimation"].exists { app.buttons["skipForestAnimation"].tap() }
        forest.tap()
        forest.tap()
        forest.tap()
        capture("Evolved forest after creature interactions", app: app)
        assertGrowth(30, in: app)

        relaunch(app)
        XCTAssertEqual(app.staticTexts["companionStage"].label, "Sprout")
        XCTAssertEqual(app.buttons["forestScene"].value as? String, "Sprout; Home clearing; Stump home")
        XCTAssertFalse(app.buttons["skipForestAnimation"].exists, "Opening saved progress must not replay evolution")
        assertGrowth(30, in: app)
    }

    func testForestSupportsLargeTextAndReducedMotion() throws {
        let app = launchFresh(document: try earnedAffinityDocument(snacks: 2),
                              options: ["--ui-testing-reduce-motion", "--ui-testing-accessibility-size"])
        let forest = app.staticTexts["forestScene"]
        XCTAssertTrue(forest.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["forestScene"].exists, "A still scene must not advertise an unavailable action")
        XCTAssertEqual(forest.value as? String, "Seedling; Home clearing; Stump home")
        assertForestRendered(forest)
        completeRepetitionSnack(in: app)
        assertGrowth(30, in: app)
        XCTAssertEqual(forest.value as? String, "Sprout; Home clearing; Stump home")
        assertForestRendered(forest)
        XCTAssertFalse(app.buttons["skipForestAnimation"].exists)
        capture("Forest with large text and reduced motion", app: app)
    }

    func testHabitatPlacementMovementAndExpansionSurviveRelaunch() throws {
        let app = launchFresh(document: try earnedAffinityDocument())
        app.buttons["buildForest"].tap()
        app.buttons["habitatKind"].tap()
        app.buttons["Little fern"].tap()
        let save = app.buttons["saveHabitat"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertEqual(app.staticTexts["habitatSaveStatus"].label, "Saved Little fern at column 5, row 4.")
        let row = app.buttons["habitatRow"]
        reveal(row, in: app)
        row.tap()
        app.buttons["Row 5"].tap()
        reveal(save, in: app)
        save.tap()
        XCTAssertEqual(app.staticTexts["habitatSaveStatus"].label, "Saved Little fern at column 5, row 5.")
        let expand = app.buttons["expandGrove"]
        reveal(expand, in: app)
        XCTAssertTrue(expand.isEnabled)
        expand.tap()
        XCTAssertTrue(app.staticTexts["groveOpen"].waitForExistence(timeout: 5))
        capture("Expanded habitat with moved fern", app: app)
        app.buttons["Done"].tap()
        assertGrowth(30, in: app)
        relaunch(app)
        app.buttons["buildForest"].tap()
        let fern = app.staticTexts["placement_fern"]
        reveal(fern, in: app)
        XCTAssertEqual(fern.label, "Little fern: Column 5, row 5")
        XCTAssertTrue(app.staticTexts["groveOpen"].exists)
        capture("Saved habitat after relaunch", app: app)
    }

    private func earnedAffinityDocument(snacks: Int = 3) throws -> AppDocument {
        var document = AppDocument()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let activity = try XCTUnwrap(document.configuration.activities.first { $0.id == "wall-push" })
        for hour in 0..<snacks {
            let date = Date(timeIntervalSince1970: activeWeekday - 3 * 24 * 3600 + Double(hour) * 3600)
            let opportunity = try XCTUnwrap(try ScheduleEngine(configuration: document.configuration)
                .current(at: date, calendar: calendar))
            let session = try SnackSession.start(opportunity: opportunity, activity: activity, at: date)
            document.session = session
            try DocumentSync.complete(session, at: date, in: &document)
        }
        try document.validate()
        return document
    }

    private func launchFresh(skipWelcome: Bool = true, document: AppDocument? = nil, options: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = arguments(now: activeWeekday) + ["--ui-testing-reset"] + options
        if skipWelcome { app.launchArguments.append("--ui-testing-skip-welcome") }
        if let document {
            do { app.launchEnvironment["MOSSLING_UI_TEST_DOCUMENT"] = try document.encoded().base64EncodedString() }
            catch { XCTFail("Invalid UI fixture: \(error)") }
        }
        app.launch()
        if skipWelcome {
            XCTAssertTrue(app.tabBars.buttons["Forest"].waitForExistence(timeout: 15))
        } else {
            XCTAssertTrue(app.buttons["Explore first"].waitForExistence(timeout: 15))
        }
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
        app.launchEnvironment.removeValue(forKey: "MOSSLING_UI_TEST_DOCUMENT")
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

    private func assertGrowth(_ expected: Int, in app: XCUIApplication, details: Bool = false,
                              file: StaticString = #filePath, line: UInt = #line) {
        let growth = details ? app.staticTexts["earnedGrowthValue"] : app.buttons["forestDetails"]
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

    private func assertForestRendered(_ forest: XCUIElement,
                                      file: StaticString = #filePath, line: UInt = #line) {
        guard let capture = forest.screenshot().image.cgImage,
              let image = capture.cropping(to: CGRect(x: 0, y: Double(capture.height) * 0.45,
                                                     width: Double(capture.width), height: Double(capture.height) * 0.55)) else {
            XCTFail("The forest must produce a rendered image", file: file, line: line)
            return
        }
        var pixels = [UInt8](repeating: 0, count: 16 * 16 * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: 16, height: 16,
                                          bitsPerComponent: 8, bytesPerRow: 64,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
            return true
        }
        XCTAssertTrue(rendered, file: file, line: line)
        let colors = Set(stride(from: 0, to: pixels.count, by: 4).map {
            Int(pixels[$0] >> 4) << 8 | Int(pixels[$0 + 1] >> 4) << 4 | Int(pixels[$0 + 2] >> 4)
        })
        XCTAssertGreaterThan(colors.count, 16, "The forest must render its artwork, not a blank surface",
                             file: file, line: line)
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
            let controls = app.collectionViews["habitatControls"]
            let scrollSurface = controls.exists ? controls : app
            let start = scrollSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: startY))
            let end = scrollSurface.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: endY))
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
