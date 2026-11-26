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

    /// The last safety net: if Max keeps trying to move and stays inside the same small space,
    /// he can always climb out.
    func trapCheck(_ input: GameInput, dt: Double) {
        guard started, cine == nil, order == nil, planning == nil else { trapT = 0; return }
        if max.pos.dist(trapAnchor) > 1.6 { trapAnchor = max.pos; trapT = 0; trapTried = []; trapped = false; return }
        let trying = input.dx != 0 || input.jump || input.up
        if trying { trapT += dt }
        if input.dx != 0 { trapTried.insert(input.dx) }
        if input.jump || input.up { trapTried.insert(0) }
        // Only once he's tried more than one way out: pushing at one wall alone isn't being trapped.
        if trapT > 4.5 && trapTried.count >= 2 && !trapped {
            trapped = true
            think("Boxed in. I’ll haul myself out.", 2.4)
        }
    }

    /// The nearest higher spot where Max can stand with headroom, within a few tiles.
    func escapeSpot() -> V2? {
        let p = max.pos
        var best: V2? = nil, bestD = Double.infinity
        var dx = -8.0
        while dx <= 8.0 {
            let x = p.x + dx
            var y = p.y - 1.2
            while y > p.y - 9 {
                if world.solid(x, y + 0.1) && !world.solid(x, y - 0.2) && !world.solid(x, y - 1.0) && !world.solid(x, y - 1.8)
                    && !world.solid(x - 0.35, y - 1.0) && !world.solid(x + 0.35, y - 1.0) {
                    let gy = world.groundY(x, from: y - 0.3, to: y + 0.3) ?? y
                    let d = abs(dx) + (p.y - gy) * 0.6
                    if d < bestD { bestD = d; best = V2(x, gy) }
                    break
                }
                y -= 0.1
            }
            dx += 0.5
        }
        return best
    }

    func climbOut() {
        trapped = false; trapT = 0
        if max.mode == .climb { exitClimb() }
        if let s = escapeSpot() {
            max.face = s.x >= max.pos.x ? 1 : -1
            max.pos = s; max.ground = true; max.vx = 0; max.vy = 0; max.vyG = 0
            max.stamina = Swift.max(0, max.stamina - 8)
            emit(.land(speed: 2))
            think("Up and out.", 1.6)
        } else {
            // Nothing within reach: find the long way back home.
            max.pos = V2(Landmarks.bench.x - 1.5, 30); max.ground = true; max.vx = 0; max.vy = 0; max.vyG = 0
            think("Took the long way round, but I’m home.", 2.6)
        }
        trapAnchor = max.pos
        emit(.saveNow)
    }
}
