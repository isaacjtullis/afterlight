import XCTest
@testable import AfterlightCore

/// Build 2 · Meet Mara and let someone use the route.
/// Pass when: a player sees another person use the route they opened and can follow them to a real
/// destination. All three Mara agreements reach Odi. Refusing a deal or keeping the lamp leaves a way forward.
final class CampaignBuild2Tests: XCTestCase {

    // MARK: helpers (same setup the chapter-3 tests use)

    func outpost(_ clock: FixedClock) -> Game {
        let g = Game()
        g.clock = { clock.now }
        g.begin()
        g.story.chapter = 3
        g.story.flags.formUnion(["ordersOK", "ch2Done", "hatchOpen", "flashOn"])
        g.story.addQuest(.dryTaps)
        for x in stride(from: 35.5, through: 72.5, by: 1.0) {
            _ = g.world.carve(center: V2(x, 7.6), radius: 0.9, floorY: 9, tool: .shovel)
            _ = g.world.carve(center: V2(x, 8.45), radius: 0.9, floorY: 9, tool: .shovel)
        }
        place(g, V2(60, 9))
        return g
    }

    func place(_ g: Game, _ p: V2) {
        g.max.pos = p
        g.max.ground = true; g.max.vx = 0; g.max.vy = 0; g.max.mode = .walk
        g.max.digFloor = p.y
        sim(g, GameInput(), 0.3)
    }

    func rideUp(_ g: Game) {
        place(g, V2(Landmarks.liftX, 9))
        g.choosePanel("mara.lift", "ride.up")
        sim(g, GameInput(), 3)
    }

    /// From the transit platform to Odi's door with the controls only: east, down the loading rungs, across the floor.
    func walkToOdi(_ g: Game, file: StaticString = #filePath, line: UInt = #line) {
        let b = Bot(g)
        XCTAssertTrue(b.go(Double(Landmarks.loadingShaft.c0) - 0.2, timeout: 90), b.trail, file: file, line: line)
        b.hold(GameInput(climbDown: true), until: { g.max.pos.y > 29.4 }, timeout: 40, "down the loading rungs")
        if g.max.mode == .climb { b.hold(GameInput(dx: 1), until: { g.max.mode == .walk }, timeout: 3, "step off the rungs") }
        XCTAssertGreaterThan(g.max.pos.y, 29, b.trail, file: file, line: line)
        XCTAssertTrue(b.go(151.0, timeout: 120), b.trail, file: file, line: line)
        XCTAssertTrue(g.inOdiRoom, "in Odi's room at \(g.max.pos)\n\(b.trail)", file: file, line: line)
        XCTAssertEqual(g.story.chapter, 5, file: file, line: line)
    }

