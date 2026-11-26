import XCTest
@testable import AfterlightCore

/// The whole campaign from a fresh save: candle to the surface door, with the wheel, DIG, JUMP,
/// the context button and conversation choices. Lifts, stairs and doors are ridden, never skipped.
final class CampaignPlaythroughTests: XCTestCase {

    func testCandleToTheEnding() {
        let clock = FixedClock()
        let g = Game()
        g.clock = { clock.now }
        let b = Bot(g)

        // Builds 1 and the old chapters: water, light, the ascent to maintenance.
        b.playToMaintenance(self)
        XCTAssertEqual(g.story.chapter, 3, b.trail)

        // The warm passage east to Outpost 9.
        b.hold(GameInput(dx: 1), until: { g.max.pos.x > 34.3 }, timeout: 10, "into the passage")
        b.hold(GameInput(dx: 1, dig: true), until: { g.max.pos.x > 74 }, timeout: 900, "dig the warm passage")
        XCTAssertGreaterThan(g.max.pos.x, 74, b.trail)

        // Mara: help with the water, for the lift.
        b.hold(GameInput(dx: 1), until: { g.nearMara }, timeout: 10, "walk up to Mara")
        XCTAssertTrue(b.use("panel:mara"), b.trail)
        for c in ["alive", "tap", "help", "agree", "ok"] { g.chooseTalk(c) }
        XCTAssertNotNil(g.agreement(MaraDeal.water), b.trail)
        b.hold(GameInput(dx: 1), until: { g.max.pos.y > 13 }, timeout: 10, "down into the sump")
        b.hold(GameInput(dx: -1), until: { abs(g.max.pos.x - 84.4) < 0.8 }, timeout: 6, "to the valve")
        XCTAssertTrue(b.use("salvage:sump.valve"), b.trail)
        b.hold(GameInput(dx: -1), until: { abs(g.max.pos.x - 81.2) < 0.8 }, timeout: 6, "to the intake")
        XCTAssertTrue(b.use("clearIntake"), b.trail)
        b.idle(2.5)
        b.hold(GameInput(dx: 1), until: { g.max.pos.x > 86.2 }, timeout: 6, "to the rungs")
        b.hold(GameInput(up: true), until: { g.max.mode == .walk && g.max.pos.y < 9.2 }, timeout: 8, "up out of the sump")
        b.hold(GameInput(dx: -1), until: { abs(g.max.pos.x - 78.3) < 0.6 }, timeout: 8, "to the pump")
        XCTAssertTrue(b.use("panel:mara.pump"), b.trail)
        XCTAssertTrue(b.row("mara.pump", "deliver.job.water.c.valve"), b.trail)
        clock.now = clock.now.addingTimeInterval(3 * 3600)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.waterOn && g.liftRepaired, b.trail)

        // Up the lift. Step away and watch it go without him.
        XCTAssertTrue(b.go(Landmarks.liftX), b.trail)
        XCTAssertTrue(b.use("panel:mara.lift"), b.trail)
        XCTAssertTrue(b.row("mara.lift", "ride.up"), b.trail)
        b.idle(3)
        XCTAssertEqual(g.story.chapter, 4, b.trail)
        XCTAssertTrue(b.go(Landmarks.liftX + 4), b.trail)
        b.idle(7)
        XCTAssertNotNil(g.actor("wren"), "someone else used the route\n" + b.trail)

        // Follow her: east, down the loading rungs, across the cavern to Odi's.
        XCTAssertTrue(b.go(Double(Landmarks.loadingShaft.c0) - 0.2, timeout: 60), b.trail)
        b.hold(GameInput(climbDown: true), until: { g.max.pos.y > 29.4 }, timeout: 40, "down the loading rungs")
        if g.max.mode == .climb { b.hold(GameInput(dx: 1), until: { g.max.mode == .walk }, timeout: 3, "step off") }
        XCTAssertTrue(b.go(151.0, timeout: 120), b.trail)
        XCTAssertEqual(g.story.chapter, 5, b.trail)
        XCTAssertTrue(b.go(g.odi.pos.x - 1.0, timeout: 20), b.trail)
        XCTAssertTrue(b.use("panel:odi"), b.trail)
        g.chooseTalk("bye")

