import Foundation

struct Probe { var d: Double; var point: V2; var hard: Bool }

extension Game {

    // MARK: probes

    func wallHit(_ x: Double, _ y: Double) -> Bool {
        world.solid(x, y - 0.9) || world.solid(x, y - 1.3) || world.solid(x, y - 1.6)
    }

    /// First earth in front of Max at chest, waist and knee height.
    func frontProbe(_ dir: Int) -> Probe? {
        var d = 0.0
        while d <= 1.8 {
            for h in [1.38, 0.92, 0.6] {
                let p = V2(max.pos.x + Double(dir) * (Tuning.halfWidth + d), max.pos.y - h)
                if world.solid(p.x, p.y) { return Probe(d: d, point: p, hard: world.hardAt(p.x, p.y)) }
            }
            d += 0.08
        }
        return nil
    }

    /// Max may dig down only while he can still step back out.
    func canSink() -> Bool {
        let l = world.groundY(max.pos.x - 1.25, from: max.pos.y - 1.0, to: max.pos.y + 1.6)
        let r = world.groundY(max.pos.x + 1.25, from: max.pos.y - 1.0, to: max.pos.y + 1.6)
        let b = Swift.min(l ?? 99, r ?? 99)
        return b == 99 || max.pos.y - b < 0.25
    }

    /// An unrevealed buried find close below Max: digging down aims straight at it.
    func buriedBelow() -> Buried? {
        world.buried.first { !$0.revealed && abs($0.pos.x - max.pos.x) < 1.5 && $0.pos.y > max.pos.y - 0.5 && $0.pos.y < max.pos.y + 1.4 }
    }

    // MARK: swings

    func startOneShot(_ k: OneShotKind, at p: V2?) {
        max.oneShot = OneShot(kind: k, point: p)
    }

    func oneShotTick(_ dt: Double) {
        guard var s = max.oneShot else { return }
        let durs: [Double] = s.kind == .tryUp ? [0.1, 0.24, 0.07, 0.4] : [0.05, 0.17, 0.06, 0.16]
        s.t += dt
        if s.t >= durs[s.phase] {
            s.t = 0
            s.phase += 1
            if s.phase == 1 { emit(.whoosh) }
            if s.phase == 3 { oneShotImpact(s) }
            if s.phase > 3 { max.oneShot = nil; digLatch = false; downLatch = false; if s.kind == .tryUp { afterTryUp() }; return }
        }
        max.oneShot = s
    }

