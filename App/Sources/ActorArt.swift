import CoreGraphics
import UIKit
import AfterlightCore

/// Hand-drawn characters, redrawn each frame from their animation state.
/// Drawing space: 1 unit = 1 tile, y down, origin at the character's feet.
enum ActorArt {
    static func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { TerrainArt.color(hex, a) }

    static func rr(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
    }
    static func line(_ ctx: CGContext, _ pts: [CGPoint], _ col: CGColor, _ w: CGFloat) {
        ctx.setStrokeColor(col); ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addLines(between: pts); ctx.strokePath()
    }
    static func dot(_ ctx: CGContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    /// Max: cream cloak, red scarf, dusty-purple beanie with a bouncing pom-pom.
    static func drawMax(_ ctx: CGContext, _ m: Max, time: Double, flashlight: Bool, flashOn: Bool, carrying: Bool, wood: Int = 0, back: Bool = false) {
        if back { drawMaxFromBehind(ctx, m, time: time, wood: wood); return }
        ctx.saveGState()
        ctx.scaleBy(x: CGFloat(m.face), y: 1)
        if m.mode == .climb {
            // Hanging from the hands: swing about the grip, not the feet.
            ctx.translateBy(x: 0.15, y: -1.75); ctx.rotate(by: CGFloat(m.lean)); ctx.translateBy(x: -0.15, y: 1.75)
        } else {
            ctx.rotate(by: CGFloat(m.lean + m.tilt) * CGFloat(m.face) * CGFloat(m.face))
        }
        let sq = CGFloat(m.squash)
        ctx.scaleBy(x: 1 + sq * 0.6, y: 1 - sq)
        let cr = CGFloat(m.crouch), bob = CGFloat(m.bob)
        let hipY = -0.6 + cr * 0.7, shY = -1.08 + cr + bob, headY = -1.38 + cr + bob * 1.2
        let climbing = m.mode == .climb

        // legs
        for i in [1, 0] {
            let ph = m.phase + Double(i) * .pi
            let amp = climbing ? 0.6 : m.walkAmp
            let sw = CGFloat(sin(ph) * amp)
            let lift = CGFloat(max(0, cos(ph)) * 0.13 * amp)
            let up = CGFloat(max(0, sin(ph)))
            let dangle = CGFloat(sin(time * 2.1 + Double(i) * 1.3)) * 0.03
            let fx = climbing ? CGFloat(i == 1 ? -0.06 : 0.1) + up * 0.1 + dangle : CGFloat(i == 1 ? -1 : 1) * CGFloat(m.stance) + sw * 0.24
            let fy = climbing ? -up * 0.38 : -lift
            let kx = climbing ? fx + 0.12 + up * 0.12 : fx * 0.5 + 0.05, ky = climbing ? (hipY + fy) / 2 - up * 0.06 : (hipY + fy) / 2
            line(ctx, [CGPoint(x: i == 1 ? -0.05 : 0.05, y: hipY), CGPoint(x: kx, y: ky), CGPoint(x: fx, y: fy - 0.06)], c(i == 1 ? 0x2a2026 : 0x3a2c33), 0.12)
            ctx.setFillColor(c(i == 1 ? 0x1c1418 : 0x2a1d22)); rr(ctx, fx - 0.08, fy - 0.12, 0.22, 0.12, 0.05); ctx.fillPath()
        }
        // backpack
        ctx.setFillColor(c(0x7a5a44)); rr(ctx, -0.37, shY + 0.02, 0.23, 0.4, 0.08); ctx.fillPath()
        ctx.setFillColor(c(0x5c4232)); ctx.fill(CGRect(x: -0.37, y: shY + 0.19, width: 0.23, height: 0.04))
        if wood > 0 {
            // Logs strapped across the back of the bag: more wood, a bigger bundle.
            let n = min(4, 1 + wood / 50)
            for k in 0..<n {
                let ly = shY + 0.06 + CGFloat(k % 2) * 0.1 - CGFloat(k / 2) * 0.1
                let lx = -0.5 + CGFloat(k / 2) * 0.03
                ctx.setFillColor(c(0x8a5a34)); rr(ctx, lx, ly, 0.36, 0.09, 0.045); ctx.fillPath()
                dot(ctx, lx + 0.36, ly + 0.045, 0.045, c(0xc9925a)); dot(ctx, lx + 0.36, ly + 0.045, 0.018, c(0x8a5a34))
            }
            line(ctx, [CGPoint(x: -0.42, y: shY + 0.0), CGPoint(x: -0.42, y: shY + 0.3)], c(0x3a2a22), 0.03)
        }
        if carrying {
            ctx.setFillColor(c(0xb48cff))
            ctx.addLines(between: [CGPoint(x: -0.3, y: shY + 0.04), CGPoint(x: -0.24, y: shY - 0.16), CGPoint(x: -0.18, y: shY + 0.04)]); ctx.fillPath()
        }
        // shovel geometry
        let a = CGFloat(climbing ? -1.9 + sin(m.phase) * 0.2 : m.shovel)
        let dx = cos(a), dy = sin(a)
        let P = CGPoint(x: 0.08, y: shY + 0.24)
        let hb = CGPoint(x: P.x - dx * 0.1, y: P.y - dy * 0.1), hf = CGPoint(x: P.x + dx * 0.2, y: P.y + dy * 0.2)
        line(ctx, [CGPoint(x: -0.04, y: shY + 0.08), hb], c(0xc9b48f), 0.1)
        // cloak with fluttering hem
        let spd = CGFloat(min(1, abs(m.vx) / 3))
        let sway = CGFloat(max(-0.18, min(0.18, -m.vx * Double(m.face) * 0.04))) + (m.ground ? 0 : -0.05)
        let hemY = hipY + 0.3
        ctx.setFillColor(c(0xeddcbd))
        ctx.move(to: CGPoint(x: -0.15, y: shY - 0.03)); ctx.addLine(to: CGPoint(x: 0.15, y: shY - 0.03))
        for k in stride(from: 4, through: 0, by: -1) {
            let u = CGFloat(k) / 4
            let hx = -0.26 + 0.51 * u + sway * (0.5 + 0.5 * (1 - u))
            let hy = hemY + CGFloat(sin(time * 7 + Double(k) * 1.4 + m.phase)) * 0.022 * (0.4 + spd) - (m.ground ? 0 : 0.07 * CGFloat(k % 2))
            ctx.addLine(to: CGPoint(x: hx, y: hy))
        }
        ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(c(0x966446, 0.2))
        ctx.addLines(between: [CGPoint(x: -0.15, y: shY - 0.03), CGPoint(x: -0.02, y: shY - 0.03), CGPoint(x: -0.02 + sway * 0.7, y: hemY), CGPoint(x: -0.26 + sway, y: hemY)])
        ctx.closePath(); ctx.fillPath()
        line(ctx, [CGPoint(x: -0.26 + sway, y: hemY), CGPoint(x: -0.15, y: shY - 0.03)], c(0xffc88c, 0.7), 0.03)
        dot(ctx, 0.09, shY + 0.18, 0.025, c(0xc79a5a)); dot(ctx, 0.1, shY + 0.32, 0.025, c(0xc79a5a))
        ctx.setFillColor(c(0xc8462f)); rr(ctx, -0.16, shY - 0.1, 0.34, 0.15, 0.07); ctx.fillPath()
        // head
        dot(ctx, 0.03, headY, 0.23, c(0xf0c9a0))
        dot(ctx, 0.14, headY + 0.07, 0.045, c(0xeb7864, 0.45))
        ctx.setFillColor(c(0x2a1a1e)); ctx.fillEllipse(in: CGRect(x: 0.106, y: headY - 0.046, width: 0.048, height: 0.072))
        ctx.setFillColor(c(0x4a3a5c))
        ctx.addArc(center: CGPoint(x: 0.02, y: headY - 0.03), radius: 0.235, startAngle: .pi, endAngle: 2 * .pi, clockwise: false); ctx.fillPath()
        ctx.fill(CGRect(x: -0.215, y: headY - 0.06, width: 0.47, height: 0.08))
        ctx.setFillColor(c(0x5c4a70)); ctx.fill(CGRect(x: -0.215, y: headY - 0.06, width: 0.47, height: 0.035))
        let pmx = -0.08 + CGFloat(m.pom) * CGFloat(m.face), pmy = headY - 0.3 + CGFloat(abs(m.pom)) * 0.3
        line(ctx, [CGPoint(x: -0.02, y: headY - 0.24), CGPoint(x: pmx, y: pmy)], c(0x4a3a5c), 0.04)
        dot(ctx, pmx, pmy, 0.075, c(0xe8a33a)); dot(ctx, pmx + 0.02, pmy - 0.025, 0.03, c(0xfff0c8, 0.5))
        // flashlight on the chest strap
        if flashlight {
            ctx.saveGState()
            ctx.translateBy(x: 0.14, y: shY + 0.12); ctx.rotate(by: CGFloat(m.beamA))
            ctx.setFillColor(c(0x575d63)); ctx.fill(CGRect(x: -0.05, y: -0.045, width: 0.17, height: 0.09))
            ctx.setFillColor(c(flashOn ? 0xfff1d0 : 0x7b8187)); ctx.fill(CGRect(x: 0.11, y: -0.06, width: 0.04, height: 0.12))
            ctx.restoreGState()
        }
        if climbing {
            // Shovel slung across the bag, blade up; both hands on the wall, reaching in turn.
            line(ctx, [CGPoint(x: -0.4, y: shY + 0.5), CGPoint(x: -0.08, y: shY - 0.42)], c(0x8a6440), 0.06)
            ctx.setFillColor(c(0xa7adb3)); rr(ctx, -0.15, shY - 0.66, 0.15, 0.26, 0.05); ctx.fillPath()
            for i in [0, 1] {
                let ph = m.phase + Double(i) * .pi
                let reach = CGFloat(max(0, sin(ph)))
                let hx: CGFloat = 0.2 + CGFloat(i) * 0.04
                let hy = headY - 0.18 - reach * 0.32 + CGFloat(sin(time * 2.4 + Double(i))) * 0.015
                let sx: CGFloat = 0.04, sy = shY + 0.05
                let ex = (sx + hx) / 2 + 0.1, ey = (sy + hy) / 2 + 0.04
                line(ctx, [CGPoint(x: sx, y: sy), CGPoint(x: ex, y: ey), CGPoint(x: hx, y: hy)], c(i == 0 ? 0xcfbd98 : 0xe3d1ae), 0.11)
                dot(ctx, hx, hy, 0.055, c(0xf0c9a0))
            }
            ctx.restoreGState()
            return
        }
        if m.hammerT > 0 {
            // Hammering: shovel slung on the back, the hammer coming down in short strokes.
            line(ctx, [CGPoint(x: -0.4, y: shY + 0.5), CGPoint(x: -0.08, y: shY - 0.42)], c(0x8a6440), 0.06)
            let k = CGFloat(abs(sin(time * 11)))
            let a = -2.3 + k * 1.7
            let sh = CGPoint(x: 0.06, y: shY + 0.06)
            let hand = CGPoint(x: sh.x + cos(a) * 0.42, y: sh.y + sin(a) * 0.42)
            line(ctx, [sh, hand], c(0xe3d1ae), 0.11)
            let end = CGPoint(x: hand.x + cos(a) * 0.5, y: hand.y + sin(a) * 0.5)
            line(ctx, [hand, end], c(0x7a5634), 0.05)
            ctx.saveGState(); ctx.translateBy(x: end.x, y: end.y); ctx.rotate(by: a)
            ctx.setFillColor(c(0x8f949a)); ctx.fill(CGRect(x: -0.04, y: -0.13, width: 0.12, height: 0.26))
            ctx.restoreGState()
            dot(ctx, hand.x, hand.y, 0.055, c(0xf0c9a0))
            ctx.restoreGState()
            return
        }
        // shovel or pick
        let s0 = CGPoint(x: P.x - dx * 0.26, y: P.y - dy * 0.26), e = CGPoint(x: P.x + dx * 0.82, y: P.y + dy * 0.82)
        let nx = -dy, ny = dx
        line(ctx, [s0, e], c(0x8a6440), 0.06)
        ctx.setFillColor(c(0xa7adb3))
        ctx.addLines(between: [CGPoint(x: e.x + nx * 0.08, y: e.y + ny * 0.08), CGPoint(x: e.x + dx * 0.22 + nx * 0.09, y: e.y + dy * 0.22 + ny * 0.09),
                               CGPoint(x: e.x + dx * 0.31, y: e.y + dy * 0.31), CGPoint(x: e.x + dx * 0.22 - nx * 0.09, y: e.y + dy * 0.22 - ny * 0.09),
                               CGPoint(x: e.x - nx * 0.08, y: e.y - ny * 0.08)])
        ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(c(0xf0f5fa, 0.6))
        ctx.addLines(between: [CGPoint(x: e.x + nx * 0.08, y: e.y + ny * 0.08), CGPoint(x: e.x + dx * 0.22 + nx * 0.09, y: e.y + dy * 0.22 + ny * 0.09), CGPoint(x: e.x + dx * 0.18 + nx * 0.03, y: e.y + dy * 0.18 + ny * 0.03)])
        ctx.closePath(); ctx.fillPath()
        // front arm
        line(ctx, [CGPoint(x: 0.05, y: shY + 0.08), hf], c(0xe3d1ae), 0.11)
        dot(ctx, hf.x, hf.y, 0.05, c(0xf0c9a0))
        ctx.restoreGState()
    }

    /// Max on a ladder, seen from behind: pack and shovel on his back, hands and feet working the rungs in turn.
    static func drawMaxFromBehind(_ ctx: CGContext, _ m: Max, time: Double, wood: Int) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -1.75); ctx.rotate(by: CGFloat(m.lean) * 0.5); ctx.translateBy(x: 0, y: 1.75)
        let hipY: CGFloat = -0.6, shY: CGFloat = -1.08, headY: CGFloat = -1.4
        // legs: one knee up on a rung while the other pushes
        for i in [0, 1] {
            let side: CGFloat = i == 0 ? -1 : 1
            let up = CGFloat(max(0, sin(m.phase + Double(i) * .pi)))
            let fx = side * 0.13, fy = -up * 0.42
            line(ctx, [CGPoint(x: side * 0.08, y: hipY), CGPoint(x: side * 0.17, y: (hipY + fy) / 2 - up * 0.05), CGPoint(x: fx, y: fy - 0.04)], c(0x2f2329), 0.12)
            ctx.setFillColor(c(0x1c1418)); rr(ctx, fx - 0.08, fy - 0.1, 0.16, 0.1, 0.04); ctx.fillPath()
        }
        // cloak from behind
        ctx.setFillColor(c(0xe3d1ae))
        ctx.move(to: CGPoint(x: -0.17, y: shY)); ctx.addLine(to: CGPoint(x: 0.17, y: shY))
        ctx.addLine(to: CGPoint(x: 0.26, y: hipY + 0.28)); ctx.addLine(to: CGPoint(x: -0.26, y: hipY + 0.28)); ctx.closePath(); ctx.fillPath()
        // arms reaching up for the rungs, alternating
        for i in [0, 1] {
            let side: CGFloat = i == 0 ? -1 : 1
            let reach = CGFloat(max(0, sin(m.phase + Double(i) * .pi + .pi / 2)))
            let hand = CGPoint(x: side * 0.24, y: headY - 0.2 - reach * 0.3)
            line(ctx, [CGPoint(x: side * 0.15, y: shY + 0.05), CGPoint(x: side * 0.27, y: (shY + hand.y) / 2), hand], c(0xd8c6a2), 0.1)
            dot(ctx, hand.x, hand.y, 0.055, c(0xf0c9a0))
        }
        // pack, shovel slung across it, wood if any
        ctx.setFillColor(c(0x7a5a44)); rr(ctx, -0.16, shY + 0.04, 0.32, 0.42, 0.08); ctx.fillPath()
        ctx.setFillColor(c(0x5c4232)); ctx.fill(CGRect(x: -0.16, y: shY + 0.2, width: 0.32, height: 0.04))
        line(ctx, [CGPoint(x: -0.3, y: shY + 0.5), CGPoint(x: 0.25, y: shY - 0.3)], c(0x8a6440), 0.05)
        ctx.setFillColor(c(0xa7adb3)); rr(ctx, 0.2, shY - 0.5, 0.13, 0.22, 0.04); ctx.fillPath()
        if wood > 0 { ctx.setFillColor(c(0x8a5a34)); rr(ctx, -0.22, shY + 0.42, 0.44, 0.09, 0.045); ctx.fillPath() }
        ctx.setFillColor(c(0xc8462f)); rr(ctx, -0.15, shY - 0.1, 0.3, 0.13, 0.06); ctx.fillPath()       // scarf, from behind
        // back of the head, beanie and pom
        dot(ctx, 0, headY, 0.22, c(0x3a2a22))
        ctx.setFillColor(c(0x4a3a5c)); ctx.addArc(center: CGPoint(x: 0, y: headY - 0.03), radius: 0.235, startAngle: .pi, endAngle: 2 * .pi, clockwise: false); ctx.fillPath()
        ctx.fill(CGRect(x: -0.235, y: headY - 0.06, width: 0.47, height: 0.08))
        dot(ctx, CGFloat(m.pom) * 0.5, headY - 0.3, 0.075, c(0xe8a33a))
        ctx.restoreGState()
    }

    /// Odi: a grower in a moss-green wrap with a lantern of her own.
    static func drawOdi(_ ctx: CGContext, face: Int, walking: Bool, time: Double) {
        ctx.saveGState()
        ctx.scaleBy(x: CGFloat(face), y: 1)
        let ph = time * (walking ? 7 : 0)
        let bob = walking ? CGFloat(-abs(sin(ph)) * 0.06) : CGFloat(sin(time * 2.2) * 0.01)
        let hipY: CGFloat = -0.62, shY = -1.12 + bob, headY = -1.42 + bob
        for i in [1, 0] {
            let sw = walking ? CGFloat(sin(ph + Double(i) * .pi)) : 0
            let fx = CGFloat(i == 1 ? -0.07 : 0.07) + sw * 0.22
            line(ctx, [CGPoint(x: 0, y: hipY), CGPoint(x: fx, y: 0 - 0.05)], c(i == 1 ? 0x2b2a24 : 0x3b392f), 0.12)
            ctx.setFillColor(c(0x1e1c18)); rr(ctx, fx - 0.08, -0.11, 0.2, 0.11, 0.05); ctx.fillPath()
        }
        ctx.setFillColor(c(0x5e7a52))
        ctx.addLines(between: [CGPoint(x: -0.17, y: shY), CGPoint(x: 0.17, y: shY), CGPoint(x: 0.26, y: hipY + 0.34), CGPoint(x: -0.27, y: hipY + 0.34)])
        ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(c(0x3f5638, 0.6)); ctx.fill(CGRect(x: -0.2, y: hipY + 0.02, width: 0.42, height: 0.05))
        dot(ctx, 0.03, headY, 0.22, c(0xc68e6a))
        ctx.setFillColor(c(0x2b1d18))
        ctx.addArc(center: CGPoint(x: -0.01, y: headY - 0.03), radius: 0.235, startAngle: .pi * 0.85, endAngle: .pi * 2.05, clockwise: false); ctx.fillPath()
        dot(ctx, -0.17, headY - 0.14, 0.11, c(0x2b1d18))
        ctx.setFillColor(c(0x1a1214)); ctx.fillEllipse(in: CGRect(x: 0.11, y: headY - 0.04, width: 0.045, height: 0.065))
        dot(ctx, 0.14, headY + 0.07, 0.04, c(0xd06a5a, 0.4))
        // lantern held low
        line(ctx, [CGPoint(x: 0.05, y: shY + 0.1), CGPoint(x: 0.28, y: hipY + 0.05)], c(0x5e7a52), 0.1)
        ctx.setFillColor(c(0x2c2724)); ctx.fill(CGRect(x: 0.22, y: hipY + 0.05, width: 0.14, height: 0.2))
        ctx.setFillColor(c(0xffc878, 0.9)); ctx.fill(CGRect(x: 0.24, y: hipY + 0.08, width: 0.1, height: 0.14))
        ctx.restoreGState()
    }

    /// Mara: the outpost's mechanic. Rust overalls, a teal headscarf, a wrench on her hip.
    static func drawMara(_ ctx: CGContext, face: Int, walking: Bool, working: Bool, time: Double) {
        ctx.saveGState()
        ctx.scaleBy(x: CGFloat(face), y: 1)
        let ph = time * (walking ? 7 : 0)
        let bob = walking ? CGFloat(-abs(sin(ph)) * 0.06) : CGFloat(sin(time * 2.0) * 0.01)
        let hipY: CGFloat = -0.66, shY = -1.18 + bob, headY = -1.48 + bob
        for i in [1, 0] {
            let sw = walking ? CGFloat(sin(ph + Double(i) * .pi)) : 0
            let fx = CGFloat(i == 1 ? -0.08 : 0.08) + sw * 0.22
            line(ctx, [CGPoint(x: 0, y: hipY), CGPoint(x: fx, y: -0.05)], c(i == 1 ? 0x5a3524 : 0x6b4030), 0.13)
            ctx.setFillColor(c(0x1e1a18)); rr(ctx, fx - 0.09, -0.11, 0.22, 0.11, 0.05); ctx.fillPath()
        }
        ctx.setFillColor(c(0x8a5a3c))
        ctx.addLines(between: [CGPoint(x: -0.18, y: shY), CGPoint(x: 0.18, y: shY), CGPoint(x: 0.22, y: hipY + 0.06), CGPoint(x: -0.22, y: hipY + 0.06)])
        ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(c(0x5c3a28)); ctx.fill(CGRect(x: -0.13, y: shY + 0.06, width: 0.26, height: 0.2))
        ctx.setFillColor(c(0x2a2420)); ctx.fill(CGRect(x: -0.22, y: hipY + 0.02, width: 0.44, height: 0.06))
        // wrench on the hip
        line(ctx, [CGPoint(x: -0.2, y: hipY + 0.02), CGPoint(x: -0.26, y: hipY + 0.3)], c(0x9aa0a6), 0.05)
        dot(ctx, 0.02, headY, 0.21, c(0x9c6b4e))
        ctx.setFillColor(c(0x2f7a78))
        ctx.addArc(center: CGPoint(x: 0, y: headY - 0.02), radius: 0.225, startAngle: .pi * 0.95, endAngle: .pi * 2.02, clockwise: false); ctx.fillPath()
        line(ctx, [CGPoint(x: -0.2, y: headY - 0.02), CGPoint(x: -0.32, y: headY + 0.12)], c(0x2f7a78), 0.06)
        ctx.setFillColor(c(0x1a1214)); ctx.fillEllipse(in: CGRect(x: 0.1, y: headY - 0.03, width: 0.045, height: 0.065))
        // arm: working swings a wrench, otherwise rests
        let a = working ? CGFloat(sin(time * 9)) * 0.4 : 0
        let hand = CGPoint(x: 0.3 + a * 0.1, y: shY + 0.36 - a * 0.25)
        line(ctx, [CGPoint(x: 0.08, y: shY + 0.08), hand], c(0x8a5a3c), 0.1)
        if working { line(ctx, [hand, CGPoint(x: hand.x + 0.22, y: hand.y - 0.1)], c(0x9aa0a6), 0.06) }
        ctx.restoreGState()
    }

    /// The lantern hanging off Max's pack, in world space.
    static func drawLantern(_ ctx: CGContext, hook: CGPoint, lamp: CGPoint, swing: Double, flicker: Double) {
        line(ctx, [hook, CGPoint(x: lamp.x, y: lamp.y - 0.08)], c(0x2a2623), 0.025)
        ctx.saveGState()
        ctx.translateBy(x: lamp.x, y: lamp.y); ctx.rotate(by: CGFloat(-swing * 0.6))
        ctx.setFillColor(c(0x2c2724)); ctx.fill(CGRect(x: -0.07, y: -0.1, width: 0.14, height: 0.03)); ctx.fill(CGRect(x: -0.07, y: 0.07, width: 0.14, height: 0.03))
        ctx.setFillColor(c(0xffbe6e, 0.6)); ctx.fill(CGRect(x: -0.055, y: -0.07, width: 0.11, height: 0.14))
        ctx.setFillColor(c(0xfff0c8)); ctx.fillEllipse(in: CGRect(x: -0.022, y: -0.045 * (1 + flicker), width: 0.044, height: 0.09 * (1 + flicker)))
        ctx.restoreGState()
    }

    /// The red scarf, a verlet rope in world space.
    static func drawScarf(_ ctx: CGContext, _ pts: [CGPoint]) {
        guard pts.count > 1 else { return }
        ctx.setLineCap(.round)
        for i in 1..<pts.count {
            ctx.setStrokeColor(c(i % 2 == 1 ? 0xc8462f : 0xb73b2a))
            ctx.setLineWidth(max(0.03, 0.105 - CGFloat(i) * 0.0085))
            ctx.move(to: pts[i - 1]); ctx.addLine(to: pts[i]); ctx.strokePath()
        }
    }
}
