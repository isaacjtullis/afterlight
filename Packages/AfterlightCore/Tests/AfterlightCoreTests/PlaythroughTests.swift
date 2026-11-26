import XCTest
@testable import AfterlightCore

/// A bot that plays the game the way a player does: the wheel, DIG, JUMP and the context button,
/// nothing else. It keeps a log so a failure says exactly where it got stuck.
final class Bot {
    let g: Game
    var log: [String] = []
    var t = 0.0
    init(_ g: Game) { self.g = g }

    func note(_ s: String) { log.append(String(format: "[%.0fs x%.1f y%.1f %@] ", t, g.max.pos.x, g.max.pos.y, "\(g.max.mode)") + s) }
    var trail: String { log.suffix(14).joined(separator: "\n") }

    func step(_ i: GameInput) {
        // A real player eats when hungry and rests when spent.
        g.update(dt: 1 / 60, input: i); _ = g.drainEvents(); t += 1 / 60
    }
    func idle(_ s: Double) { var k = 0.0; while k < s { step(GameInput()); k += 1 / 60 } }

    /// Hold an input until a condition holds. Rests when stamina runs out, like a player would.
    @discardableResult
    func hold(_ i: GameInput, until done: () -> Bool, timeout: Double, _ what: String) -> Bool {
        var k = 0.0
        while !done() && k < timeout {
            if g.max.stamina < 5 && i.dig { idle(6) }
            step(i); k += 1 / 60
        }
        note((done() ? "ok " : "TIMED OUT ") + what)
        return done()
    }

    /// Walk to x, digging through whatever's in the way.
    @discardableResult
    func go(_ x: Double, dig: Bool = false, timeout: Double = 120) -> Bool {
        // Like a player: jump over holes in the floor (unless the goal is down in one).
        var k = 0.0
        while abs(g.max.pos.x - x) >= 0.35 && k < timeout {
            let d = g.max.pos.x < x ? 1 : -1
            let ahead = g.max.pos.x + Double(d) * 0.9
            let hole = g.max.ground && !g.world.solid(ahead, g.max.pos.y + 0.35) && !g.world.solid(ahead, g.max.pos.y + 1.2) && abs(ahead - x) > 0.6
            if g.max.stamina < 5 && dig { idle(6) }
            // A hole in the way: bridge it with a plank if there's wood, else jump it.
            if hole && g.context?.id == "plank" { g.performContext(); note("planked a hole at x\(String(format: "%.1f", ahead))"); idle(0.3); continue }
            step(GameInput(dx: d, dig: dig, jump: hole)); k += 1 / 60
        }
        let ok = abs(g.max.pos.x - x) < 0.35
        note((ok ? "ok " : "TIMED OUT ") + "go to x\(x)")
        return ok && settle()
    }
    @discardableResult func settle() -> Bool { idle(0.4); return true }

    /// Use the context button, but only if it offers what we expect.
    @discardableResult
    func use(_ id: String, wait: Double = 3) -> Bool {
        var k = 0.0
        while g.context?.id != id && k < wait { step(GameInput()); k += 1 / 60 }
        guard g.context?.id == id else { note("expected \(id), button shows \(g.context?.id ?? "nothing")"); return false }
        g.performContext()
        note("used \(id)")
        idle(0.5)
        return true
    }
}

extension Bot {
    /// Tap a row in the panel that's open (the drum, a pump…), like a finger would.
    @discardableResult
    func row(_ panel: String, _ id: String) -> Bool {
        guard let r = g.panel(panel)?.rows.first(where: { $0.id == id }), r.enabled else {
            note("panel \(panel) has no enabled row \(id); rows: \(g.panel(panel)?.rows.map { "\($0.id)\($0.enabled ? "" : "(off)")" } ?? [])")
            return false
        }
        g.choosePanel(panel, id)
        note("tapped \(panel)/\(id)")
        idle(0.3)
        return true
    }

    /// Search or salvage whatever's here and take everything.
    @discardableResult
    func takeAll(_ prop: String) -> Bool {
        var k = 0.0
        while !(g.context?.id.hasSuffix(prop) ?? false) && k < 2 { step(GameInput()); k += 1 / 60 }
        guard let id = g.context?.id, id.hasSuffix(prop) else { note("expected to search \(prop), button shows \(g.context?.id ?? "nothing")"); return false }
        g.performContext(); note("took from \(prop)"); idle(0.4)
        return true
    }

