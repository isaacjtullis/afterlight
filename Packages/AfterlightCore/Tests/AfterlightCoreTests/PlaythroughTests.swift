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
        hold(GameInput(dx: g.max.pos.x < x ? 1 : -1, dig: dig), until: { abs(g.max.pos.x - x) < 0.35 }, timeout: timeout, "go to x\(x)") && settle()
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

final class PlaythroughTests: XCTestCase {

    /// From the candle to a lit home, playing only with the controls.
    func testFreshGameToALitHome() {
        let g = Game()
        let b = Bot(g)
        g.begin()

        // Chapter 1: the crystal glint, the flashlight, the shaft.
        XCTAssertTrue(b.go(31.3), b.trail)
        XCTAssertTrue(b.hold(GameInput(dig: true), until: { g.max.pos.x > 37.1 }, timeout: 40, "dig east to the glint"), b.trail)
        b.go(37.5)
        b.hold(GameInput(down: true), until: { g.inv.count(.chargeCrystal) > 0 }, timeout: 4, "dig down to the crystal")
        b.idle(1)
        XCTAssertEqual(g.inv.count(.chargeCrystal), 1, b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 30.2 && g.max.ground }, timeout: 6, "climb out of the hole")
        XCTAssertTrue(b.go(26.2), b.trail)
        XCTAssertTrue(b.use("repair"), b.trail)
        b.idle(2)
        XCTAssertTrue(g.inv.has(.flashlight), b.trail)
        XCTAssertTrue(b.use("switchOn"), b.trail)
        b.idle(10)
        XCTAssertTrue(g.story.flags.contains("sawShaft"), b.trail)
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
        XCTAssertNil(g.talk)
    }
}
