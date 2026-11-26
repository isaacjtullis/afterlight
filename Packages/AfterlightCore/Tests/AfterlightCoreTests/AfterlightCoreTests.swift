import XCTest
@testable import AfterlightCore

final class FixedClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

func sim(_ g: Game, _ input: GameInput, _ seconds: Double) {
    var t = 0.0
    while t < seconds {
        g.update(dt: 1.0 / 60.0, input: input)
        _ = g.drainEvents()
        t += 1.0 / 60.0
    }
}

func walk(_ g: Game, to x: Double, timeout: Double = 20) {
    var t = 0.0
    while abs(g.max.pos.x - x) > 0.25 && t < timeout {
        let dx = g.max.pos.x < x ? 1 : -1
        g.update(dt: 1.0 / 60.0, input: GameInput(dx: dx))
        _ = g.drainEvents()
        t += 1.0 / 60.0
    }
    sim(g, GameInput(), 0.5)
}

final class WorldTests: XCTestCase {
    func testMaxStartsOnTheWorkshopFloor() {
        let g = Game()
        g.begin()
        sim(g, GameInput(), 1)
        XCTAssertEqual(g.max.pos.y, 30, accuracy: 0.08)
        XCTAssertTrue(g.max.ground)
    }

    func testHoldingDigCarvesALevelTunnel() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        let startStamina = g.max.stamina
        sim(g, GameInput(dig: true), 6)
        XCTAssertGreaterThan(g.max.pos.x, 33.5, "Max should creep forward as he carves")
        XCTAssertEqual(g.max.pos.y, 30, accuracy: 0.15, "the tunnel floor should stay level")
        XCTAssertLessThan(g.max.stamina, startStamina)
        XCTAssertEqual(g.world.m(33, 29), .dug)
        XCTAssertEqual(g.world.m(33, 28), .dug)
    }

    func testSteelDoesNotCarve() {
        let g = Game()
        let r = g.world.carve(center: V2(24.5, 18.5), radius: 0.8, floorY: nil, tool: .shovel)
        XCTAssertEqual(g.world.m(24, 18), .metal)
        XCTAssertTrue(r.cleared.isEmpty)
    }

    func testPickOnlyOpensSoftSeams() {
        let g = Game()
        _ = g.world.carve(center: V2(40.5, 20), radius: 0.8, tool: .pick)
        XCTAssertEqual(g.world.m(40, 20), .dug, "the pick cuts dirt overhead too")
        _ = g.world.carve(center: V2(26, 11.5), radius: 0.8, tool: .pick)
        XCTAssertEqual(g.world.m(26, 11), .dug)
    }
}

final class ChapterTests: XCTestCase {
    /// Plays the opening the way a player would, using the game's own controls.
    func testChapterOneToTwo() {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        var t = 0.0
        while g.max.pos.x < 37.1 && t < 30 { g.update(dt: 1 / 60, input: GameInput(dig: true)); _ = g.drainEvents(); t += 1 / 60 }
        walk(g, to: 37.5)
        sim(g, GameInput(down: true), 1.2)
        sim(g, GameInput(), 1.5)
        XCTAssertEqual(g.inv.count(.chargeCrystal), 1, "digging down beside the glint should pop the crystal")
        // He's in the hole he dug: ▲ climbs out.
        sim(g, GameInput(up: true), 4)
        sim(g, GameInput(), 0.5)

        var trail: [String] = []
        var tt = 0.0
        while abs(g.max.pos.x - 26.2) > 0.25 && tt < 30 {
            let y0 = g.max.pos.y, m0 = g.max.mode
            g.update(dt: 1.0 / 60.0, input: GameInput(dx: g.max.pos.x < 26.2 ? 1 : -1))
            _ = g.drainEvents()
            if abs(g.max.pos.y - y0) > 0.3 || g.max.mode != m0 { trail.append(String(format: "t%.2f x%.2f y%.2f->%.2f %@", tt, g.max.pos.x, y0, g.max.pos.y, "\(g.max.mode)")) }
            tt += 1.0 / 60.0
        }
        sim(g, GameInput(), 0.5)
        XCTAssertEqual(g.context?.id, "repair", "max at \(g.max.pos) mode \(g.max.mode) trail \(trail.prefix(12))")
        g.performContext()
        sim(g, GameInput(), 2)
        XCTAssertTrue(g.inv.has(.flashlight))
        XCTAssertEqual(g.context?.id, "switchOn")
        g.performContext()
        sim(g, GameInput(), 9.5)
        XCTAssertTrue(g.story.flags.contains("sawShaft"))
        // The water comes first now; this test is about the shaft.
        for s in Quest.homeWater.steps { g.story.step("drum", s.id) }
        g.quarters.filterFitted = true
        walk(g, to: 26.0)
        XCTAssertEqual(g.context?.id, "tryUp")
        g.performContext()
        sim(g, GameInput(), 10)
        XCTAssertEqual(g.story.chapter, 2)
        XCTAssertTrue(g.story.flags.contains("ordersOK"))
    }

