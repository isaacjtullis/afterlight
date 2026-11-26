import XCTest
@testable import AfterlightCore

final class TraceTests: XCTestCase {
    func testTracePassageDig() {
        let g = Game()
        g.begin()
        g.story.chapter = 3
        g.story.flags.formUnion(["ordersOK", "hatchOpen", "flashOn", "sawShaft", "triedUp"])
        g.inv.belt.append(.flashlight)
        g.max.pos = V2(34.3, 9)
        var log: [String] = []
        var t = 0.0
        var lastX = 0.0
        while g.max.pos.x < 74 && t < 400 {
            if g.max.stamina < 4 { sim(g, GameInput(), 5) }
            g.update(dt: 1 / 60, input: GameInput(dx: 1, dig: true)); _ = g.drainEvents(); t += 1 / 60
            if g.max.pos.x > 66 && abs(g.max.pos.x - lastX) > 0.05 {
                lastX = g.max.pos.x
                log.append(String(format: "t%.1f x%.2f y%.2f vx%.2f gr%d sw%d", t, g.max.pos.x, g.max.pos.y, g.max.vx, g.max.ground ? 1 : 0, g.max.swingOn ? 1 : 0))
            }
        }
        let p = g.max.pos
        let probe = g.frontProbe(1).map { "probe d\($0.d) at \($0.point) hard \($0.hard)" } ?? "no probe"
        let tiles = (5...9).map { r in (Int(p.x) - 1...Int(p.x) + 3).map { c in "\(g.world.m(c, r).rawValue)" }.joined() }.joined(separator: "/")
        let dens = (0..<8).map { i in String(format: "%.2f", g.world.density(p.x + 0.3 + Double(i) * 0.15, p.y - 0.3)) }.joined(separator: ",")
        XCTAssertGreaterThan(g.max.pos.x, 74, "stuck at \(p) \(probe) tiles \(tiles) dens@knee \(dens)\n" + log.suffix(12).joined(separator: "\n"))
    }
}
