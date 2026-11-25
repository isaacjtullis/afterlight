import XCTest
@testable import AfterlightCore

/// Chapter 3 acceptance tests: Mara's outpost, the three ways up, shared jobs, agreements and water.
final class MaraTests: XCTestCase {

    /// A chapter-3 game with the warm passage dug through to the outpost.
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

    /// Stands at a spot and uses whatever the contextual button offers there.
    func use(_ g: Game, at p: V2, expect id: String, file: StaticString = #filePath, line: UInt = #line) {
        place(g, p)
        XCTAssertEqual(g.context?.id, id, "at \(p)", file: file, line: line)
        if g.context?.id == id { g.performContext() }
        sim(g, GameInput(), 2.5)
    }

    func row(_ g: Game, _ panel: String, _ id: String) -> PanelRow? { g.panel(panel)?.rows.first { $0.id == id } }

    func fetchValveAndClearIntake(_ g: Game) {
        use(g, at: V2(84.4, 14), expect: "salvage:sump.valve")
        XCTAssertEqual(g.inv.count(.pressureValve), 1)
        use(g, at: V2(81.2, 14), expect: "clearIntake")
        XCTAssertTrue(g.story.flags.contains("intakeClear"))
    }

    func deliverValve(_ g: Game) {
        place(g, V2(78.3, 9))
        XCTAssertEqual(g.context?.id, "panel:mara.pump")
        XCTAssertNotNil(row(g, "mara.pump", "deliver.job.water.c.valve"))
        g.choosePanel("mara.pump", "deliver.job.water.c.valve")
    }

    func rideUp(_ g: Game) {
        place(g, V2(Landmarks.liftX, 9))
        XCTAssertEqual(g.context?.id, "panel:mara.lift")
        XCTAssertNotNil(row(g, "mara.lift", "ride.up"))
        g.choosePanel("mara.lift", "ride.up")
        sim(g, GameInput(), 3)
    }

    // MARK: the encounter

    func testPumpIsHeardBeforeTheDryTapAndStalledLiftAreSeen() {
        let clock = FixedClock()
        let g = outpost(clock)
        place(g, V2(55, 9))
        sim(g, GameInput(), 7)
        XCTAssertTrue(g.story.flags.contains("said.knock"))
        XCTAssertFalse(g.story.flags.contains("said.tap"))
        walk(g, to: 75.5)
        XCTAssertTrue(g.story.flags.contains("said.tap"))
        XCTAssertFalse(g.story.flags.contains("said.lift"))
        walk(g, to: 83)
        XCTAssertTrue(g.story.flags.contains("said.lift"))
        XCTAssertEqual(g.panel("mara.tap")?.lines.first, "Dry. Not a drop.")
    }

    // MARK: route 1 — collaborate

    func testHelpMaraThenReturnToARunningPumpAndAHonouredLift() throws {
        let clock = FixedClock()
        let g = outpost(clock)
        use(g, at: V2(79.6, 9), expect: "panel:mara")
        let offer = row(g, "mara", "offer.collab")
        XCTAssertNotNil(offer?.detail, "terms are shown before agreeing")
        g.choosePanel("mara", "offer.collab")
        let deal = try XCTUnwrap(g.agreement(MaraDeal.water))
        XCTAssertEqual(deal.terms.map(\.id), ["t.valve", "t.intake", "t.install", "t.water", "t.lift"])
        XCTAssertEqual(deal.owedToMax, ["A working lift up to the transit level"])
        XCTAssertEqual(g.activeJobID(for: "mara"), MaraDeal.waterJob, "Mara takes one job at a time: water first")

        fetchValveAndClearIntake(g)
        deliverValve(g)
        XCTAssertEqual(g.inv.count(.pressureValve), 0)
        XCTAssertEqual(g.job(MaraDeal.waterJob)?.reserved, [ItemStack(.pressureValve)])
        XCTAssertEqual(g.job(MaraDeal.waterJob)?.status, .working)
        XCTAssertTrue(g.job(MaraDeal.liftJob)?.blocker?.contains("first") ?? false)

        // Close the game and come back much later.
        let data = try g.encodeSave()
        clock.now = clock.now.addingTimeInterval(3600)
        let h = Game.load(try Game.decodeSave(data), clock: { clock.now })
        XCTAssertTrue(h.waterOn)
        XCTAssertTrue(h.liftRepaired, "the lift repair was honoured while Max was away")
        XCTAssertEqual(h.agreement(MaraDeal.water)?.state, .fulfilled)
        XCTAssertEqual(h.job(MaraDeal.waterJob)?.installed, [ItemStack(.pressureValve)])
        XCTAssertEqual(h.panel("mara.tap")?.lines.first, "Running clear. Mara’s beds are drinking.")

        rideUp(h)
        XCTAssertEqual(h.max.pos.y, 3, accuracy: 0.05)
        XCTAssertEqual(h.story.chapter, 4)
        XCTAssertTrue(h.story.flags.contains("up.lift"))
    }

