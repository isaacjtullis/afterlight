import XCTest
@testable import AfterlightCore
final class ZDumpTests: XCTestCase {
    func testDumpMap() throws {
        guard ProcessInfo.processInfo.environment["DUMP"] != nil else { return }
        let g = Game(); let w = g.world
        var s = ""
        for r in 0..<w.h { var line = String(format: "%02d ", r); for c in 0..<w.w { let m = w.m(c, r); line += m == .air || m == .dug ? " " : m.hard ? "#" : m == .metal ? "=" : "." }; s += line + "\n" }
        for p in w.props { s += "\(p.id) \(p.kind) \(p.pos)\n" }
        for c in w.climbs { s += "climb \(c.id) \(c.kind) \(c)\n" }
        try s.write(toFile: "/tmp/mapdump/map.txt", atomically: true, encoding: .utf8)
    }
}