    func oneShotImpact(_ s: OneShot) {
        switch s.kind {
        case .air:
            emit(.whoosh)
        case .tryUp:
            emit(.pour(at: V2(max.pos.x + Double(max.face) * 0.4, 26.05)))
            max.crK = 0.14; max.squash = 0.12; max.lantV += 4
        case .clank, .clankDown:
            let p = s.point ?? max.pos
            emit(.clank(at: p))
            if time - clankAt > 6 {
                clankAt = time
                let t = world.m(Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))
                if t == .metal { think(s.kind == .clankDown ? "Steel floor. The blade just rings." : "Solid steel.", 2.4) }
                else { think("Bedrock. The blade just skips off it.", 2.4) }
            }
        }
    }

    /// Continuous digging: rhythmic swings, a bite at each strike, creeping forward.
    func swingTick(_ dt: Double, kind: SwingKind) -> Int {
        func floorRef() -> Double {
            // Standing on the rounded foot of a wall reads a little high; cut to the true floor line.
            let r = max.pos.y.rounded()
            return abs(max.pos.y - r) < 0.25 ? r : max.pos.y
        }
        if !max.swingOn { max.swingOn = true; max.swing = 0.04; max.digFloor = floorRef() }
        if abs(max.pos.y - max.digFloor) > 0.7 || kind != .side { max.digFloor = floorRef() }
        max.swingKind = kind
        var dir = 0
        if kind == .side, let pr = frontProbe(max.face), pr.d > 0.14 { dir = max.face }
        let prevS = max.swing
        let period = (max.stamina <= 0.5 && order == nil) ? Tuning.tiredSwingPeriod : Tuning.swingPeriod
        max.swing += dt / period
        if prevS < 0.6 && max.swing >= 0.6 { bite(kind) }
        if max.swing >= 1 { max.swing -= 1 }
        return dir
    }

    func bite(_ kind: SwingKind) {
        max.biteHigh.toggle()
        var c: V2
        var R = 0.72
        var tool = DigTool.shovel
        var floor: Double? = nil
        switch kind {
        case .side:
            c = V2(max.pos.x + Double(max.face) * (Tuning.halfWidth + 0.46), max.digFloor - (max.biteHigh ? 1.38 : 0.55))
            floor = max.digFloor
        case .down:
            c = V2(max.pos.x + Double(max.face) * 0.04, max.pos.y + 0.1)
            R = 0.55
            if let b = buriedBelow() { c = V2(b.pos.x, Swift.max(c.y, b.pos.y - 0.2)) }
        case .up:
            c = V2(max.pos.x, max.pos.y - (max.mode == .climb ? (max.biteHigh ? 2.55 : 1.9) : 2.0))
            R = 1.05
            tool = .pick
        }
        func hasEarth(_ c: V2) -> Bool {
            for o in [V2(0, 0), V2(0.3, 0), V2(-0.3, 0), V2(0, 0.3), V2(0, -0.3)] {
                let p = c + o
                if world.solid(p.x, p.y) && tool.cuts(world.m(Int(p.x.rounded(.down)), Int(p.y.rounded(.down)))) { return true }
            }
            return false
        }
        var near = hasEarth(c)
        if !near && kind == .side {
            // A thin sliver right against Max: swing shorter so it doesn't stall him.
            let close = V2(max.pos.x + Double(max.face) * (Tuning.halfWidth + 0.12), c.y)
            if hasEarth(close) { c = close; near = true }
        }
        if !near {
            if kind == .up && world.solid(c.x, c.y) && !world.hardAt(c.x, c.y) {
                if time - clankAt > 5 { clankAt = time; think("Packed too hard overhead. The pick only opens soft seams.", 2.8) }
            }
            emit(.whoosh); return
        }
        let res = world.carve(center: c, radius: R, floorY: floor, tool: tool)
        emit(.bite(at: c, kind: kind, carved: res.changed, face: max.face))
        max.lantV += Double(max.face) * 1.3
        max.squash = 0.09
        digLatch = false; downLatch = false
        if res.changed {
            max.stamina = Swift.max(0, max.stamina - Tuning.biteCost)
            max.restT = 0
            story.flags.insert("dug")
        }
        for b in res.revealed {
            drops.append(Drop(item: b.item, pos: b.pos, vy: -5.5, t: 0))
            emit(.reveal(at: b.pos))
        }
        if let o = res.touchedOpen { breakthrough(o.c, o.r) }
        onCarved(res)
    }

    func breakthrough(_ c: Int, _ r: Int) {
        guard !story.flags.contains("broke") else { return }
        story.flags.insert("broke")
        flicker = 1
        emit(.breakthrough(at: V2(Double(c), Double(r))))
        let y = max.pos.y
        later(0.03) { g in
            _ = g.world.carve(center: V2(Double(c) - 0.1, y - 1.36), radius: 0.95, floorY: y, tool: .shovel)
            _ = g.world.carve(center: V2(Double(c) - 0.1, y - 0.62), radius: 0.95, floorY: y, tool: .shovel)
        }
        if order != nil { stopOrder("opening") } else { later(0.5) { $0.think("…air. Moving air.", 3) } }
        emit(.saveNow)
    }

    // MARK: physics

    func physics(dir: Int, dt: Double) {
        let prevVx = max.vx
        var slope = 0.0
        let p = max.pos
        if max.ground,
           let a = world.groundY(p.x - 0.25, from: p.y - 0.9, to: p.y + 0.9),
           let b = world.groundY(p.x + 0.25, from: p.y - 0.9, to: p.y + 0.9) {
            slope = clampD((b - a) / 0.5, -1.6, 1.6)
        }
        max.slope = damp(max.slope, slope, 10, dt)
        let sinT = max.slope / (1 + max.slope * max.slope).squareRoot()
        let uphill = (dir != 0 && Double(dir) * max.slope < 0) ? abs(sinT) : 0
        let vmax = (max.swingOn ? 1.4 : Tuning.walkSpeed) * (1 - 0.35 * uphill)
        if dir != 0 {
            if max.vx != 0 && (max.vx > 0 ? 1 : -1) == -dir {
                max.vx += Double(dir) * Tuning.decel * dt
            } else if abs(max.vx) < vmax {
                max.vx = Double(dir) * Swift.min(vmax, abs(max.vx) + Tuning.accel * dt)
            } else {
                max.vx -= (max.vx > 0 ? 1 : -1) * 1.1 * dt
            }
        } else {
            let fr = (max.ground && abs(max.vx) > Tuning.walkSpeed * 1.05) ? 2.0 : Tuning.decel
            let s = max.vx > 0 ? 1.0 : (max.vx < 0 ? -1.0 : 0)
            max.vx -= s * Swift.min(abs(max.vx), fr * dt)
        }
        if max.ground && !max.swingOn && abs(sinT) > 0.04 && (abs(max.vx) > Tuning.walkSpeed * 0.95 || (dir == 0 && abs(sinT) > 0.45)) {
            max.vx += 15 * sinT * dt
        }
        max.vx = clampD(max.vx, -8.5, 8.5)
        if dir == 0 && abs(prevVx) > 1.5 && abs(prevVx) < Tuning.walkSpeed * 1.1 && !max.stopping { max.stopping = true; max.crK = 0.075 }
        if dir != 0 { max.stopping = false }
        max.ax = clampD((max.vx - prevVx) / Swift.max(dt, 1e-3), -25, 25)

        let prevX = max.pos.x
        if max.vx != 0 {
            let nx = max.pos.x + max.vx * dt
            let sgn: Double = max.vx > 0 ? 1 : -1
            let fx = nx + sgn * Tuning.halfWidth
            if wallHit(fx, max.pos.y) {
                // A knee-high lip (the rim of a hole he dug) is stepped over, not a wall.
                if max.ground && !max.swingOn,
                   let top = world.groundY(fx, from: max.pos.y - 1.0, to: max.pos.y),
                   max.pos.y - top > 0.12, max.pos.y - top < 0.85,
                   !world.solid(fx, top - 0.1), !wallHit(fx, top),
                   !world.solid(nx, top - 0.4), !world.solid(nx, top - 1.0), !world.solid(nx, top - Tuning.height),
                   world.groundY(nx, from: max.pos.y - 1.2, to: max.pos.y + 0.2).map({ $0 >= top - 0.05 }) ?? true {
                    max.pos.x = nx
                    max.pos.y = top
                    max.vx *= 0.6
                    max.squash = Swift.max(max.squash, 0.06)
                } else {
                    if abs(max.vx) > 4.5 { emit(.land(speed: 3)) }
                    max.vx = 0
                }
            } else {
                max.pos.x = nx
            }
        }

        if max.ground {
            // Follow the floor within a step of the feet; never snap up onto earth hanging overhead.
            let overhang = world.solid(max.pos.x, max.pos.y - 0.45) && !world.solid(max.pos.x, max.pos.y - 0.05)
            let from = overhang ? max.pos.y - 0.05 : max.pos.y - 0.45
            if let g = world.groundY(max.pos.x, from: from, to: max.pos.y + 0.75) {
                let pred = max.pos.y + max.vyG * dt + 0.5 * Tuning.airGravity * dt * dt
                if abs(max.vx) > 4.6 && g > pred + 0.045 {
                    max.ground = false; max.vy = max.vyG
                } else if !(max.swingOn && max.swingKind == .side) && g < max.pos.y - (Swift.abs(max.vx) * dt * 1.8 + 0.035) {
                    // Too steep to walk up in one step: a small lip gets a little hop, anything taller is a wall.
                    let h = max.pos.y - g
                    if h < 0.85 && dir != 0 && !wallHit(max.pos.x, g) {
                        max.ground = false
                        max.vy = -(2 * Tuning.gravity * (h + 0.12)).squareRoot()
                        max.air = 0
                        max.squash = Swift.max(max.squash, 0.08)
                    } else {
                        max.pos.x = prevX
                        max.vx = 0
                    }
                } else {
                    // While cutting sideways the floor is held level: uncut crumbs never lift Max.
                    let gg = (max.swingOn && max.swingKind == .side) ? Swift.max(g, max.digFloor - 0.04) : g
                    max.vyG = clampD((gg - max.pos.y) / dt, -14, 14)
                    max.pos.y = gg
                }
            } else {
                max.ground = false; max.vy = max.vyG
            }
        }
        if !max.ground {
            max.air += dt
            let grav = abs(max.vx) > 3.6 ? Tuning.airGravity : Tuning.gravity
            max.vy = Swift.min(max.vy + grav * dt, 20)
            let ny = max.pos.y + max.vy * dt
            if max.vy >= 0 {
                if let g = world.groundY(max.pos.x, from: max.pos.y - 0.05, to: ny + 0.03) {
                    let v = max.vy
                    max.pos.y = g; max.ground = true; max.vyG = 0
                    if v > 4.5 || max.air > 0.35 {
                        emit(.land(speed: v))
                        max.crK = 0.06 + Swift.min(0.12, v * 0.012)
                    }
                    max.air = 0
                } else {
                    max.pos.y = ny
                }
            } else if world.solid(max.pos.x, ny - Tuning.height) {
                max.vy = 0
            } else {
                max.pos.y = ny
            }
        }

        let ph0 = Int((max.phase / .pi).rounded(.down))
        max.sliding = max.ground && abs(max.vx) > Tuning.walkSpeed * 1.12
        max.phase += abs(max.vx) * dt * (max.sliding ? 0.6 : 4.3)
        if !max.sliding && Int((max.phase / .pi).rounded(.down)) != ph0 && max.walkAmp > 0.35 && max.ground {
            emit(.step)
            max.squash = Swift.max(max.squash, 0.05 * max.walkAmp)
        }
    }

    // MARK: feel

    func updateFeel(_ dt: Double) {
        let L = 0.3
        let acc = max.ax * 0.8 + cos(max.phase * 2) * 5 * max.walkAmp
        max.lantV += (-(26 * sin(max.lant) + acc * cos(max.lant)) / L - 2.4 * max.lantV) * dt
        max.lant = clampD(max.lant + max.lantV * dt, -1.2, 1.2)
        max.squash = damp(max.squash, 0, 11, dt)
        max.pomV += (-90 * max.pom - 6 * max.pomV - max.ax * 0.012 + (max.ground ? 0 : max.vy * 0.02)) * dt
        max.pom = clampD(max.pom + max.pomV * dt, -0.25, 0.25)

        var tA = -2.2, rate = 8.0, tCr = 0.0, stance = 0.07
        var tLean = clampD(max.vx * 0.03, -0.1, 0.1) - max.ax * 0.005
        if max.swingOn {
            let s = max.swing
            let high = s < 0.6 ? !max.biteHigh : max.biteHigh
            func eo(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
            func ei(_ x: Double) -> Double { x * x * x }
            func eio(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x) }
            var a0 = -2.3, a1 = -2.95, a2 = high ? -0.12 : 0.42, l1 = 0.16, c1 = high ? 0.05 : 0.13
            switch max.swingKind {
            case .side: stance = 0.19
            case .down: a0 = -2.05; a1 = -1.7; a2 = 1.45; l1 = 0.2; c1 = 0.17; stance = 0.2
            case .up: a0 = 0.3; a1 = 0.8; a2 = -1.45; l1 = -0.12; c1 = 0.0; stance = 0.15
            }
            if s < 0.5 {
                let k = eo(s / 0.5); max.shovel = lerpD(a0, a1, k); tLean = lerpD(0, -0.11, k); tCr = 0.05
            } else if s < 0.62 {
                let k = ei((s - 0.5) / 0.12); max.shovel = lerpD(a1, a2, k); tLean = lerpD(-0.11, l1, k); tCr = lerpD(0.05, c1, k)
            } else {
                let k = eio((s - 0.62) / 0.38); max.shovel = lerpD(a2, a0, k); tLean = lerpD(l1, 0, k); tCr = lerpD(c1, 0.05, k)
            }
            rate = 0
        } else if let o = max.oneShot {
            let poses: [[Double]]
            switch o.kind {
            case .air, .clank: poses = [[-2.35, 0, 0.06], [-2.85, -0.14, 0.05], [-0.1, 0.17, 0.07], [-0.18, 0.07, 0.05]]
            case .clankDown: poses = [[-2.05, 0, 0.05], [-1.75, -0.1, 0], [1.5, 0.2, 0.17], [1.3, 0.1, 0.12]]
            case .tryUp: poses = [[0.4, 0, 0.1], [0.85, 0.05, 0.16], [-1.38, -0.14, -0.02], [-1.1, 0.12, 0.14]]
            }
            let p = poses[Swift.min(o.phase, 3)]
            tA = p[0]; tLean = p[1]; tCr = p[2]; stance = 0.18
            rate = o.phase == 2 ? 48 : 11
        } else if max.busy > 0 {
            tA = -0.25 + sin(time * 16) * 0.12; tLean = 0.12; tCr = 0.05; stance = 0.12; rate = 12
        } else if max.mode == .climb {
            tA = -2.4; tLean = max.sway; stance = 0.05; rate = 0
        } else if max.sliding {
            tA = -2.95; tCr = 0.17; tLean = -0.06; stance = 0.22; rate = 6
        } else if !max.ground && max.air > 0.08 {
            tA = -3.05 + sin(time * 6) * 0.1; tCr = 0.03; tLean = clampD(-max.vy * 0.03, -0.25, 0.25); stance = 0.15; rate = 5
        }
        if rate > 0 { max.shovel = damp(max.shovel, tA, rate, dt) }
        max.lean = max.mode == .climb ? tLean : damp(max.lean, tLean, 13, dt)
        max.crK = damp(max.crK, 0, 7, dt)
        max.crouch = damp(max.crouch, tCr + max.crK, 16, dt)
        max.stance = damp(max.stance, stance, 10, dt)
        let moving = !(max.swingOn || max.sliding || !max.ground || max.mode == .climb)
        max.walkAmp = damp(max.walkAmp, moving ? Swift.min(1, abs(max.vx) / Tuning.walkSpeed) : 0, 8, dt)
        max.tilt = damp(max.tilt, max.ground && max.mode == .walk ? clampD(atan(max.slope * Double(max.face)) * 0.35, -0.16, 0.16) : 0, max.ground ? 8 : 3, dt)
        let breathe = (max.walkAmp < 0.2 && max.ground && !max.swingOn) ? 0.012 * sin(time * 2.4) : 0
        max.bob = -abs(sin(max.phase)) * 0.075 * max.walkAmp + breathe
    }

    // MARK: climbing

    func reachableClimb(up: Bool) -> Climb? {
        let p = max.pos
        for c in world.climbs where abs(c.x - p.x) < 0.55 {
            if up {
                // hands reach about 2.1 above the feet
                if c.bottom >= p.y - 2.1 && c.top < p.y - 0.05 { return c }
            } else {
                if abs(c.top - p.y) < 0.35 || (c.top < p.y - 0.05 && c.bottom > p.y + 0.05) { return c }
            }
        }
        return nil
    }

    func tryEnterClimb(up: Bool) -> Bool {
        guard let c = reachableClimb(up: up) else { return false }
        max.mode = .climb; max.climbID = c.id
        max.swayV += Double(max.face) * 1.6 + max.vx * 0.3
        max.vx = 0; max.vy = 0; max.ground = false
        max.swingOn = false
        story.flags.insert("climbed")
        return true
    }

    func climbTick(_ dt: Double, input: GameInput, freshDig: Bool) {
        guard let id = max.climbID, let c = world.climbs.first(where: { $0.id == id }) else { max.mode = .walk; return }
        max.pos.x = damp(max.pos.x, c.x, 12, dt)
        let v = (input.down ? 1.0 : 0) - (input.up ? 1.0 : 0)
        let wasMoving = abs(max.vy) > 0.1
        max.vy = v * Tuning.climbSpeed
        max.phase += abs(max.vy) * dt * 3.2
        // Pendulum sway: each reach pulls the body to one side; stopping lets it swing out and settle.
        let reach = abs(max.vy) > 0.1 ? sin(max.phase) * 7.5 : 0
        if wasMoving && abs(max.vy) < 0.1 { max.swayV += (max.sway >= 0 ? 1 : -1) * 0.9 }
        max.swayV += (reach - 26 * max.sway - 2.2 * max.swayV) * dt
        max.sway = clampD(max.sway + max.swayV * dt, -0.32, 0.32)
        max.lantV += max.swayV * 0.6 * dt
        var ny = max.pos.y + max.vy * dt
        // head room: pick away the seam above
        if input.dig {
            if inv.has(.shortPick) {
                _ = swingTick(dt, kind: .up)
            } else if freshDig {
                startOneShot(.tryUp, at: nil)
            }
            ny = max.pos.y
        } else if max.swingOn {
            max.swing += dt / Tuning.swingPeriod
            if max.swing >= 1 { max.swingOn = false; max.swing = 0 }
        }
        oneShotTick(dt)
        if world.solid(max.pos.x, ny - Tuning.height) && v < 0 { ny = max.pos.y }
        max.pos.y = clampD(ny, c.top, c.bottom)
        // hand over to the next climbable above (ladder -> rungs)
        if max.pos.y <= c.top + 0.05 && input.up,
           let next = world.climbs.first(where: { $0.id != c.id && abs($0.x - c.x) < 0.6 && $0.bottom >= max.pos.y - 0.3 && $0.top < max.pos.y - 0.05 }) {
            max.climbID = next.id
            return
        }
        // step off at the top onto whichever side has floor
        if max.pos.y <= c.top + 0.01 && input.up {
            // The edge of an opening is rounded; reach a little further for flat floor if needed.
            for reach in [1.05, 1.5, 2.0, 2.5] {
                for side in [max.face, -max.face] {
                    let x = c.x + Double(side) * reach
                    if let g = world.groundY(x, from: c.top - 0.8, to: c.top + 0.9), !wallHit(x, g) {
                        max.pos = V2(x, g); max.face = side
                        exitClimb(); return
                    }
                }
            }
        }
        if (max.pos.y >= c.bottom - 0.01 && input.down) || input.dx != 0 {
            if let g = world.groundY(max.pos.x, from: max.pos.y - 0.3, to: max.pos.y + 0.35) {
                max.pos.y = g; exitClimb()
                if input.dx != 0 { max.face = input.dx }
            }
        }
    }

    func exitClimb() {
        max.mode = .walk; max.climbID = nil; max.ground = true; max.vy = 0; max.vyG = 0; max.swingOn = false
    }

    /// Is there earth right against Max on this side?
    func wallBeside(_ dir: Int) -> Bool {
        let x = max.pos.x + Double(dir) * 0.75
        return world.solid(x, max.pos.y - 0.5) && !world.hardAt(x, max.pos.y - 0.5)
    }

    /// The top of the earth ledge on this side, if Max could climb it: the first opening with
    /// headroom above it, up to about eight tiles.
    func footholdTop(_ dir: Int) -> Double? {
        let x = max.pos.x + Double(dir) * 0.75
        guard wallBeside(dir) else { return nil }
        var y = max.pos.y - 0.5
        while y > max.pos.y - 8.5 {
            if world.hardAt(x, y) { return nil }
            if !world.solid(x, y) && !world.solid(x, y - 0.6) && !world.solid(x, y - 1.2) {
                guard let t = world.groundY(x, from: y, to: max.pos.y), max.pos.y - t > 0.9 else { return nil }
                // Room to stand at the top, and a clear line for Max's own body on the way up.
                if world.solid(x + Double(dir) * 0.4, t - 1.2) { return nil }
                var yy = max.pos.y - 0.4
                while yy > t + 0.2 { if world.solid(max.pos.x, yy - 1.2) { return nil }; yy -= 0.25 }
                return t
            }
            y -= 0.1
        }
        return nil
    }

    /// Cut footholds up an earth ledge so Max can climb it: out of a hole he dug, or up a bank.
    @discardableResult
    func tryFoothold(dir: Int) -> Bool {
        guard let t = footholdTop(dir) else { return false }
        let x = max.pos.x + Double(dir) * 0.75
        let lineX = max.pos.x + Double(dir) * 0.35
        if world.climbs.contains(where: { abs($0.x - lineX) < 0.45 && $0.bottom > max.pos.y - 0.6 && $0.top < max.pos.y - 0.5 }) { return false }
        world.climbs.append(Climb(id: "foot.\(Int(time * 100))", x: lineX, top: t, bottom: max.pos.y, kind: .foothold))
        emit(.bite(at: V2(x, max.pos.y - 1), kind: .side, carved: true, face: dir))
        max.face = dir
        if !story.flags.contains("said.footholds") {
            story.flags.insert("said.footholds")
            think("Footholds. That’ll do.", 2)
        }
        return true
    }

    // MARK: live dig orders

    public func previewOrder(dir: Int) -> OrderPreview? {
        let f = Int(max.pos.y.rounded())
        var face: Int? = nil
        var c = Int(max.pos.x.rounded(.down))
        for _ in 0..<44 {
            if world.m(c, f - 1).solid || world.m(c, f - 2).solid { face = c; break }
            c += dir
        }
        guard let F = face else { return nil }
        var budget = max.stamina
        var reach = F - dir
        var blocked: Int? = nil
        var col = F
        while abs(col - F) < 40 {
            var cost = 0.0, ok = true, natural = true
            for r in [f - 2, f - 1] {
                let t = world.m(col, r)
                if t.solid {
                    natural = false
                    if !DigTool.shovel.cuts(t) { ok = false } else { cost += Tuning.columnCost / 2 }
                } else if !(t == .air && world.bd(col, r) == .open) { natural = false }
            }
            if !ok { blocked = col; break }
            if natural { break }
            if cost > budget { break }
            budget -= cost
            reach = col
            col += dir
        }
        return OrderPreview(dir: dir, face: F, reach: reach, blockedAt: blocked, floorRow: f)
    }

    public func beginPlanning() {
        guard story.flags.contains("ordersOK"), order == nil, cine == nil, max.mode == .walk else { return }
        var p = previewOrder(dir: max.face)
        if p == nil || p?.blockedAt == p?.face {
            if let q = previewOrder(dir: -max.face), q.blockedAt != q.face { p = q }
        }
        guard let pv = p, pv.blockedAt != pv.face else { think("Nothing I can cut from here.", 2.4); return }
        max.face = pv.dir
        planning = pv
    }
    public func cancelPlanning() { planning = nil }
    public func confirmOrder(target: Int) {
        guard let p = planning else { return }
        var t = target
        if (t - p.face) * p.dir < 0 { t = p.face }
        order = DigOrder(dir: p.dir, target: t)
        planning = nil
        story.flags.insert("orderGiven")
        think(["On it.", "Right. Here goes.", "Back to it."][Int(time) % 3], 1.8)
    }

    func orderTick() -> (Int, SwingKind?) {
        guard let o = order else { return (0, nil) }
        max.face = o.dir
        let frontCol = Int((max.pos.x + Double(o.dir) * (Tuning.halfWidth + 0.5)).rounded(.down))
        if (frontCol - o.target) * o.dir > 0 { stopOrder("done"); return (0, nil) }
        guard let pr = frontProbe(o.dir) else { return (o.dir, nil) }
        if pr.hard && pr.d < 0.5 { stopOrder("blocked"); return (0, nil) }
        if max.stamina < Tuning.biteCost { stopOrder("tired"); return (0, nil) }
        return (0, .side)
    }

    public func stopOrder(_ why: String) {
        guard order != nil else { return }
        order = nil
        switch why {
        case "done": think("That’s the stretch.", 3)
        case "tired": think("That’s all I’ve got. Need a breather.", 3)
        case "opening": think("Wait. There’s air coming through.", 3)
        case "blocked": think("Too hard to cut.", 3)
        default: hint("You took over.", 1.6)
        }
        emit(.saveNow)
    }

    // MARK: cinematic: the flashlight

    func cineTick(_ dt: Double) -> Int {
        guard var c = cine else { return 0 }
        c.t += dt
        let t = c.t
        max.flashI = t < 0.05 ? 1 : t < 0.14 ? 0 : t < 0.22 ? 0.8 : t < 0.45 ? 0.08 : t < 0.52 ? 1 : t < 0.6 ? 0.4 : 1
        if t > 0.5 && c.beat == 0 { c.beat = 1; emit(.swell) }
        if t > 1.3 && c.beat == 1 { c.beat = 2; think("Oh.", 1.6) }
        if t > 2.7 && c.beat == 2 { c.beat = 3; think("…what’s up there?", 2) }
        if t > 5 && c.beat == 3 { c.beat = 4; think("A service shaft. It goes all the way up.", 3.4) }
        var dir = 0
        if t > 2.3 {
            max.face = 1
            let dx = 26.05 - max.pos.x
            if abs(dx) > 0.15 { dir = dx > 0 ? 1 : -1 }
            max.beamA = damp(max.beamA, -1.52, 2.2, dt)
            max.lookUp = damp(max.lookUp, 1, 2, dt)
            let k = smoothstepD(2.4, 4.6, t) * (1 - smoothstepD(6.4, 7.6, t))
            c.focus = V2(26, 18.5); c.focusWeight = k
        } else {
            max.beamA = damp(max.beamA, 0.05, 4, dt)
            if max.face < 0 && t > 0.3 { max.face = 1 }
        }
        cine = c
        if t > 8.6 {
            cine = nil
            story.flags.insert("sawShaft")
            hint("The shaft goes up. Stand under it and try the shovel.", 6)
        }
        return dir
    }
}