    func testLadderPickSeamAndMaintenanceRoom() {
        let g = Game()
        g.begin()
        g.story.chapter = 2
        g.story.flags.formUnion(["needPick", "needLadder", "ordersOK", "inspected", "sawShaft", "triedUp", "flashOn"])
        g.story.addQuest(.firstAscent)
        g.inv.belt.append(.flashlight)
        g.inv.add(.liftTooth); g.inv.add(.spareGrip)
        g.inv.add(.pipe); g.inv.add(.pipe); g.inv.add(.fasteners, 4)
        walk(g, to: 26.2)
        g.craft("pick")
        g.craft("ladder")
        XCTAssertTrue(g.inv.has(.shortPick))
        XCTAssertEqual(g.inv.count(.ladderSection), 1)
        walk(g, to: 26.0)
        sim(g, GameInput(), 0.2)
        XCTAssertEqual(g.context?.id, "placeLadder")
        g.performContext()
        // climb up the ladder, onto the rungs, as far as the seam
        sim(g, GameInput(up: true), 8)
        XCTAssertEqual(g.max.mode, .climb)
        XCTAssertLessThan(g.max.pos.y, 16)
        // pick the seam open while climbing
        for _ in 0..<12 {
            sim(g, GameInput(up: true, dig: true), 1.5)
            sim(g, GameInput(up: true), 1.0)
            if g.story.flags.contains("hatchOpen") { break }
        }
        XCTAssertTrue(g.story.flags.contains("hatchOpen"), "max at \(g.max.pos); seam \((9...12).map { "\(g.world.m(25, $0))/\(g.world.m(26, $0))" })")
        sim(g, GameInput(up: true), 6)
        XCTAssertEqual(g.max.mode, .walk)
        sim(g, GameInput(), 1)
        XCTAssertEqual(g.story.chapter, 3, "stepping into the maintenance room completes chapter 2")
    }

    func testLightingThePassageToTheOutpost() {
        let g = Game()
        g.begin()
        g.story.chapter = 3
        g.story.flags.formUnion(["ordersOK", "ch2Done", "hatchOpen"])
        g.story.addQuest(.dryTaps); g.story.addQuest(.lights)
        for x in stride(from: 35.5, through: 72.5, by: 1.0) {
            _ = g.world.carve(center: V2(x, 7.6), radius: 0.9, floorY: 9, tool: .shovel)
            _ = g.world.carve(center: V2(x, 8.45), radius: 0.9, floorY: 9, tool: .shovel)
        }
        for x in [40.0, 50.0, 60.0, 70.0] { g.world.props.append(Prop(id: "lamp.\(x)", kind: .lamp, pos: V2(x, 9))) }
        g.max.pos = V2(30, 9)
        sim(g, GameInput(), 0.5)
        XCTAssertTrue(g.story.flags.contains("passageLit"))
        XCTAssertEqual(g.story.chapter, 3, "lighting the way is a side quest; the chapter ends by going up")
    }
}

