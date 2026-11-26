import XCTest
@testable import AfterlightCore

final class TraceTests: XCTestCase {
    func testTraceWalkToWall() {
        let g = Game()
        g.begin()
        var log: [String] = []
        var t = 0.0
        var lastY = g.max.pos.y
        func step(_ inp: GameInput, _ tag: String) {
            g.update(dt: 1.0 / 60.0, input: inp); _ = g.drainEvents(); t += 1.0 / 60.0
            if abs(g.max.pos.y - lastY) > 0.01 {
                log.append(String(format: "%@ t%.2f x%.2f y%.3f vx%.2f gr%d sw%d run%d mode %@", tag, t, g.max.pos.x, g.max.pos.y, g.max.vx, g.max.ground ? 1 : 0, g.max.swingOn ? 1 : 0, g.max.running ? 1 : 0, "\(g.max.mode)"))
                lastY = g.max.pos.y
            }
        }
        while abs(g.max.pos.x - 31.3) > 0.25 && t < 20 { step(GameInput(dx: g.max.pos.x < 31.3 ? 1 : -1), "walk") }
        for _ in 0..<30 { step(GameInput(), "idle") }
        for _ in 0..<120 { step(GameInput(dig: true), "dig") }
        XCTAssertTrue(log.isEmpty, log.prefix(30).joined(separator: "\n"))
    }
}
