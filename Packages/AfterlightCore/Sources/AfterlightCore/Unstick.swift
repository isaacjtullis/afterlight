import Foundation

extension Game {
    /// A safety net under all the movement rules: if Max is pushing a direction and not going anywhere,
    /// clear a body-sized gap of soft earth in front of him. Hard rock or steel gets a thought instead.
    func unstick(dir: Int, dt: Double) {
        guard dir != 0, max.mode == .walk, max.ground, cine == nil, order == nil else { stuckT = 0; stuckX = max.pos.x; return }
        if abs(max.pos.x - stuckX) > 0.08 { stuckT = 0; stuckX = max.pos.x; return }
        stuckT += dt
        guard stuckT > 1.0 else { return }
        stuckT = 0; stuckX = max.pos.x
        let x = max.pos.x + Double(dir) * (Tuning.halfWidth + 0.45)
        let heights = [0.45, 0.95, 1.45, 1.7]
        let blocked = heights.contains { world.solid(x, max.pos.y - $0) }
        guard blocked else { return }
        if heights.contains(where: { world.solid(x, max.pos.y - $0) && world.hardAt(x, max.pos.y - $0) }) {
            if time - clankAt > 5 { clankAt = time; think("Solid rock. I’ll have to find another way.", 2.6) }
            return
        }
        var res = CarveResult()
        for h in heights {
            let r = world.carve(center: V2(x, max.pos.y - h), radius: 0.62, floorY: max.pos.y, tool: .shovel)
            res.changed = res.changed || r.changed
            res.cleared += r.cleared; res.revealed += r.revealed
            if res.touchedOpen == nil { res.touchedOpen = r.touchedOpen }
        }
        if res.changed { emit(.bite(at: V2(x, max.pos.y - 0.9), kind: .side, carved: true, face: dir)) }
        for b in res.revealed { drops.append(Drop(item: b.item, pos: b.pos, vy: -5.5, t: 0)); emit(.reveal(at: b.pos)) }
        onCarved(res)
    }
}
