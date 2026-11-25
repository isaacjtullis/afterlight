import XCTest
@testable import AfterlightCore

final class IntroTests: XCTestCase {
    func run(_ p: inout IntroPlayer, _ seconds: Double) {
        var t = 0.0
        while t < seconds { p.tick(1.0 / 30); t += 1.0 / 30 }
    }

    func testTwelveScenesInOrderWithTheirLines() {
        let s = IntroScript.scenes
        XCTAssertEqual(s.map(\.image), ["01-valley", "02-rumor", "03-shifts", "04-shelves", "05-road", "06-rich",
                                         "07-families", "08-strikes", "09-collapse", "10-radio", "11-generations", "12-max"])
        XCTAssertEqual(s[0].text, "In 3100 AD…")
        XCTAssertTrue(s[2].text.hasPrefix("If you caught it, you died."))
        XCTAssertTrue(s[5].text.contains("The rich"))
        XCTAssertTrue(s[11].text.contains("shovel"))
        XCTAssertTrue(s.allSatisfy { !$0.text.isEmpty })
    }

    func testTimingFollowsReadingLength() {
        let short = IntroScript.duration(IntroScript.scenes[0])
        let long = IntroScript.duration(IntroScript.scenes[2])
        XCTAssertLessThan(short, 3)
        XCTAssertGreaterThan(long, 7)
    }

    func testAutoAdvanceThroughEverySceneThenHoldOnMax() {
        var p = IntroPlayer()
        var seen = [p.index]
        for _ in 0..<5000 {
            p.tick(1.0 / 30)
            if seen.last != p.index { seen.append(p.index) }
        }
        XCTAssertEqual(seen, Array(0..<12), "every scene shows once, in order")
        XCTAssertTrue(p.waitingForCandle)
        XCTAssertEqual(p.index, 11)
        run(&p, 60)
        XCTAssertEqual(p.index, 11, "the last image holds until the player acts")
    }

    func testTapRightAdvancesAndTapLeftGoesBack() {
        var p = IntroPlayer()
        p.next(); p.next()
        XCTAssertEqual(p.index, 2)
        run(&p, 0.2)
        p.back()
        XCTAssertEqual(p.index, 1, "a tap at the very start of a scene goes to the previous one")
        run(&p, 3)
        p.back()
        XCTAssertEqual(p.index, 1, "later in a scene, a left tap restarts it")
        XCTAssertEqual(p.progress, 0)
    }

    func testHoldPausesAndReleaseResumesOnTheSameScene() {
        var p = IntroPlayer()
        p.next()
        run(&p, 1)
        let before = p.progress
        p.held = true
        run(&p, 30)
        XCTAssertEqual(p.index, 1)
        XCTAssertEqual(p.progress, before)
        p.held = false
        run(&p, 0.5)
        XCTAssertEqual(p.index, 1)
        XCTAssertGreaterThan(p.progress, before)
    }

    func testBackgroundAndPauseControlStopTheTimer() {
        var p = IntroPlayer()
        p.next()
        p.backgrounded = true
        run(&p, 30)
        XCTAssertEqual(p.index, 1); XCTAssertEqual(p.progress, 0)
        p.backgrounded = false
        p.paused = true
        run(&p, 30)
        XCTAssertEqual(p.progress, 0)
        p.paused = false
        run(&p, 1)
        XCTAssertGreaterThan(p.progress, 0)
    }

    func testSkipGoesStraightToTheCandle() {
        var p = IntroPlayer()
        p.next()
        p.skip()
        XCTAssertEqual(p.index, 11)
        XCTAssertTrue(p.waitingForCandle)
    }

    func testLightingTheCandleStartsTheGameInTheWorkshop() {
        let g = Game()
        XCTAssertFalse(g.started)
        g.begin()
        sim(g, GameInput(), 1)
        XCTAssertTrue(g.started)
        XCTAssertEqual(g.max.pos.y, 30, accuracy: 0.1)
        XCTAssertTrue(g.atHome, "control hands to Max in the workshop")
    }
}