final class JobTests: XCTestCase {
    func testResolverCountsStepsByTimeAndStamina() {
        let steps = (0..<10).map { _ in JobStep(label: "Dig", seconds: 300, stamina: 7, endPos: V2(0, 0)) }
        let plan = JobPlan(id: "j", kind: .dig, title: "t", summary: "", steps: steps, staminaBudget: 50, pauseIndex: nil, pauseReason: nil)
        XCTAssertEqual(JobResolver.completedSteps(plan, elapsed: 0), 0)
        XCTAssertEqual(JobResolver.completedSteps(plan, elapsed: 650), 2)
        XCTAssertEqual(JobResolver.completedSteps(plan, elapsed: 99_999), 7, "50 stamina at 7 per step is 7 steps")
        var paused = plan; paused.pauseIndex = 3
        XCTAssertEqual(JobResolver.completedSteps(paused, elapsed: 99_999), 3)
    }

    func testDigJobPaysOutExactlyOnce() {
        let clock = FixedClock()
        let g = Game()
        g.clock = { clock.now }
        g.story.flags.insert("ordersOK")
        guard let plan = g.availableJobs().first(where: { $0.kind == .dig }) else { return XCTFail("no dig job") }
        g.startJob(plan, startedAt: clock.now)
        clock.now = clock.now.addingTimeInterval(3 * 3600)
        let rec = g.activeJob!
        let n = JobResolver.completedSteps(rec.plan, elapsed: 3 * 3600)
        XCTAssertGreaterThan(n, 5)
        let first = g.applyJob(rec, completed: n, recalled: false)
        XCTAssertNotNil(first)
        XCTAssertEqual(g.world.m(33, 29), .dug)
        let staminaAfter = g.max.stamina
        let second = g.applyJob(rec, completed: n, recalled: false)
        XCTAssertNil(second, "a job can never pay out twice")
        XCTAssertEqual(g.max.stamina, staminaAfter)
    }

    func testDigJobStopsAtTheCavern() {
        let g = Game()
        g.story.flags.insert("ordersOK")
        let plan = g.availableJobs(meals: 3).first(where: { $0.kind == .dig })!
        XCTAssertNotNil(plan.pauseIndex)
        XCTAssertEqual(plan.pauseReason?.contains("open air"), true)
    }
}

final class SaveTests: XCTestCase {
    func testRoundTripKeepsTerrainAndStory() throws {
        let g = Game()
        g.begin()
        walk(g, to: 31.3)
        sim(g, GameInput(dig: true), 4)
        g.story.flags.insert("custom")
        g.inv.add(.wire, 3)
        let data = try g.encodeSave()
        let s = try Game.decodeSave(data)
        let h = Game.load(s)
        XCTAssertEqual(h.world.m(32, 29), g.world.m(32, 29))
        XCTAssertEqual(h.world.density(32.6, 28.6), g.world.density(32.6, 28.6), accuracy: 0.01)
        XCTAssertTrue(h.story.flags.contains("custom"))
        XCTAssertEqual(h.inv.count(.wire), 3)
        XCTAssertEqual(h.max.pos.x, g.max.pos.x, accuracy: 0.001)
        XCTAssertLessThan(data.count, 120_000, "saves should stay small")
    }
}

final class InventoryTests: XCTestCase {
    func testBulkyItemsTakeWholeSlots() {
        var inv = Inventory()
        XCTAssertEqual(inv.add(.pipe, 12), Inventory.capacity)
        XCTAssertEqual(inv.add(.wire), 0)
        inv.remove(.pipe, 2)
        XCTAssertEqual(inv.add(.wire, 7), 7)
        XCTAssertEqual(inv.room(for: .pipe), 0)
    }
}
