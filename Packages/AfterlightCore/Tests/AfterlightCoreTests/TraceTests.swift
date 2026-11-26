import XCTest
@testable import AfterlightCore

final class TraceTests: XCTestCase {
    func testTraceMaraPassage() throws {
        let clock = FixedClock()
        let fresh = Game()
        fresh.clock = { clock.now }
        fresh.begin()
        fresh.story.chapter = 2
        fresh.story.flags.formUnion(["ordersOK", "hatchOpen", "flashOn", "sawShaft", "triedUp"])
        fresh.inv.belt.append(.flashlight)
        fresh.max.pos = V2(30, 9)
        sim(fresh, GameInput(), 1)
        let g = Game.load(try Game.decodeSave(try fresh.encodeSave()), clock: { clock.now })
        var log: [String] = []
        var t = 0.0
        func hold(_ input: GameInput, until done: () -> Bool, timeout: Double) {
            var tt = 0.0
            while !done() && tt < timeout {
                if g.max.stamina < 4 && input.dig { sim(g, GameInput(), 5) }
                g.update(dt: 1 / 60, input: input); _ = g.drainEvents(); tt += 1 / 60; t += 1 / 60
                if g.max.pos.x > 67.8 && log.count < 400 {
                    log.append(String(format: "t%.2f x%.3f y%.3f vx%.2f gr%d sw%d swk%@ st%.0f ctx %@", t, g.max.pos.x, g.max.pos.y, g.max.vx, g.max.ground ? 1 : 0, g.max.swingOn ? 1 : 0, "\(g.max.swingKind)", g.max.stamina, g.context?.id ?? "-"))
                }
            }
        }
        hold(GameInput(dx: 1), until: { g.max.pos.x > 34.3 }, timeout: 10)
        hold(GameInput(dx: 1, dig: true), until: { g.max.pos.x > 74 }, timeout: 900)
        let p = g.max.pos
        let tiles = (5...9).map { r in (Int(p.x) - 1...Int(p.x) + 3).map { c in "\(g.world.m(c, r).rawValue)" }.joined() }.joined(separator: "/")
        let probe = g.frontProbe(1).map { "d\($0.d) \($0.point) hard\($0.hard)" } ?? "none"
        XCTAssertGreaterThan(p.x, 74, "stuck \(p) probe \(probe) tiles \(tiles) chapter \(g.story.chapter)\n" + log.prefix(8).joined(separator: "\n") + "\n...\n" + log.suffix(6).joined(separator: "\n"))
    }
}
