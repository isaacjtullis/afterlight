import XCTest
@testable import AfterlightCore

final class SalvageTests: XCTestCase {
    /// Every salvage wreck must rest on the cavern floor with open air above it, where Max can stand next to it.
    func testWrecksSitOnTheCavernFloorNotInsideTheEarth() {
        let w = WorldGen.make()
        for id in ["liftcar", "drill", "gantry"] {
            guard let pr = w.prop(id) else { return XCTFail("missing \(id)") }
            let c = Int(pr.pos.x), r = Int(pr.pos.y)
            XCTAssertTrue(w.m(c, r).solid, "\(id) should rest on solid ground (row \(r))")
            XCTAssertFalse(w.m(c, r - 1).solid, "\(id) should have open air above it (row \(r - 1))")
            XCTAssertGreaterThan(pr.pos.y, 20, "\(id) should be down where Max walks, not up at y=\(pr.pos.y)")
        }
    }

    /// Standing beside the lift car offers Salvage.
    func testStandingAtTheLiftCarOffersSalvage() {
        let g = Game(world: WorldGen.make())
        g.begin()
        g.story.flags.formUnion(["broke", "needPick"])
        g.story.chapter = 2
        let car = g.world.prop("liftcar")!
        g.max.pos = V2(car.pos.x + 0.6, car.pos.y)
        g.update(dt: 1.0 / 60, input: GameInput())
        XCTAssertEqual(g.context?.id, "salvage:liftcar")
        XCTAssertNotNil(g.guide)
    }
}

final class SalvageSaveTests: XCTestCase {
    /// A save from a build that buried the lift car comes back with it on the cavern floor.
    func testOldSaveWithBuriedWreckIsRepaired() throws {
        let g = Game(world: WorldGen.make())
        g.begin()
        let i = g.world.propIndex("liftcar")!
        g.world.props[i].pos = V2(64.5, 14)
        g.story.flags.remove(Game.worldVersionFlag)
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertGreaterThan(back.world.prop("liftcar")!.pos.y, 20)
    }
}

final class HomeGroundTests: XCTestCase {
    /// The lift car sits in a small pit just east of the crystal, not out in a distant cavern.
    func testLiftCarIsCloseToHome() {
        let w = WorldGen.make()
        let car = w.prop("liftcar")!
        XCTAssertLessThan(car.pos.x, 50)
        XCTAssertEqual(car.pos.y, 30, accuracy: 0.01)
        XCTAssertGreaterThan(Double(Landmarks.caveStart), 100, "the big cavern is far from home")
    }

    /// Hacking the roots in the west door gives wood, strapped outside the bag.
    func testRootsGiveWood() {
        let g = Game()
        g.begin()
        walk(g, to: 20.8)
        g.max.face = -1
        sim(g, GameInput(dig: true), 4)
        XCTAssertGreaterThanOrEqual(g.inv.wood, 20, "cutting into the door roots should yield wood")
        XCTAssertEqual(g.inv.wood % Inventory.woodPerRootTile, 0)
        XCTAssertEqual(Inventory.capacity - g.inv.freeSlots, 0, "wood doesn't take a pocket")
    }

    /// Wood can't go past what the bag can carry.
    func testWoodIsCapped() {
        var inv = Inventory()
        XCTAssertEqual(inv.addWood(150), 150)
        XCTAssertEqual(inv.addWood(150), Inventory.woodCap - 150)
        XCTAssertEqual(inv.wood, Inventory.woodCap)
    }

    /// Digging down as deep as he likes, then holding ▲ cuts footholds and climbs him back out.
    func testDigDownThenClimbOut() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        sim(g, GameInput(dig: true), 5)
        let x = g.max.pos.x
        var t = 0.0
        while g.max.pos.y < 32.3 && t < 12 { g.update(dt: 1 / 60, input: GameInput(down: true)); _ = g.drainEvents(); t += 1 / 60 }
        XCTAssertGreaterThan(g.max.pos.y, 32.2, "Max should be able to dig down more than two tiles")
        sim(g, GameInput(), 0.5)
        sim(g, GameInput(up: true), 6)
        sim(g, GameInput(), 0.6)
        XCTAssertEqual(g.max.mode, .walk)
        XCTAssertLessThan(g.max.pos.y, 30.4, "Max should climb back out of his hole; he's at \(g.max.pos), started at x \(x)")
    }

    /// A plank bridges a hole: it costs five wood and Max can walk across it.
    func testPlankCoversAHole() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        sim(g, GameInput(dig: true), 6)
        // a hole one tile wide, two deep, just behind where Max stands
        let hx = Int(g.max.pos.x) - 3
        for r in 30...31 { g.world.set(hx, r, .dug, back: .earth) }
        g.world.rebuildDensity()
        XCTAssertFalse(g.world.m(hx, 30).solid)
        g.inv.wood = 20
        g.max.pos = V2(Double(hx) + 1.45, 30); g.max.face = -1; g.max.vx = 0; g.max.ground = true
        sim(g, GameInput(), 0.3)
        XCTAssertEqual(g.context?.id, "plank", "max at \(g.max.pos)")
        g.performContext()
        XCTAssertEqual(g.inv.wood, 15)
        XCTAssertTrue(g.world.m(hx, 30) == .plank || g.world.m(hx - 1, 30) == .plank || g.world.m(hx + 1, 30) == .plank)
        walk(g, to: Double(hx) - 1.0)
        XCTAssertEqual(g.max.pos.y, 30, accuracy: 0.25, "Max walks across the plank instead of dropping in")
    }

    /// Repairing the flashlight without looking at it first must still leave the workbench usable.
    func testBenchOffersThePickWithoutInspecting() {
        let g = Game()
        g.begin()
        g.story.chapter = 2
        g.story.flags.formUnion(["needPick", "needLadder", "sawShaft", "triedUp", "flashOn"])
        g.inv.belt.append(.flashlight)
        g.inv.add(.liftTooth); g.inv.add(.spareGrip)
        walk(g, to: Landmarks.bench.x)
        sim(g, GameInput(), 0.3)
        XCTAssertEqual(g.context?.id, "bench")
        XCTAssertEqual(g.context?.label, "Make short pick")
    }

    /// Holding an arrow, Max walks and then breaks into a run.
    func testHoldingAnArrowBreaksIntoARun() {
        let g = Game()
        g.begin()
        for c in 32...56 { for r in 27...29 { g.world.set(c, r, .dug, back: .earth) }; g.world.set(c, 30, .dirt) }
        g.world.rebuildDensity()
        g.max.pos = V2(32.6, 30)
        sim(g, GameInput(dx: 1), 0.3)
        XCTAssertLessThanOrEqual(abs(g.max.vx), Tuning.walkSpeed + 0.01)
        sim(g, GameInput(dx: 1), 1.0)
        XCTAssertTrue(g.max.running)
        XCTAssertGreaterThan(abs(g.max.vx), Tuning.walkSpeed + 0.5)
    }
}