    // MARK: route 2 — trade

    func testPayForTheLiftRideItAndComeBackToHelpWithWaterLater() throws {
        let clock = FixedClock()
        let g = outpost(clock)
        g.inv.add(.pipe, 1); g.inv.add(.wire, 2); g.inv.add(.fasteners, 4)
        place(g, V2(79.6, 9))
        XCTAssertTrue(row(g, "mara", "offer.trade")?.detail?.contains("Pipe length ×1, Wire ×2, Fasteners ×4") ?? false,
                      "the price is visible before committing")
        g.choosePanel("mara", "offer.trade")
        XCTAssertEqual(g.job(MaraDeal.liftJob)?.status, .open)
        for i in 0..<3 { g.choosePanel("mara.lift", "deliver.job.lift.c.pay\(i)") }
        XCTAssertEqual(g.inv.count(.pipe) + g.inv.count(.wire) + g.inv.count(.fasteners), 0)
        XCTAssertEqual(g.agreement(MaraDeal.lift)?.terms.first?.state, .kept)
        XCTAssertEqual(g.job(MaraDeal.liftJob)?.status, .working)

        clock.now = clock.now.addingTimeInterval(MaraDeal.liftSeconds + 1)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.liftRepaired)
        XCTAssertFalse(g.waterOn, "the dry pump stays dry and visible")
        XCTAssertEqual(g.panel("mara.pump")?.lines.first?.hasPrefix("Knocking"), true)

        rideUp(g)
        XCTAssertEqual(g.story.chapter, 4)
        place(g, V2(Landmarks.liftX, 3))
        XCTAssertEqual(g.context?.id, "panel:transit.lift")
        g.choosePanel("transit.lift", "ride.down")
        sim(g, GameInput(), 3)
        XCTAssertEqual(g.max.pos.y, 9, accuracy: 0.05)