    func helpRoute(_ clock: FixedClock) -> Game {
        let g = outpost(clock)
        place(g, V2(79.6, 9))
        g.choosePanel("mara", "offer.collab")
        place(g, V2(84.4, 14)); g.performContext(); sim(g, GameInput(), 2.5)
        place(g, V2(81.2, 14)); g.performContext(); sim(g, GameInput(), 2.5)
        place(g, V2(78.3, 9)); g.choosePanel("mara.pump", "deliver.job.water.c.valve")
        clock.now = clock.now.addingTimeInterval(3600)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.liftRepaired && g.waterOn)
        rideUp(g)
        return g
    }

    func payRoute(_ clock: FixedClock) -> Game {
        let g = outpost(clock)
        g.inv.add(.pipe, 1); g.inv.add(.wire, 2); g.inv.add(.fasteners, 4)
        place(g, V2(79.6, 9))
        g.choosePanel("mara", "offer.trade")
        for i in 0..<3 { g.choosePanel("mara.lift", "deliver.job.lift.c.pay\(i)") }
        clock.now = clock.now.addingTimeInterval(MaraDeal.liftSeconds + 1)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.liftRepaired)
        rideUp(g)
        return g
    }

    func chimneyRoute(_ clock: FixedClock) -> Game {
        let g = outpost(clock)
        place(g, V2(79.6, 9))
        g.choosePanel("mara", "offer.decline")
        g.inv.add(.rope, 2); g.inv.add(.fasteners, 2)
        place(g, V2(71.0, 9))
        g.choosePanel("chimney", "chimney.rig")
        sim(g, GameInput(), 1.5)
        sim(g, GameInput(up: true), 6)
        sim(g, GameInput(), 1)
        return g
    }

    // MARK: all three agreements reach Odi

    func testHelpingMaraReachesOdi() {
        let g = helpRoute(FixedClock())
        XCTAssertEqual(g.story.chapter, 4)
        walkToOdi(g)
    }

    func testPayingForTheLiftReachesOdi() {
        let g = payRoute(FixedClock())
        XCTAssertEqual(g.story.chapter, 4)
        walkToOdi(g)
    }

    func testRefusingAndClimbingTheChimneyReachesOdi() {
        let g = chimneyRoute(FixedClock())
        XCTAssertEqual(g.story.chapter, 4)
        XCTAssertTrue(g.story.coop.agreements.isEmpty, "no deal")
        walkToOdi(g)
    }

    // MARK: someone else uses the route

    func testTheLiftMovesWithoutMaxAndWrenWalksToOdi() throws {
        let g = payRoute(FixedClock())
        XCTAssertGreaterThan(g.liftCar, 0.5, "the cage is up with Max")
        // Step off and look back at it.
        place(g, V2(Landmarks.liftX + 4, 3))
        XCTAssertTrue(g.story.flags.contains("wren.lift"))
        XCTAssertLessThan(g.liftCar, 0.5, "the cage went down without him")
        sim(g, GameInput(), 6)
        let w = try XCTUnwrap(g.actor("wren"))
        XCTAssertFalse(w.hidden)
        XCTAssertGreaterThan(g.liftCar, 0.5, "and came back up with someone")
        XCTAssertEqual(w.holds(.growTray), 1, "she has somewhere to go and something to carry")
        // Save mid-walk: one Wren, one place, same trays.
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(back.actor("wren")?.pos, g.actor("wren")?.pos)
        XCTAssertEqual(back.actor("wren")?.holds(.growTray), 1)
        XCTAssertEqual(back.actor("wren")?.route.count, g.actor("wren")?.route.count)
        // Follow her: she ends up at Odi's, and the trays end up on Odi's shelf.
        sim(back, GameInput(), 160)
        let at = try XCTUnwrap(back.actor("wren"))
        XCTAssertTrue(back.story.flags.contains("wren.atOdi"), "Wren at \(at.pos)")
        XCTAssertEqual(at.holds(.growTray), 0)
        XCTAssertEqual(back.world.prop("odi.shelf")?.stock.first { $0.id == .growTray }?.count, 1)
        XCTAssertTrue(back.remembers("max", "sawWren"))
    }

    func testOnTheChimneyRouteSomeoneClimbsTheRopeBelowHim() throws {
        let g = chimneyRoute(FixedClock())
        place(g, V2(Landmarks.chimneyTop.x + 5, 3))
        place(g, V2(Landmarks.chimneyTop.x + 4, 3))
        XCTAssertTrue(g.story.flags.contains("wren.chimney"))
        let w = try XCTUnwrap(g.actor("wren"))
        XCTAssertGreaterThan(w.pos.y, 6, "her lamp is below him in the chimney")
        XCTAssertTrue(w.lamp)
        sim(g, GameInput(), 8)
        XCTAssertTrue(g.remembers("wren", "metAtChimney"), "she'll know him later")
        XCTAssertTrue(g.story.flags.contains("wren.seen"))
    }

    // MARK: Mara's own deliveries

    func testMaraTakesFullCansToTransitAndMaxCanCarryOne() {
        let clock = FixedClock()
        let g = helpRoute(clock)
        place(g, V2(Landmarks.liftX, 3)); g.choosePanel("transit.lift", "ride.down"); sim(g, GameInput(), 3)
        g.story.counters["haul.next"] = Int(g.time) + 1
        place(g, V2(60, 9))
        sim(g, GameInput(), 2)
        XCTAssertTrue(g.maraHauling)
        XCTAssertEqual(g.maraHaulKind, "transit")
        sim(g, GameInput(), 5)   // she's filled up at the tap
        XCTAssertTrue(g.maraCansFull)
        // Meet her on the way and take a can.
        place(g, V2(g.mara.pos.x + 0.6, 9))
        XCTAssertEqual(g.context?.id, "can.carry", "Max \(g.max.pos) Mara \(g.mara.pos) cans \(g.maraCans) room \(g.inv.room(for: .fullCan)) busy \(g.max.busy) mode \(g.max.mode)")
        if g.context?.id == "can.carry" { g.performContext() }
        XCTAssertEqual(g.inv.count(.fullCan), 1)
        XCTAssertTrue(g.remembers("mara", "carriedCan"))
        XCTAssertFalse(g.remembers("odi", "carriedCan"), "only Mara saw it")
        XCTAssertEqual(g.maraCans, 1)
        // Her route goes on without waiting; the drop is up on the platform.
        sim(g, GameInput(), 40)
        XCTAssertGreaterThan(g.world.prop("mara.drop")?.stock.first { $0.id == .fullCan }?.count ?? 0, 0, "she left her can at the drop")
        // Max brings his up and sets it down there for his share.
        place(g, V2(Landmarks.liftX, 9)); g.choosePanel("mara.lift", "ride.up"); sim(g, GameInput(), 3)
        g.hydration = 40
        place(g, V2(Landmarks.transitDrop.x, 3))
        XCTAssertEqual(g.context?.id, "can.down")
        g.performContext()
        XCTAssertEqual(g.inv.count(.fullCan), 0)
        XCTAssertEqual(g.hydration, 100, "his share")
    }

    func testDryMaraTakesEmptiesToTheSeep() {
        let clock = FixedClock()
        let g = payRoute(clock)
        place(g, V2(Landmarks.liftX, 3)); g.choosePanel("transit.lift", "ride.down"); sim(g, GameInput(), 3)
        g.story.counters["haul.next"] = Int(g.time) + 1
        place(g, V2(60, 9))
        sim(g, GameInput(), 2)
        XCTAssertEqual(g.maraHaulKind, "seep")
        sim(g, GameInput(), 25)
        XCTAssertLessThan(g.mara.pos.x, 73, "she walks the line west to the seep")
        sim(g, GameInput(), 60)
        XCTAssertFalse(g.maraHauling, "and comes home")
    }

    // MARK: the signal and Odi's beds

    func testTheSignalIsAnsweredFromAcrossTheCavern() {
        let g = Game()
        g.begin()
        g.story.chapter = 4
        g.inv.add(.batteryCell)
        place(g, V2(Landmarks.signalLampX, 3))
        XCTAssertEqual(g.context?.id, "signal")
        g.performContext()
        sim(g, GameInput(), 4.5)
        XCTAssertEqual(g.cine?.kind, "answer")
        XCTAssertEqual(g.cine?.focus?.x ?? 0, Landmarks.odiLamp.x, accuracy: 0.1, "the camera looks across to the answer")
        sim(g, GameInput(), 9)
        XCTAssertNil(g.cine)
        XCTAssertTrue(g.story.isDone("answer", "seen"))
        // And again whenever he flashes it.
        place(g, V2(Landmarks.signalLampX, 3))
        XCTAssertEqual(g.context?.id, "flash.signal")
    }

    func odiReady() -> Game {
        let g = Game()
        g.begin()
        g.story.chapter = 4
        place(g, V2(150, 41))
        XCTAssertEqual(g.story.chapter, 5)
        return g
    }

    func testOdiLampCableOrKeepEachLeaveAWayForward() throws {
        for choice in ["lend", "cable", "keep"] {
            let g = odiReady()
            g.inv.add(.lamp, 1); g.inv.add(.wire, 4); g.inv.add(.fasteners, 2)
            g.startTalk("odi")
            XCTAssertEqual(g.talk?.node, "first")
            g.chooseTalk("beds")
            XCTAssertEqual(g.talk?.node, "beds")
            g.chooseTalk(choice)
            XCTAssertEqual(g.odiBedsLit, ["lend": 2, "cable": 4, "keep": 1][choice], choice)
            // A later visit shows what grew.
            sim(g, GameInput(), 1)
            g.time += 400
            sim(g, GameInput(), 1)
            XCTAssertEqual(g.world.props.filter { $0.id.hasPrefix("odi.bed") && $0.flags.contains("grown") }.count, g.odiBedsLit)
            // Whatever he chose, she tells him the way on.
            g.startTalk("odi")
            XCTAssertEqual(g.talk?.node, "hub")
            XCTAssertTrue(g.talk?.choices.contains { $0.id == "hotel" } ?? false, choice)
            let back = Game.load(try Game.decodeSave(try g.encodeSave()))
            XCTAssertEqual(back.odiBedsLit, g.odiBedsLit)
        }
    }

    func testLentLampComesBackAndOnlyOneCopyExists() {
        let g = odiReady()
        g.inv.add(.lamp, 1)
        g.startTalk("odi"); g.chooseTalk("beds"); g.chooseTalk("lend")
        XCTAssertEqual(g.inv.count(.lamp), 0)
        g.startTalk("odi"); g.chooseTalk("back")
        XCTAssertEqual(g.inv.count(.lamp), 1)
        XCTAssertEqual(g.odiBedsLit, 1)
        g.startTalk("odi")
        XCTAssertFalse(g.talk?.choices.contains { $0.id == "back" } ?? true, "nothing to take back twice")
    }

    func testOldSavePastMaraGetsTheGrowRoomAhead() throws {
        let g = Game()
        g.story.chapter = 4
        g.story.flags.remove("odiRoom1")
        g.world.props.removeAll { WorldGen.odiRoomPropIDs.contains($0.id) }
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(back.story.chapter, 4)
        for id in WorldGen.odiRoomPropIDs { XCTAssertNotNil(back.world.prop(id), id) }
    }
}