    /// Chapter 1 from a fresh game, up to the flashlight's first look around.
    func playChapterOne() -> Bool {
        g.begin()
        guard go(31.3),
              hold(GameInput(dig: true), until: { self.g.max.pos.x > 37.1 }, timeout: 40, "dig east to the glint") else { return false }
        go(37.5)
        hold(GameInput(down: true), until: { self.g.inv.count(.chargeCrystal) > 0 }, timeout: 4, "dig down to the crystal")
        idle(1)
        hold(GameInput(up: true), until: { self.g.max.pos.y < 30.2 && self.g.max.ground }, timeout: 6, "climb out of the hole")
        guard go(26.2), use("repair") else { return false }
        idle(2)
        guard use("switchOn") else { return false }
        idle(12)
        note("after the first look: sawShaft=\(g.story.flags.contains("sawShaft")) cine=\(g.cine?.kind ?? "none") drumQuest=\(g.waterQuestActive)")
        return g.inv.has(.flashlight) && g.waterQuestActive
    }

    /// Trace the drip, fetch strap and gasket from the old bunk room, clamp it, read the old filter.
    func playDrumRepair() -> Bool {
        guard go(30.7), use("panel:drum"), row("drum", "drum.trace") else { return false }
        idle(4)
        // West through the roots into the old bunk room.
        guard go(17.6, dig: true, timeout: 120), takeAll("washstand") else { return false }
        guard go(16.0), takeAll("bunk.broken") else { return false }
        guard go(30.7, timeout: 120), use("panel:drum"), row("drum", "drum.clamp") else { return false }
        idle(2)
        guard g.quarters.drumSealed else { note("drum not sealed"); return false }
        row("drum", "drum.pour")
        guard row("drum", "drum.intake") else { return false }
        idle(4)
        // Dad's map: the corner at the bench, the sketch under the grate.
        guard go(26.25), use("mapClip") else { return false }
        idle(4)
        guard go(27.3), use("grate") else { return false }
        idle(2)
        return g.available(.sketch) > 0
    }
}

extension Bot {
    /// Route A: the long dig. Down from the tunnel mouth through the store's caved-in roof.
    func playStoreByDigging() -> Bool {
        guard go(32.5, timeout: 60) else { return false }
        hold(GameInput(down: true), until: { self.g.story.flags.contains("foundStore") }, timeout: 200, "dig down into Store B")
        guard g.story.flags.contains("foundStore") else { return false }
        return fetchAndFit(back: .digUp)
    }

    enum Way { case digUp, walk }