        // Odi's service lift up to the hotel.
        XCTAssertTrue(b.go(156.4, timeout: 20), b.trail)
        XCTAssertTrue(b.use("ride:hotel"), b.trail)
        b.idle(2.5)
        XCTAssertEqual(g.story.chapter, 6, b.trail)

        // The main route: across the ground floor, up the exit stair, west along the corridor, up to the gallery.
        XCTAssertTrue(b.go(188.6, timeout: 60), b.trail)
        XCTAssertTrue(b.use("x:diagram"), b.trail)
        XCTAssertTrue(b.go(247.6, timeout: 160), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 28.4 && g.max.mode == .walk }, timeout: 40, "up the exit stair")
        XCTAssertTrue(b.go(228.7, timeout: 60), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 12.6 && g.max.mode == .walk }, timeout: 40, "up to the gallery")
        b.idle(1)
        XCTAssertEqual(g.story.chapter, 7, b.trail)
        XCTAssertTrue(g.story.isDone("gallery", "landing"), b.trail)
        b.idle(2)
        if g.talk?.graph == "x.landing" { g.chooseTalk("skip") }
        b.idle(8)

        // An outing: down by the fire hatch and the luggage stair, out the back stairs, and back.
        XCTAssertTrue(b.go(228.7), b.trail)
        b.hold(GameInput(climbDown: true), until: { g.max.pos.y > 27.6 && g.max.mode == .walk }, timeout: 30, "down from the landing")
        if g.max.mode == .climb { b.hold(GameInput(dx: -1), until: { g.max.mode == .walk }, timeout: 3, "step off") }
        XCTAssertTrue(b.go(172.9, timeout: 120), b.trail)
        XCTAssertTrue(b.use("unbar"), b.trail)
        b.hold(GameInput(climbDown: true), until: { g.max.pos.y > 39.5 }, timeout: 30, "down the upper stair")
        if g.max.mode == .climb { b.hold(GameInput(dx: 1), until: { g.max.mode == .walk }, timeout: 3, "step off") }
        XCTAssertTrue(b.go(197.8, timeout: 60), b.trail)
        b.hold(GameInput(climbDown: true), until: { g.max.pos.y > 51.5 }, timeout: 30, "down the luggage stair")
        if g.max.mode == .climb { b.hold(GameInput(dx: -1), until: { g.max.mode == .walk }, timeout: 3, "step off") }
        XCTAssertTrue(b.go(Landmarks.backstairs.x, timeout: 60), b.trail)
        XCTAssertTrue(b.use("ride:transit"), b.trail)
        b.idle(2.5)
        XCTAssertTrue(b.use("ride:backstairs"), b.trail)
        b.idle(2.5)
        XCTAssertEqual(g.outings, 1, b.trail)

        // Back up to the gallery by the stairs he opened.
        XCTAssertTrue(b.go(Landmarks.luggageX - 0.3, timeout: 60), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 40.4 && g.max.mode == .walk }, timeout: 30, "up the luggage stair")
        XCTAssertTrue(b.go(172.9, timeout: 60), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 28.4 && g.max.mode == .walk }, timeout: 30, "up the upper stair")
        XCTAssertTrue(b.go(228.7, timeout: 120), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 12.6 && g.max.mode == .walk }, timeout: 40, "up to the gallery")

        // The toll: watch Wren pay.
        XCTAssertTrue(b.go(Landmarks.tollPos.x - 8, timeout: 60), b.trail)
        b.idle(24)
        XCTAssertTrue(g.story.flags.contains("toll.seen"), b.trail)

        // Stay: a shift on the passage, Wren's delivery walked through.
        XCTAssertTrue(b.go(Landmarks.stationPos.x, timeout: 60), b.trail)
        XCTAssertTrue(b.use("panel:gallery.station"), b.trail)
        XCTAssertTrue(b.row("gallery.station", "end.stay"), b.trail)
        var k = 0
        while g.story.ending == nil && k < 120, let w = g.actor("wren") {
            b.go(Swift.min(w.pos.x + 0.6, Landmarks.tollPos.x + 8), timeout: 6)
            b.idle(1)
            k += 1
        }
        XCTAssertEqual(g.story.ending?.id, "stay", b.trail)
        XCTAssertNotNil(g.epilogue)
        for l in b.log where l.contains("hurt") || l.contains("collapsed") || l.contains("ate") { print("BOT| " + l) }
    }
}
