import XCTest
@testable import AfterlightCore

final class ExpeditionTests: XCTestCase {
    func onPlatform(_ x: Double) -> Game {
        let g = Game()
        g.begin()
        g.story.chapter = 4
        g.story.flags.formUnion(["sawPlatform", "flashOn", "sawShaft"])
        g.story.addQuest(.farEdge)
        g.max.pos = V2(x, Double(Landmarks.transit.floor)); g.max.ground = true
        sim(g, GameInput(), 0.3)
        return g
    }

    func testLoadingShaftReachesTheCavern() {
        let w = WorldGen.make()
        let rungs = w.climbs.first { $0.id == "rungs.loading" }
        XCTAssertNotNil(rungs)
        let x = Double(Landmarks.loadingShaft.c0) + 1.0
        for y in stride(from: 3.4, to: 29.5, by: 0.5) { XCTAssertFalse(w.solid(x, y), "the shaft is open at y \(y)") }
        XCTAssertFalse(w.solid(Double(Landmarks.transit.x1) + 1.5, 2.0), "the platform's east wall is broken through")
    }

    func testPitchCampStashReloadTake() throws {
        let g = onPlatform(78)
        g.inv.add(.campCrate)
        sim(g, GameInput(), 0.2)
        XCTAssertEqual(g.context?.id, "pitchCamp", "at \(g.max.pos): \(g.campObstruction() ?? "-")")
        g.performContext()
        let camp = g.world.props(of: .camp).first!
        XCTAssertEqual(g.inv.count(.campCrate), 0)
        g.inv.add(.batteryCell)
        let i = g.inv.slots.firstIndex { $0?.id == .batteryCell }!
        g.stash(slot: i, in: camp.id)
        XCTAssertEqual(g.inv.count(.batteryCell), 0)
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(back.campStock(camp.id).first?.id, .batteryCell)
        back.takeFromCamp(camp.id, item: .batteryCell)
        XCTAssertEqual(back.inv.count(.batteryCell), 1)
        XCTAssertTrue(back.campStock(camp.id).isEmpty, "taken, not copied")
        let again = Game.load(try Game.decodeSave(try back.encodeSave()))
        XCTAssertEqual(again.inv.count(.batteryCell) + again.campStock(camp.id).count, 1, "never duplicates or vanishes")
    }

    func testNoCampOnUnevenOrCrampedGround() {
        let g = onPlatform(78)
        g.inv.add(.campCrate)
        g.max.pos = V2(Double(Landmarks.loadingShaft.c0) - 0.4, Double(Landmarks.transit.floor))
        sim(g, GameInput(), 0.1)
        XCTAssertNotNil(g.campObstruction())
    }

    func testBatteryWakesTheSignalAndItStaysLit() throws {
        let g = onPlatform(Landmarks.signalLampX + 0.4)
        XCTAssertEqual(g.context?.id, "signalLook")
        g.inv.add(.batteryCell)
        sim(g, GameInput(), 0.1)
        XCTAssertEqual(g.context?.id, "signal")
        g.performContext()
        XCTAssertTrue(g.world.prop("signal")!.flags.contains("lit"))
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertTrue(back.world.prop("signal")!.flags.contains("lit"))
        XCTAssertTrue(back.story.isDone("far", "cell"))
    }

    func testClimbDownTheLoadingShaftIntoTheCavern() {
        let g = onPlatform(Double(Landmarks.loadingShaft.c0) - 0.2)
        var t = 0.0
        while g.max.mode != .climb && t < 3 { g.update(dt: 1 / 60, input: GameInput(climbDown: true)); _ = g.drainEvents(); t += 1 / 60 }
        XCTAssertEqual(g.max.mode, .climb)
        sim(g, GameInput(climbDown: true), 14)
        XCTAssertGreaterThan(g.max.pos.y, 28)
        XCTAssertTrue(g.story.flags.contains("reachedCavern") || g.max.pos.y > 28)
    }

    func testMapRemembersWhereMaxHasBeen() {
        let g = Game()
        g.begin()
        sim(g, GameInput(), 0.2)
        let n = g.story.explored.count
        XCTAssertGreaterThan(n, 10)
        g.max.pos = V2(80, 9)
        sim(g, GameInput(), 0.1)
        XCTAssertGreaterThan(g.story.explored.count, n)
    }

    func testDepthInFeet() {
        XCTAssertEqual(Depth.feet(atY: 30), 2600)
        XCTAssertEqual(Depth.label(atY: 30), "−2,600 ft")
    }
}