    /// Take both essentials off the shelf, get home, fit the filter, prime it, draw the first cup.
    func fetchAndFit(back: Way) -> Bool {
        guard let shelf = g.world.prop("store.shelf") else { return false }
        guard go(shelf.pos.x, timeout: 30), takeAll("store.shelf") else { return false }
        guard g.available(.filterAssembly) > 0 else { note("no filter assembly in the bag"); return false }
        note("carrying can=\(g.available(.waterCan)) filter=\(g.available(.filterAssembly))")
        switch back {
        case .digUp:
            guard go(32.5, timeout: 30) else { return false }
            let x = g.max.pos.x, y = g.max.pos.y
            note("at the rubble: L=\(g.world.solid(x - 0.95, y - 0.6)) R=\(g.world.solid(x + 0.95, y - 0.6)) head=\(g.world.solid(x, y - 2.2)) col=\((30...46).map { g.world.m(Int(x), $0).solid ? "#" : "." }.joined()) left=\((30...46).map { g.world.m(Int(x) - 1, $0).solid ? "#" : "." }.joined()) probe=\(stride(from: y - 1, to: y - 17, by: -1.0).map { yy in "\(Int(yy)):\(g.world.solid(x, yy - 1.8) ? "C" : "")\(!g.world.solid(x - 1, yy - 0.5) && g.world.solid(x - 1, yy + 0.2) ? "L" : "")" }.joined(separator: " ")) shaftClimb=\(g.tryShaftClimb()) climbs=\(g.world.climbs.filter { $0.kind == .foothold }.map { "\($0.x),\($0.top)-\($0.bottom)" })")
            hold(GameInput(up: true), until: { self.g.max.pos.y < 31 && self.g.max.mode == .walk }, timeout: 60, "climb back up the dig")
        case .walk:
            guard go(Double(Landmarks.serviceShaft.c1), timeout: 60) else { return false }
            hold(GameInput(up: true), until: { self.g.max.pos.y < 31 && self.g.max.mode == .walk }, timeout: 40, "climb the service ladder")
        }
        guard g.max.pos.y < 31 else { note("didn't make it back up"); return false }
        if back == .digUp {
            // Cover the hole by the door with a plank, the way you'd want to before walking past it again.
            go(31.3)
            hold(GameInput(dx: 1), until: { self.g.context?.id == "plank" || self.g.max.pos.x > 32.3 }, timeout: 3, "edge of my own hole")
            if g.context?.id == "plank" { g.performContext(); note("planked over the hole") } else { note("no plank offered: \(g.context?.id ?? "nothing") wood=\(g.inv.wood)") }
        }
        guard go(30.7, timeout: 120), use("panel:drum") else { return false }
        row("drum", "drum.can")
        guard row("drum", "drum.fit") else { return false }
        idle(2.5)
        guard row("drum", "drum.prime") else { return false }
        idle(4.5)
        guard row("drum", "drum.cup") else { return false }
        idle(1)
        return true
    }
}

final class PlaythroughTests: XCTestCase {

    /// Route B: down the service ladder, planks over the broken span, both essentials home in one trip.
    func testWaterMissionByTheServiceWalk() {
        let g = Game()
        let b = Bot(g)
        XCTAssertTrue(b.playChapterOne(), b.trail)
        XCTAssertTrue(b.playDrumRepair(), b.trail)
        XCTAssertGreaterThanOrEqual(g.inv.wood, 15, "the roots gave enough wood for three planks\n" + b.trail)
        // East to the lift pit, through the plank cover, down the ladder.
        XCTAssertTrue(b.go(36), b.trail)
        XCTAssertTrue(b.go(Double(Landmarks.serviceShaft.c1), dig: true, timeout: 200), b.trail)
        b.hold(GameInput(down: true), until: { g.max.pos.y > 31 || g.max.mode == .climb }, timeout: 6, "dig through the plank cover")
        b.hold(GameInput(down: true), until: { g.max.pos.y > Double(Landmarks.serviceWalk.floor) - 0.3 && g.max.mode == .walk }, timeout: 20, "climb down the service ladder")
        XCTAssertTrue(g.story.flags.contains("lm.pipe"), "passed the forked pipe\n" + b.trail)
        // West along the walk to the broken span: lay planks across it.
        let sw = Landmarks.serviceWalk
        b.hold(GameInput(dx: -1), until: { g.max.pos.x < Double(sw.gap1) + 1.6 }, timeout: 10, "walk to the broken span")
        for _ in 0..<4 where g.world.m(sw.gap0, sw.floor) != .plank {
            b.hold(GameInput(dx: -1), until: { g.context?.id == "plank" }, timeout: 3, "edge of the gap")
            if g.context?.id == "plank" { g.performContext(); b.note("laid a plank") }
            b.idle(0.4)
        }
        XCTAssertTrue((sw.gap0...sw.gap1).contains { g.world.m($0, sw.floor) == .plank }, "planks over the span\n" + b.trail)
        XCTAssertTrue(b.go(Double(Landmarks.storeB.x1) - 1, timeout: 20), b.trail)
        XCTAssertTrue(g.story.flags.contains("foundStore"), b.trail)
        XCTAssertTrue(g.story.flags.contains("lm.stripes") && g.story.flags.contains("lm.mark"), "saw every landmark\n" + b.trail)
        XCTAssertTrue(b.fetchAndFit(back: .walk), b.trail)
        XCTAssertTrue(g.quarters.filterFitted, b.trail)
        XCTAssertGreaterThan(g.quarters.clean, 6, "the sealed can went into the drum too\n" + b.trail)
    }

