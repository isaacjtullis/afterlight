import XCTest

/// Plays the opening with real touches on the simulator: the buttons a thumb presses, not code shortcuts.
final class PlayByTouchTests: XCTestCase {
    let shotDir = "/tmp/afterlight-shots"
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    func shot(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
        try? png.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    var state: String { app.staticTexts["debug.state"].label }
    func value(_ key: String) -> Double {
        for part in state.split(separator: " ") where part.hasPrefix(key + "=") { return Double(part.dropFirst(key.count + 1)) ?? .nan }
        return .nan
    }
    func waitFor(_ text: String, timeout: Double = 10) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if state.contains(text) { return true }; usleep(200_000) }
        return false
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate { app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)) }

    func testOpeningStoryByThumbThenWalkAndDig() {
        let begin = app.buttons["Begin"]
        XCTAssertTrue(begin.waitForExistence(timeout: 15), "title screen shows Begin")
        shot("01-title")
        begin.tap()
        sleep(2)
        shot("02-story-first")
        let firstCaption = app.staticTexts["intro.caption"].label
        point(0.85, 0.5).tap()
        sleep(1)
        XCTAssertNotEqual(app.staticTexts["intro.caption"].label, firstCaption, "tapping the right side advances the story")
        shot("03-story-next")
        point(0.1, 0.5).tap()
        sleep(1)

        // Swipe down with a thumb closes the story and starts the game.
        point(0.5, 0.35).press(forDuration: 0.05, thenDragTo: point(0.5, 0.9))
        XCTAssertTrue(waitFor("started=true", timeout: 8), "closing the story starts the game; state: \(state)")
        sleep(3)
        shot("04-workshop")

        let right = app.buttons["move.right"], left = app.buttons["move.left"], dig = app.buttons["dig"]
        XCTAssertTrue(right.waitForExistence(timeout: 5), "walk buttons are on screen")
        let x0 = value("x")
        right.press(forDuration: 1.5)
        usleep(500_000)
        let x1 = value("x")
        XCTAssertGreaterThan(x1, x0 + 1, "holding ▶ walks Max right (\(x0) → \(x1))")
        shot("05-walked-right")
        left.press(forDuration: 0.8)
        usleep(500_000)
        XCTAssertLessThan(value("x"), x1, "holding ◀ walks Max left")

        // To the dirt wall, then hold DIG.
        right.press(forDuration: 4)
        shot("06-at-the-wall")
        dig.press(forDuration: 5)
        usleep(500_000)
        XCTAssertTrue(state.contains("dug=true"), "holding DIG cuts into the wall; state: \(state)")
        shot("07-digging")
    }

    func testStoryPlaysToTheCandle() {
        app.buttons["Begin"].tap()
        for _ in 0..<12 { point(0.85, 0.5).tap(); usleep(400_000) }
        let candle = app.buttons["intro.candle"]
        XCTAssertTrue(candle.waitForExistence(timeout: 5), "the last scene waits on Light the candle")
        shot("08-candle")
        candle.tap()
        XCTAssertTrue(waitFor("started=true"), "lighting the candle hands control to Max")
    }
}
