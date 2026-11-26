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
        sim(g, GameInput(), 0.3)
        // Whatever lip is left is short enough to walk or scramble up.
        sim(g, GameInput(dx: -1), 1.5)
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
        g.max.pos = V2(Double(hx) + 1.6, 30); g.max.face = -1; g.max.vx = 0; g.max.ground = true
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
        sim(g, GameInput(dx: 1), 0.6)
        XCTAssertLessThanOrEqual(abs(g.max.vx), Tuning.walkSpeed + 0.01, "walking unless the wheel is pushed out")
        let st = g.max.stamina
        sim(g, GameInput(dx: 1, run: true), 1.0)
        XCTAssertTrue(g.max.running)
        XCTAssertLessThan(g.max.stamina, st, "running costs stamina")
        XCTAssertGreaterThan(abs(g.max.vx), Tuning.walkSpeed + 0.5)
    }

    /// JUMP in the open: Max jumps and lands again.
    func testTapUpJumps() {
        let g = Game()
        g.begin()
        g.max.pos = V2(23.5, 30)
        sim(g, GameInput(), 0.3)
        var peak = 30.0
        for i in 0..<70 { g.update(dt: 1 / 60, input: GameInput(jump: i < 25)); _ = g.drainEvents(); peak = min(peak, g.max.pos.y) }
        XCTAssertLessThan(peak, 29.0, "a held jump clears about a tile")
        // A quick tap is only a hop.
        var hop = 30.0
        for i in 0..<70 { g.update(dt: 1 / 60, input: GameInput(jump: i < 2)); _ = g.drainEvents(); hop = min(hop, g.max.pos.y) }
        XCTAssertGreaterThan(hop, peak + 0.3, "a tap is a smaller hop than a held jump")
        XCTAssertEqual(g.max.pos.y, 30, accuracy: 0.1)
        XCTAssertTrue(g.max.ground)
    }

    /// The UP button digs overhead dirt with just the shovel.
    func testShovelDigsUp() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        sim(g, GameInput(dig: true), 4)
        let x = g.max.pos.x
        XCTAssertTrue(g.world.solid(x, 27.15), "earth overhead before")
        sim(g, GameInput(digUp: true), 2.5)
        XCTAssertFalse(g.world.solid(x, 27.15), "digging up should open the earth overhead")
    }

    /// A one-tile ledge (the far side of a hole) is scrambled over just by walking into it.
    func testWalkingIntoALedgeScramblesUp() {
        let g = Game()
        g.begin()
        for c in 32...44 { for r in 26...29 { g.world.set(c, r, .dug, back: .earth) }; g.world.set(c, 30, .dirt) }
        for c in 32...36 { g.world.set(c, 30, .dug, back: .earth); g.world.set(c, 31, .dirt) }   // a sunken stretch, one tile down
        g.world.rebuildDensity()
        g.max.pos = V2(34, 31); g.max.ground = true
        sim(g, GameInput(), 0.3)
        sim(g, GameInput(dx: 1), 2.5)
        XCTAssertGreaterThan(g.max.pos.x, 38, "Max should climb out of the dip and keep going, at \(g.max.pos)")
        XCTAssertEqual(g.max.pos.y, 30, accuracy: 0.2)
    }

    /// The pantry restores Max's strength with a ration.
    func testPantryRestoresStamina() {
        let g = Game()
        g.begin()
        g.max.stamina = 20; g.max.hunger = 30
        walk(g, to: 28.3)
        sim(g, GameInput(), 0.2)
        XCTAssertEqual(g.context?.id, "pantry")
        g.performContext()
        XCTAssertGreaterThan(g.max.stamina, 55, "a meal gives a good chunk back")
        XCTAssertEqual(g.world.prop("pantry")?.stock.first?.count, 11)
    }

    /// Something dropped from the bag stays in the world and can be picked up again.
    func testDropAndPickUp() {
        let g = Game()
        g.begin()
        g.max.pos = V2(23.0, 30); g.max.face = 1
        g.inv.add(.wire, 2)
        let i = g.inv.slots.firstIndex { $0?.id == .wire }!
        g.dropSlot(i)
        XCTAssertEqual(g.inv.count(.wire), 0)
        XCTAssertEqual(g.world.props(of: .pile).count, 1)
        sim(g, GameInput(), 0.2)
        XCTAssertEqual(g.context?.id.hasPrefix("search:pile"), true)
        g.performContext()
        XCTAssertEqual(g.inv.count(.wire), 2)
        XCTAssertTrue(g.world.props(of: .pile).isEmpty)
    }

    /// One more jump in mid-air, and only one.
    func testDoubleJump() {
        let g = Game()
        g.begin()
        g.max.pos = V2(23.5, 30)
        sim(g, GameInput(), 0.3)
        var peak = 30.0
        for i in 0..<90 {
            let up = i < 12 || (i >= 16 && i < 28) || (i >= 32 && i < 40)
            g.update(dt: 1 / 60, input: GameInput(jump: up)); _ = g.drainEvents(); peak = min(peak, g.max.pos.y)
        }
        XCTAssertLessThan(peak, 28.1, "the second jump carries Max higher than one jump")
        XCTAssertGreaterThan(peak, 26.0, "but there is no third")
    }

    /// The earth holds things: ore veins, relics, spores and roots, all in packed dirt.
    func testTheEarthHasFinds() {
        let w = WorldGen.make()
        let finds = w.buried.filter { $0.id != "crystal" }
        XCTAssertGreaterThan(finds.count, 60)
        XCTAssertTrue(finds.allSatisfy { w.m(Int($0.pos.x), Int($0.pos.y)).solid })
        XCTAssertTrue(Set(finds.map(\.item.id)).isSuperset(of: [.copperOre, .ironOre, .quartz, .coin]))
        var roots = 0
        for r in 12..<55 { for c in 40..<150 where w.m(c, r) == .root { roots += 1 } }
        XCTAssertGreaterThan(roots, 20, "roots run through the earth away from home too")
    }

    /// Holding the wheel up next to a short bank doesn't start a climb: that's a jump, not a climb.
    func testNoClimbUpShortBanks() {
        let g = Game()
        g.begin()
        for c in 32...44 { for r in 26...29 { g.world.set(c, r, .dug, back: .earth) }; g.world.set(c, 30, .dirt) }
        for c in 32...36 { g.world.set(c, 30, .dug, back: .earth); g.world.set(c, 31, .dirt) }
        g.world.rebuildDensity()
        g.max.pos = V2(36.5, 31); g.max.face = 1; g.max.ground = true
        sim(g, GameInput(), 0.3)
        sim(g, GameInput(up: true), 1.5)
        XCTAssertEqual(g.max.mode, .walk, "a one-tile bank is jumped or walked up, not climbed")
    }

    /// One DIG button: aiming the wheel down digs the floor, up digs overhead.
    func testWheelAimsTheDig() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        sim(g, GameInput(dig: true), 4)
        let y0 = g.max.pos.y
        sim(g, GameInput(dig: true, climbDown: true), 2)
        XCTAssertGreaterThan(g.max.pos.y, y0 + 0.5, "DIG with the wheel down digs down")
    }

    /// A single tap of DIG opens a full body-height bite in front of Max.
    func testOneChompClearsHeadToToe() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        g.max.face = 1
        let x = g.max.pos.x + Tuning.halfWidth + 0.46
        g.update(dt: 1 / 60, input: GameInput(dig: true)); _ = g.drainEvents()
        sim(g, GameInput(), 0.6)
        XCTAssertFalse(g.world.solid(x, 29.4), "low earth cleared")
        XCTAssertFalse(g.world.solid(x, 28.4), "high earth cleared in the same chomp")
    }

    /// The flashlight runs down; a lamp cell from the bag fills it again.
    func testBatteryDrainsAndSwaps() {
        let g = Game()
        g.begin()
        g.inv.belt.append(.flashlight); g.story.flags.formUnion(["flashOn", "sawShaft"])
        g.battery = 1
        sim(g, GameInput(), 20)
        XCTAssertEqual(g.battery, 0, accuracy: 0.01)
        XCTAssertFalse(g.story.flags.contains("flashOn"), "a dead flashlight goes out")
        g.inv.add(.lampCell)
        g.swapCell()
        XCTAssertEqual(g.battery, 100)
        XCTAssertEqual(g.inv.count(.lampCell), 0)
    }

    /// At zero health Max wakes up in bed, weak but whole.
    func testCollapseWakesAtHome() {
        let g = Game()
        g.begin()
        g.max.pos = V2(36, 30)
        g.hurt(500, why: "test")
        XCTAssertEqual(g.max.pos.x, 22.4, accuracy: 0.01)
        XCTAssertGreaterThan(g.max.health, 0)
    }
}