        // Later: help with the water after all.
        place(g, V2(79.6, 9))
        XCTAssertNotNil(row(g, "mara", "offer.collab"))
        XCTAssertNil(row(g, "mara", "offer.trade"))
        g.choosePanel("mara", "offer.collab")
        XCTAssertEqual(g.story.coop.jobs.filter { $0.id == MaraDeal.liftJob }.count, 1, "no second lift job")
        fetchValveAndClearIntake(g)
        deliverValve(g)
        clock.now = clock.now.addingTimeInterval(MaraDeal.installSeconds + 1)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.waterOn)
        XCTAssertEqual(g.inv.count(.trailMeal), 2)
        g.advanceSharedJobs(to: clock.now.addingTimeInterval(500))
        XCTAssertEqual(g.inv.count(.trailMeal), 2, "a reward is paid once")
    }

    // MARK: route 3 — go around

    func testDeclineTheDealAndClimbTheOldChimney() {
        let clock = FixedClock()
        let g = outpost(clock)
        place(g, V2(79.6, 9))
        XCTAssertTrue(row(g, "mara", "offer.decline")?.detail?.contains("Rope ×2") ?? false, "the route's cost is shown first")
        g.choosePanel("mara", "offer.decline")
        XCTAssertTrue(g.story.coop.agreements.isEmpty)

        place(g, V2(71.0, 9))
        XCTAssertEqual(g.context?.id, "panel:chimney")
        XCTAssertEqual(row(g, "chimney", "chimney.rig")?.enabled, false, "can't commit without the rope")
        g.inv.add(.rope, 2); g.inv.add(.fasteners, 2)
        XCTAssertEqual(row(g, "chimney", "chimney.rig")?.enabled, true)
        g.choosePanel("chimney", "chimney.rig")
        XCTAssertEqual(g.inv.count(.rope), 0)
        sim(g, GameInput(), 1.5)
        sim(g, GameInput(up: true), 6)
        sim(g, GameInput(), 1)
        XCTAssertEqual(g.max.mode, .walk)
        XCTAssertLessThan(g.max.pos.y, 4.0, "on the platform at \(g.max.pos)")
        XCTAssertEqual(g.story.chapter, 4)
        XCTAssertTrue(g.story.flags.contains("up.chimney"))
    }

    // MARK: reserved parts

    func testCancelBeforeInstallationReclaimsDeliveredPartsExactlyOnce() throws {
        let clock = FixedClock()
        let g = outpost(clock)
        g.inv.add(.pipe, 1)
        place(g, V2(79.6, 9))
        g.choosePanel("mara", "offer.trade")
        g.choosePanel("mara.lift", "deliver.job.lift.c.pay0")
        XCTAssertEqual(g.inv.count(.pipe), 0)
        XCTAssertNotNil(row(g, "mara.lift", "cancel.lift")?.confirm, "breaking a deal asks first")
        g.choosePanel("mara.lift", "cancel.lift")
        XCTAssertEqual(g.agreement(MaraDeal.lift)?.state, .broken)
        XCTAssertNotNil(row(g, "mara.lift", "reclaim.lift"))

        // Reloading doesn't duplicate the reclaimable part.
        let h = Game.load(try Game.decodeSave(try g.encodeSave()), clock: { clock.now })
        XCTAssertEqual(h.reclaim(job: MaraDeal.liftJob), [ItemStack(.pipe)])
        XCTAssertEqual(h.inv.count(.pipe), 1)
        XCTAssertEqual(h.reclaim(job: MaraDeal.liftJob), [])
        XCTAssertEqual(h.inv.count(.pipe), 1)
        XCTAssertNil(row(h, "mara.lift", "reclaim.lift"))
        let k = Game.load(try Game.decodeSave(try h.encodeSave()), clock: { clock.now })
        XCTAssertEqual(k.reclaim(job: MaraDeal.liftJob), [])
        XCTAssertEqual(k.inv.count(.pipe), 1)
    }

    func testInstalledPartsStayWhenAJobIsFinished() {
        let clock = FixedClock()
        let g = outpost(clock)
        g.inv.add(.pipe, 1); g.inv.add(.wire, 2); g.inv.add(.fasteners, 4)
        g.choosePanel("mara", "offer.trade")
        for i in 0..<3 { g.choosePanel("mara.lift", "deliver.job.lift.c.pay\(i)") }
        g.advanceSharedJobs(to: clock.now.addingTimeInterval(1000))
        g.cancelJob(MaraDeal.liftJob, by: "max")
        XCTAssertEqual(g.job(MaraDeal.liftJob)?.status, .done)
        XCTAssertEqual(g.job(MaraDeal.liftJob)?.installed.count, 3)
        XCTAssertEqual(g.reclaim(job: MaraDeal.liftJob), [])
    }

    // MARK: closing the game

    func testCloseMidRepairAndAtCompletionThenReopen() throws {
        let clock = FixedClock()
        let g = outpost(clock)
        g.choosePanel("mara", "offer.collab")
        fetchValveAndClearIntake(g)
        deliverValve(g)
        let t0 = clock.now

        clock.now = t0.addingTimeInterval(30)
        g.advanceSharedJobs(to: clock.now)
        let mid = try g.encodeSave()

        let a = Game.load(try Game.decodeSave(mid), clock: { clock.now })
        XCTAssertEqual(a.job(MaraDeal.waterJob)?.status, .working)
        XCTAssertEqual(a.job(MaraDeal.waterJob)?.workDone ?? 0, 30, accuracy: 0.5)

        clock.now = t0.addingTimeInterval(200)
        let b = Game.load(try Game.decodeSave(mid), clock: { clock.now })
        XCTAssertTrue(b.waterOn)
        XCTAssertEqual(b.job(MaraDeal.liftJob)?.workDone ?? 0, 80, accuracy: 0.5, "the lift starts when the water finishes, not before")

        clock.now = t0.addingTimeInterval(1000)
        b.advanceSharedJobs(to: clock.now)
        let done = try b.encodeSave()
        let c = Game.load(try Game.decodeSave(done), clock: { clock.now })
        let d = Game.load(try Game.decodeSave(try c.encodeSave()), clock: { clock.now.addingTimeInterval(9999) })
        for x in [c, d] {
            XCTAssertTrue(x.waterOn && x.liftRepaired)
            XCTAssertEqual(x.story.coop.jobs.count, 2)
            XCTAssertEqual(x.story.coop.appliedEffects, ["job.job.water", "job.job.lift"])
            XCTAssertEqual(x.job(MaraDeal.waterJob)?.installed, [ItemStack(.pressureValve)])
            XCTAssertEqual(x.job(MaraDeal.waterJob)?.reserved, [])
            XCTAssertEqual(x.inv, b.inv)
            XCTAssertEqual(x.trust("mara"), b.trust("mara"))
        }
    }

    // MARK: blocked route

    func testBlockedRoutePausesWithTheReasonAndResumes() throws {
        let clock = FixedClock()
        let g = outpost(clock)
        g.choosePanel("mara", "offer.collab")
        fetchValveAndClearIntake(g)
        deliverValve(g)
        let t0 = clock.now
        clock.now = t0.addingTimeInterval(10)
        place(g, V2(85.6, 9))
        XCTAssertEqual(g.context?.id, "panel:sump.hatch")
        g.mara.pos = Landmarks.maraHome
        g.choosePanel("sump.hatch", "hatch.bar")
        XCTAssertFalse(g.hatchOpen)
        XCTAssertEqual(g.job(MaraDeal.waterJob)?.status, .paused)
        XCTAssertEqual(g.job(MaraDeal.waterJob)?.workDone ?? 0, 10, accuracy: 0.5)

        clock.now = t0.addingTimeInterval(500)
        let h = Game.load(try Game.decodeSave(try g.encodeSave()), clock: { clock.now })
        XCTAssertEqual(h.job(MaraDeal.waterJob)?.status, .paused)
        XCTAssertEqual(h.job(MaraDeal.waterJob)?.blocker, "The sump hatch is barred shut. Mara can’t get down to the intake.")
        XCTAssertEqual(h.job(MaraDeal.waterJob)?.workDone ?? 0, 10, accuracy: 0.5)
        XCTAssertTrue(h.panel("mara.pump")?.rows.contains { $0.label.contains("barred shut") } ?? false, "the obstacle is shown")

        h.choosePanel("sump.hatch", "hatch.open")
        clock.now = t0.addingTimeInterval(500 + 50)
        h.advanceSharedJobs(to: clock.now)
        XCTAssertEqual(h.job(MaraDeal.waterJob)?.workDone ?? 0, 60, accuracy: 0.5)
        clock.now = t0.addingTimeInterval(500 + 111)
        h.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(h.waterOn)
    }

    func testTheSumpAlwaysHasAWayOut() {
        let clock = FixedClock()
        let g = outpost(clock)
        g.choosePanel("sump.hatch", "hatch.bar")
        place(g, V2(85.3, 14))
        // From below, the hatch still opens.
        let p = g.panel("sump.hatch")
        XCTAssertEqual(p?.rows.first?.id, "hatch.open")
        g.mara.pos = V2(81.6, 14)
        g.choosePanel("sump.hatch", "hatch.open")
        XCTAssertEqual(row(g, "sump.hatch", "hatch.bar")?.enabled, false, "nobody can be barred in")
    }

    // MARK: water

    func testRedirectWaterShowsTheCostAndRestoringItKeepsTheBrokenDeal() throws {
        let clock = FixedClock()
        let g = outpost(clock)
        g.choosePanel("mara", "offer.collab")
        fetchValveAndClearIntake(g)
        deliverValve(g)
        clock.now = clock.now.addingTimeInterval(MaraDeal.installSeconds + 10)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.waterOn)
        XCTAssertFalse(g.homeWater)

        let home = try XCTUnwrap(row(g, "mara.pump", "route.home"))
        XCTAssertTrue(home.detail?.contains("Mara’s tap and beds: dry") ?? false, "who loses is shown")
        XCTAssertTrue(home.detail?.contains("Your home tank: filling") ?? false, "who gains is shown")
        XCTAssertNotNil(home.confirm)
        g.choosePanel("mara.pump", "route.home")
        XCTAssertEqual(g.story.coop.water.outpostTapFlow, 0)
        XCTAssertTrue(g.homeWater)
        XCTAssertEqual(g.panel("mara.tap")?.lines.first, "Dry. The water’s going somewhere else.")
        XCTAssertEqual(g.agreement(MaraDeal.water)?.state, .broken)
        XCTAssertEqual(g.agreement(MaraDeal.water)?.terms.first { $0.id == "t.water" }?.state, .broken)
        XCTAssertFalse(g.evidence(heldBy: "mara").isEmpty)
        XCTAssertEqual(g.job(MaraDeal.liftJob)?.blocker, "Mara won’t finish your lift while her tap’s dry.")
        let liftDone = g.job(MaraDeal.liftJob)?.workDone ?? 0

        clock.now = clock.now.addingTimeInterval(300)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertEqual(g.job(MaraDeal.liftJob)?.workDone ?? 0, liftDone, accuracy: 0.01)

        XCTAssertNil(row(g, "mara.pump", "route.outpost")?.confirm, "putting water back needs no confirmation")
        g.choosePanel("mara.pump", "route.outpost")
        XCTAssertEqual(g.story.coop.water.outpostTapFlow, 1)
        let deal = try XCTUnwrap(g.agreement(MaraDeal.water))
        XCTAssertEqual(deal.state, .broken, "restoring the flow doesn't erase the broken agreement")
        XCTAssertTrue(deal.log.contains("Max turned the water back to the outpost."))
        XCTAssertTrue(deal.terms.first { $0.id == "t.water" }?.note?.contains("Later restored") ?? false)
        XCTAssertEqual(deal.owedToMax, ["A working lift up to the transit level"], "what Max is owed is preserved")

        clock.now = clock.now.addingTimeInterval(MaraDeal.liftSeconds)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.liftRepaired, "Mara still keeps her side once the water's back")
        XCTAssertEqual(g.agreement(MaraDeal.water)?.state, .broken)
    }

    // MARK: ownership and evidence

    func testTakingMarasSpareIsNotSalvageAndBlameNeedsEvidence() {
        let clock = FixedClock()
        // Seen.
        let g = outpost(clock)
        place(g, V2(82.4, 9))
        XCTAssertEqual(g.context?.id, "panel:mara.shelf")
        XCTAssertNotNil(row(g, "mara.shelf", "take.spare")?.confirm, "taking supplies asks first")
        g.choosePanel("mara.shelf", "take.spare")
        XCTAssertEqual(g.holding("mara", .pressureValve), 1)
        XCTAssertEqual(g.evidence(heldBy: "mara").map(\.id), ["saw.spare"])
        XCTAssertTrue(g.panel("mara")?.lines.first?.contains("watched you take") ?? false)
        g.choosePanel("mara", "return.spare")
        XCTAssertEqual(g.holding("mara", .pressureValve), 0)
        XCTAssertEqual(g.inv.count(.pressureValve), 0)
        XCTAssertEqual(g.world.prop("mara.shelf")?.stock, [ItemStack(.pressureValve)])

        // Unseen: Mara notices it's gone but doesn't blame anyone.
        let h = outpost(clock)
        h.mara.pos = V2(81.6, 14)
        place(h, V2(82.4, 9))
        h.mara.pos = V2(81.6, 14)
        h.choosePanel("mara.shelf", "take.spare")
        XCTAssertTrue(h.evidence(heldBy: "mara").isEmpty)
        h.mara.pos = Landmarks.maraHome
        XCTAssertTrue(h.panel("mara")?.lines.first?.contains("not saying it was you") ?? false)

        // Using it in her own pump gives it away.
        h.choosePanel("mara", "offer.collab")
        h.choosePanel("mara.pump", "deliver.job.water.c.valve")
        XCTAssertEqual(h.evidence(heldBy: "mara").map(\.id), ["spare.inPump"])
        XCTAssertEqual(h.holding("mara", .pressureValve), 0)
    }

    func testMaraWorksOneJobAtATime() {
        let clock = FixedClock()
        let g = outpost(clock)
        g.inv.add(.pipe, 1); g.inv.add(.wire, 2); g.inv.add(.fasteners, 4)
        g.choosePanel("mara", "offer.trade")
        g.choosePanel("mara", "offer.collab")
        for i in 0..<3 { g.choosePanel("mara.lift", "deliver.job.lift.c.pay\(i)") }
        fetchValveAndClearIntake(g)
        deliverValve(g)
        XCTAssertEqual(g.story.coop.jobs.filter { $0.status == .working }.count, 1)
        XCTAssertEqual(g.job(MaraDeal.waterJob)?.blocker, "Mara is on “Repair the lift” first.")
        clock.now = clock.now.addingTimeInterval(MaraDeal.liftSeconds + MaraDeal.installSeconds + 1)
        g.advanceSharedJobs(to: clock.now)
        XCTAssertTrue(g.liftRepaired && g.waterOn)
    }

    // MARK: the whole chapter, by touch, from a fresh save

    /// Plays chapter 3 using only what the touch controls send: hold-to-walk, DIG, ▲, and taps on
    /// context buttons and panel rows. Starts from a fresh save made on arriving in the maintenance room.
    func testWholeChapterWithTouchControlsFromAFreshSave() throws {
        let clock = FixedClock()
        let fresh = Game()
        fresh.clock = { clock.now }
        fresh.begin()
        fresh.story.chapter = 2
        fresh.story.flags.formUnion(["ordersOK", "hatchOpen", "flashOn", "sawShaft", "triedUp"])
        fresh.inv.belt.append(.flashlight)
        fresh.max.pos = V2(30, 9)
        sim(fresh, GameInput(), 1)
        XCTAssertEqual(fresh.story.chapter, 3)
        let g = Game.load(try Game.decodeSave(try fresh.encodeSave()), clock: { clock.now })

        func hold(_ input: GameInput, until done: () -> Bool, timeout: Double) {
            var t = 0.0
            while !done() && t < timeout {
                if g.max.stamina < 4 && input.dig { sim(g, GameInput(), 5) }
                g.update(dt: 1 / 60, input: input); _ = g.drainEvents(); t += 1 / 60
            }
        }
        func tapContext(_ id: String) {
            XCTAssertEqual(g.context?.id, id, "at \(g.max.pos)")
            if g.context?.id == id { g.performContext() }
        }

        // Dig the warm passage east to the outpost door.
        hold(GameInput(dx: 1), until: { g.max.pos.x > 34.3 }, timeout: 10)
        hold(GameInput(dx: 1, dig: true), until: { g.max.pos.x > 74 }, timeout: 400)
        XCTAssertGreaterThan(g.max.pos.x, 74, "dug through at \(g.max.pos)")
        XCTAssertEqual(g.max.pos.y, 9, accuracy: 0.2)

        // Meet Mara and agree to help.
        hold(GameInput(dx: 1), until: { g.nearMara }, timeout: 10)
        tapContext("panel:mara")
        g.choosePanel("mara", "offer.collab")

        // Down the open hatch into the sump, valve, intake.
        hold(GameInput(dx: 1), until: { g.max.pos.y > 13 }, timeout: 10)
        hold(GameInput(dx: -1), until: { abs(g.max.pos.x - 84.4) < 0.8 }, timeout: 6)
        sim(g, GameInput(), 0.3)
        tapContext("salvage:sump.valve")
        sim(g, GameInput(), 0.5)
        hold(GameInput(dx: -1), until: { abs(g.max.pos.x - 81.2) < 0.8 }, timeout: 6)
        sim(g, GameInput(), 0.3)
        tapContext("clearIntake")
        sim(g, GameInput(), 2.5)

        // Back up the rungs and hand over the valve.
        hold(GameInput(dx: 1), until: { g.max.pos.x > 86.2 }, timeout: 6)
        hold(GameInput(up: true), until: { g.max.mode == .walk && g.max.pos.y < 9.2 }, timeout: 8)
        XCTAssertEqual(g.max.pos.y, 9, accuracy: 0.2, "climbed out at \(g.max.pos)")
        hold(GameInput(dx: -1), until: { abs(g.max.pos.x - 78.3) < 0.6 }, timeout: 8)
        sim(g, GameInput(), 0.3)
        tapContext("panel:mara.pump")
        g.choosePanel("mara.pump", "deliver.job.water.c.valve")

        // Go to work; come back later.
        clock.now = clock.now.addingTimeInterval(8 * 3600)
        let back = Game.load(try Game.decodeSave(try g.encodeSave()), clock: { clock.now })
        XCTAssertTrue(back.waterOn && back.liftRepaired)
        var t = 0.0
        while abs(back.max.pos.x - Landmarks.liftX) > 0.5 && t < 8 { back.update(dt: 1 / 60, input: GameInput(dx: back.max.pos.x < Landmarks.liftX ? 1 : -1)); _ = back.drainEvents(); t += 1 / 60 }
        sim(back, GameInput(), 0.3)
        XCTAssertEqual(back.context?.id, "panel:mara.lift")
        back.performContext()
        back.choosePanel("mara.lift", "ride.up")
        sim(back, GameInput(), 3)
        XCTAssertEqual(back.story.chapter, 4)
    }
}