    /// From the candle to a lit home, playing only with the controls.
    func testFreshGameToALitHome() {
        let g = Game()
        let b = Bot(g)
        b.playToMaintenance(self)
        XCTAssertNil(g.talk)
    }
}

extension Bot {
    /// From the candle to the maintenance room, playing only with the controls.
    func playToMaintenance(_ t: XCTestCase) {
        let g = self.g
        let b = self

        XCTAssertTrue(b.playChapterOne(), b.trail)
        XCTAssertTrue(b.playDrumRepair(), b.trail)
        XCTAssertTrue(b.playStoreByDigging(), b.trail)
        XCTAssertTrue(g.quarters.filterFitted, "the first clean cup\n" + b.trail)
        XCTAssertTrue(g.story.isDone("drum", "cup"), b.trail)
        b.go(26.0)
        XCTAssertTrue(b.use("tryUp"), b.trail)
        b.idle(10)
        XCTAssertEqual(g.story.chapter, 2, b.trail)

        // Power for home: look, hammer it loose, fetch the cell from the lift car, fit it.
        XCTAssertTrue(b.go(21.55), b.trail)
        XCTAssertTrue(b.use("genLook"), b.trail)
        b.idle(1)
        XCTAssertTrue(b.use("genFree"), b.trail)
        b.idle(2)
        XCTAssertTrue(b.go(36), b.trail)
        XCTAssertTrue(b.go(Landmarks.liftCarPos.x - 0.6, dig: true, timeout: 200), b.trail)
        b.idle(0.5)
        if let id = g.context?.id, id.hasPrefix("search:") || id.hasPrefix("salvage:") { g.performContext(); b.note("searched the lift car") }
        b.idle(0.5)
        XCTAssertGreaterThan(g.available(.batteryCell), 0, "the lift car's battery cell is in the bag\n" + b.trail)
        XCTAssertTrue(b.go(21.55, timeout: 200), b.trail)
        XCTAssertTrue(b.use("genPower"), b.trail)
        b.idle(2)
        XCTAssertTrue(g.story.flags.contains("shelterLit"), "the shelter is lit\n" + b.trail)
        XCTAssertTrue(g.story.isDone("homeLight", "fix"), b.trail)

        // Pack food from the pantry.
        b.go(28.3)
        g.packRation()
        XCTAssertTrue(g.packedFood)

        // The ascent: the grip from the workshop locker, the tooth already came with the lift car.
        XCTAssertTrue(b.go(20.9), b.trail)
        if let id = g.context?.id, id.hasPrefix("search:") || id.hasPrefix("salvage:") { g.performContext(); b.note("searched \(id)") }
        b.idle(0.5)
        XCTAssertGreaterThan(g.available(.spareGrip), 0, "the spare grip from the workshop locker\n" + b.trail)
        XCTAssertGreaterThan(g.available(.liftTooth), 0, "the drive tooth from the lift car\n" + b.trail)
        XCTAssertTrue(b.go(26.2), b.trail)
        g.craft("pick"); g.craft("ladder")
        XCTAssertTrue(g.inv.has(.shortPick), "built the short pick\n" + b.trail)
        XCTAssertEqual(g.inv.count(.ladderSection), 1, "built the ladder\n" + b.trail)
        b.go(26.0)
        XCTAssertTrue(b.use("placeLadder"), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 16 }, timeout: 12, "climb to the seam")
        for _ in 0..<12 where !g.story.flags.contains("hatchOpen") {
            b.hold(GameInput(up: true, dig: true), until: { g.story.flags.contains("hatchOpen") }, timeout: 1.5, "pick the seam")
            b.hold(GameInput(up: true), until: { false }, timeout: 1, "keep climbing")
        }
        XCTAssertTrue(g.story.flags.contains("hatchOpen"), b.trail)
        b.hold(GameInput(up: true), until: { g.max.mode == .walk && g.max.pos.y < 9.5 }, timeout: 8, "climb into maintenance")
        b.idle(1)
        XCTAssertEqual(g.story.chapter, 3, "into the maintenance room\n" + b.trail)
    }
}

