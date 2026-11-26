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
        XCTAssertNotEqual(g.context?.id, "pitchCamp", "nothing to set until Max chooses to")
        g.beginPlacing(.campCrate)
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

    func testPoweringTheShelter() throws {
        let g = Game()
        g.begin()
        g.inv.belt.append(.flashlight); g.story.flags.formUnion(["flashOn", "sawShaft"])
        sim(g, GameInput(), 0.2)
        XCTAssertNotNil(g.story.quests.first { $0.id == "homeLight" })
        walk(g, to: 21.55)
        XCTAssertEqual(g.context?.id, "genLook")
        g.performContext()
        sim(g, GameInput(), 0.3)
        XCTAssertEqual(g.context?.id, "genFree")
        g.performContext()
        sim(g, GameInput(), 2.0)
        XCTAssertTrue(g.knownRecipes.contains { $0.id == "cell" }, "the ore cell recipe is known once Max has seen the generator")
        g.inv.add(.batteryCell)
        sim(g, GameInput(), 0.2)
        XCTAssertEqual(g.context?.id, "genPower")
        g.performContext()
        sim(g, GameInput(), 1.5)
        XCTAssertTrue(g.story.flags.contains("shelterLit"))
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertTrue(back.story.isDone("homeLight", "fix"))
    }

    func testHungerIsItsOwnMeterAndFoodFromTheBagHelps() {
        let g = Game()
        g.begin()
        sim(g, GameInput(), 60)
        XCTAssertLessThan(g.max.hunger, 99, "hunger drops with time")
        XCTAssertGreaterThan(g.max.stamina, 95, "standing still doesn't tire Max")
        g.max.hunger = 20
        g.packRation()
        XCTAssertEqual(g.inv.count(.ration), 1)
        g.eat(.ration)
        XCTAssertGreaterThan(g.max.hunger, 60)
        XCTAssertEqual(g.inv.count(.ration), 0)
    }

    func testBuildAnywhereNeedsABench() {
        let g = Game()
        g.begin()
        g.story.flags.formUnion(["wood", "sawPlatform"])
        g.inv.wood = 60; g.inv.add(.fasteners, 6)
        g.max.pos = V2(36, 30)
        let bench = Recipes.all.first { $0.id == "fieldBench" }!
        XCTAssertNil(g.buildBlocker(bench), "a field workbench can be built anywhere")
        let cot = Recipes.all.first { $0.id == "cot" }!
        XCTAssertEqual(g.buildBlocker(cot), "Needs a workbench")
    }

    func testOldSavesCanGetThroughTheWarmPipePatch() throws {
        let g = Game()
        g.world.set(35, 6, .metal)
        g.story.flags.remove("world3")
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(back.world.m(35, 6), .dirt)
    }

    /// The quarters keep time: a watered, lit plot is ready after its grow time, even across a save.
    func testGardenGrowsOnTheRealClock() throws {
        let clock = FixedClock()
        let g = Game()
        g.clock = { clock.now }
        g.begin()
        g.quartersTick(now: clock.now)
        g.inv.add(.seedTin)
        g.plant(0, .seedTin)
        g.waterPlot(0)
        clock.now = clock.now.addingTimeInterval(50 * 60)
        let back = Game.load(try Game.decodeSave(try g.encodeSave()), clock: { clock.now })
        back.quartersTick(now: clock.now)
        XCTAssertTrue(back.plotReady(0))
        back.harvestPlot(0)
        XCTAssertEqual(back.available(.greens), 3)
    }

    func testFilterClogsAndLampsDrain() {
        let clock = FixedClock()
        let g = Game()
        g.clock = { clock.now }
        g.quartersTick(now: clock.now)
        clock.now = clock.now.addingTimeInterval(30 * 3600)
        g.quartersTick(now: clock.now)
        XCTAssertLessThan(g.quarters.filter, 20)
        XCTAssertEqual(g.quarters.charge, 0)
        XCTAssertFalse(g.quartersNeeds(now: clock.now).isEmpty)
        g.rinseFilter()
        XCTAssertEqual(g.quarters.filter, 100)
    }

    /// Lantern levels go one at a time, each brighter than the last.
    func testLanternLevels() {
        let g = Game()
        g.begin()
        XCTAssertEqual(g.lanternLevel, 1)
        XCTAssertTrue(g.upgradeOpen("lantern2"))
        XCTAssertFalse(g.upgradeOpen("lantern3"))
        g.applyUpgrade("lantern2")
        XCTAssertEqual(g.lanternLevel, 2)
        XCTAssertTrue(g.upgradeOpen("lantern3"))
        XCTAssertGreaterThan(Game.lanternRadius(5), Game.lanternRadius(1) * 2)
    }

    /// Storing wood moves it off the bag and back.
    func testStoreWood() {
        let g = Game()
        g.begin()
        g.inv.wood = 120
        XCTAssertTrue(g.atHome)
        g.storeWood()
        XCTAssertEqual(g.inv.wood, 0); XCTAssertEqual(g.storage.wood, 120); XCTAssertEqual(g.woodAvailable, 120)
        g.takeWood(50)
        XCTAssertEqual(g.inv.wood, 50); XCTAssertEqual(g.storage.wood, 70)
    }

    /// A torch only offers to be set once Max picks it to place, and placing ends after.
    func testPlacingATorch() {
        let g = onPlatform(78)
        g.inv.add(.torch)
        sim(g, GameInput(), 0.2)
        XCTAssertNotEqual(g.context?.id, "placeTorch")
        g.beginPlacing(.torch)
        XCTAssertEqual(g.placing, .torch)
        sim(g, GameInput(), 0.2)
        XCTAssertEqual(g.context?.id, "placeTorch")
        g.performContext()
        XCTAssertNil(g.placing)
        XCTAssertEqual(g.inv.count(.torch), 0)
        XCTAssertTrue(g.world.props.contains { $0.flags.contains("torch") })
    }

    /// A wooden ladder that stops short of the shaft rungs still hands Max over, up and back down.
    func testLadderToRungsWithAGap() {
        let g = Game()
        g.begin()
        g.world.climbs.removeAll { $0.id == "ladder.shaft" }
        g.world.climbs.append(Climb(id: "wl", x: 26.0, top: 26.5, bottom: 30.0, kind: .ladder))
        g.max.pos = V2(26, 29); g.max.mode = .climb; g.max.climbID = "wl"; g.max.ground = false
        var t = 0.0
        while g.max.pos.y > 20 && t < 8 { g.update(dt: 1 / 60, input: GameInput(up: true)); _ = g.drainEvents(); t += 1 / 60 }
        XCTAssertEqual(g.max.climbID, Landmarks.shaftRungsID, "Max should grab the rungs above the ladder")
        XCTAssertLessThan(g.max.pos.y, 20.5, "and keep climbing, at \(g.max.pos)")
        t = 0
        while g.max.pos.y < 28 && t < 10 { g.update(dt: 1 / 60, input: GameInput(down: true)); _ = g.drainEvents(); t += 1 / 60 }
        XCTAssertGreaterThan(g.max.pos.y, 27.5, "and climb back down onto the ladder, at \(g.max.pos) on \(g.max.climbID ?? "-")")
    }
}
