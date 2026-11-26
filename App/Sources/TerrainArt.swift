import CoreGraphics
import UIKit
import AfterlightCore

/// Draws one chunk of terrain (back walls, smooth earth, steel, stencils) into an image.
/// Coordinates inside the context are world tiles with y down, scaled by `ppt` pixels per tile.
enum TerrainArt {
    static let ppt: CGFloat = 26

    static func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a).cgColor
    }

    static let earthHome = color(0x66412f), earthCave = color(0x55323d), loose = color(0x86604a)
    static let rimTop = color(0xffd6aa, 0.36), rimBottom = color(0x1e0a12, 0.3)

    static func render(world w: World, cx: Int, cy: Int) -> CGImage? {
        let n = World.chunk
        let size = Int(CGFloat(n) * ppt)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: ppt, y: -ppt)
        ctx.translateBy(x: -CGFloat(cx * n), y: -CGFloat(cy * n))
        ctx.setShouldAntialias(true)

        let c0 = cx * n, c1 = c0 + n - 1, r0 = cy * n, r1 = r0 + n - 1

        // Back walls behind every tile that isn't natural cavern.
        for r in r0...r1 {
            for c in c0...c1 {
                let b = w.bd(c, r)
                let rect = CGRect(x: c, y: r, width: 1, height: 1).insetBy(dx: -0.02, dy: -0.02)
                switch b {
                case .open: continue
                case .room:
                    ctx.setFillColor(color(c % 3 == 0 ? 0x403d4a : 0x454250)); ctx.fill(rect)
                    ctx.setFillColor(color(0x000000, 0.22))
                    if c % 3 == 0 { ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r), width: 0.05, height: 1)) }
                    if r == 27 { ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r) + 0.5, width: 1, height: 0.04)) }
                case .maint:
                    ctx.setFillColor(color(c % 4 == 0 ? 0x3a3f46 : 0x40454d)); ctx.fill(rect)
                    ctx.setFillColor(color(0x000000, 0.2))
                    if c % 4 == 0 { ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r), width: 0.05, height: 1)) }
                case .outpost:
                    ctx.setFillColor(color((c + r) % 2 == 0 ? 0x5a4636 : 0x5e4939)); ctx.fill(rect)
                    ctx.setFillColor(color(0x000000, 0.18)); ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r) + 0.95, width: 1, height: 0.05))
                case .sump:
                    ctx.setFillColor(color(0x2c3438)); ctx.fill(rect)
                    ctx.setFillColor(color(0x000000, 0.2)); ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r) + 0.95, width: 1, height: 0.05))
                case .transit:
                    ctx.setFillColor(color(c % 6 == 0 ? 0x33302e : 0x3a3633)); ctx.fill(rect)
                    if r == 1 && c % 6 == 3 { ctx.setFillColor(color(0xffdcb4, 0.08)); ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r), width: 1.2, height: 0.25)) }
                case .shaft:
                    ctx.setFillColor(color(0x2e2c34)); ctx.fill(rect)
                    ctx.setFillColor(color(0xffdcb4, 0.06)); ctx.fill(CGRect(x: CGFloat(c), y: CGFloat(r) + 0.82, width: 1, height: 0.1))
                case .earth:
                    ctx.setFillColor(color(0x4e312b)); ctx.fill(rect)
                }
            }
        }

        // Smooth earth from the density field (marching squares on the fine grid).
        let K = World.K
        let k = CGFloat(K)
        let top = CGMutablePath(), bot = CGMutablePath()
        var fills: [UInt32: CGMutablePath] = [:]
        func path(_ c: UInt32) -> CGMutablePath { if let p = fills[c] { return p }; let p = CGMutablePath(); fills[c] = p; return p }
        func cellColor(_ c: Int, _ r: Int) -> UInt32 {
            var t = w.m(c, r), cc = c
            if !t.solid || t == .metal {
                for (dc, dr) in [(0, 1), (0, -1), (-1, 0), (1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)] {
                    let q = w.m(c + dc, r + dr)
                    if q.solid && q != .metal { t = q; cc = c + dc; break }
                }
            }
            if t == .root { return 0x5e3b26 }
            if t == .loose { return 0x86604a }
            if t == .seam { return 0x7a5a48 }
            return cc >= Landmarks.caveStart - 1 ? 0x55323d : 0x66412f
        }
        let i0 = max(0, c0 * K), i1 = min(w.dw - 2, (c1 + 1) * K - 1)
        let j0 = max(0, r0 * K), j1 = min(w.dh - 2, (r1 + 1) * K - 1)
        if i0 <= i1 && j0 <= j1 {
            for j in j0...j1 {
                for i in i0...i1 {
                    let tc = i / K, tr = j / K
                    let t = w.m(tc, tr)
                    let a = w.d(i, j), b = w.d(i + 1, j), d = w.d(i + 1, j + 1), e = w.d(i, j + 1)
                    if t == .metal || t == .plank { continue }
                    if a < 0.5 && b < 0.5 && d < 0.5 && e < 0.5 { continue }
                    if t == .air || t == .dug, [Backdrop.room, .shaft, .maint, .outpost, .sump, .transit].contains(w.bd(tc, tr)) { continue }
                    let x = CGFloat(i) / k, y = CGFloat(j) / k, s = 1 / k
                    let p = path(cellColor(tc, tr))
                    if a >= 0.5 && b >= 0.5 && d >= 0.5 && e >= 0.5 {
                        p.addRect(CGRect(x: x - 0.01, y: y - 0.01, width: s + 0.02, height: s + 0.02))
                        continue
                    }
                    let cs: [(CGFloat, CGFloat, Double)] = [(0, 0, a), (1, 0, b), (1, 1, d), (0, 1, e)]
                    var pts: [CGPoint] = []
                    var ep: [CGPoint] = []
                    for q in 0..<4 {
                        let (x0, y0, v0) = cs[q], (x1, y1, v1) = cs[(q + 1) % 4]
                        if v0 >= 0.5 { pts.append(CGPoint(x: x + x0 * s, y: y + y0 * s)) }
                        if (v0 >= 0.5) != (v1 >= 0.5) {
                            let tt = CGFloat((0.5 - v0) / (v1 - v0))
                            let pt = CGPoint(x: x + (x0 + (x1 - x0) * tt) * s, y: y + (y0 + (y1 - y0) * tt) * s)
                            pts.append(pt); ep.append(pt)
                        }
                    }
                    guard pts.count >= 3 else { continue }
                    p.addLines(between: pts); p.closeSubpath()
                    var q = 0
                    while q + 1 < ep.count {
                        let mx = Double((ep[q].x + ep[q + 1].x) / 2), my = Double((ep[q].y + ep[q + 1].y) / 2)
                        if !w.solid(mx, my - 0.12) { top.move(to: ep[q]); top.addLine(to: ep[q + 1]) }
                        else if !w.solid(mx, my + 0.12) { bot.move(to: ep[q]); bot.addLine(to: ep[q + 1]) }
                        q += 2
                    }
                }
            }
        }
        for (c, p) in fills {
            ctx.addPath(p); ctx.setFillColor(color(c)); ctx.fillPath()
        }
        ctx.setLineCap(.round)
        ctx.addPath(top); ctx.setStrokeColor(rimTop); ctx.setLineWidth(0.07); ctx.strokePath()
        ctx.addPath(bot); ctx.setStrokeColor(rimBottom); ctx.setLineWidth(0.05); ctx.strokePath()

        // Steel and details.
        for r in r0...r1 {
            for c in c0...c1 {
                let t = w.m(c, r)
                let X = CGFloat(c), Y = CGFloat(r)
                if t == .metal {
                    ctx.setFillColor(color(0x3d4049)); ctx.fill(CGRect(x: X - 0.01, y: Y - 0.01, width: 1.02, height: 1.02))
                    ctx.setFillColor(color(0x585e68)); ctx.fill(CGRect(x: X, y: Y, width: 1, height: 0.08))
                    ctx.setFillColor(color(0x000000, 0.3)); ctx.fill(CGRect(x: X, y: Y + 0.92, width: 1, height: 0.08))
                    ctx.setFillColor(color(0x626a74))
                    ctx.fill(CGRect(x: X + 0.15, y: Y + 0.3, width: 0.08, height: 0.08))
                    ctx.fill(CGRect(x: X + 0.77, y: Y + 0.3, width: 0.08, height: 0.08))
                } else if t == .plank {
                    ctx.setFillColor(color(0x000000, 0.25)); ctx.fill(CGRect(x: X - 0.03, y: Y + 0.3, width: 1.06, height: 0.06))
                    ctx.setFillColor(color(0x9a6a40)); ctx.fill(CGRect(x: X - 0.03, y: Y, width: 1.06, height: 0.31))
                    ctx.setFillColor(color(0xc8925c)); ctx.fill(CGRect(x: X - 0.03, y: Y, width: 1.06, height: 0.07))
                    ctx.setFillColor(color(0x6e4628)); ctx.fill(CGRect(x: X + 0.48, y: Y + 0.02, width: 0.03, height: 0.28))
                    ctx.setFillColor(color(0x3a3036))
                    ctx.fillEllipse(in: CGRect(x: X + 0.12, y: Y + 0.12, width: 0.07, height: 0.07))
                    ctx.fillEllipse(in: CGRect(x: X + 0.8, y: Y + 0.12, width: 0.07, height: 0.07))
                } else if t == .root {
                    // Bark: long dark grain lines and a few pale knots.
                    ctx.setStrokeColor(color(0x3a2216, 0.8)); ctx.setLineWidth(0.05)
                    for i in 0..<3 {
                        let ox = Double(c) + 0.15 + Double(i) * 0.3, oy = Double(r) + hash2(c + i, r) * 0.3
                        if w.solid(ox, oy + 0.3) {
                            ctx.move(to: CGPoint(x: ox, y: oy)); ctx.addQuadCurve(to: CGPoint(x: ox + 0.12, y: oy + 0.8), control: CGPoint(x: ox - 0.12, y: oy + 0.4))
                        }
                    }
                    ctx.strokePath()
                    if hash2(c, r * 7) < 0.35 && w.solid(Double(c) + 0.5, Double(r) + 0.5) {
                        ctx.setFillColor(color(0x8a5c3a)); ctx.fillEllipse(in: CGRect(x: X + 0.4, y: Y + 0.4, width: 0.18, height: 0.12))
                    }
                } else if t == .loose || t == .seam {
                    ctx.setFillColor(color(0xffe6c8, 0.14))
                    for i in 0..<4 {
                        let px = Double(c) + 0.08 + hash2(c * 4 + i, r) * 0.8, py = Double(r) + 0.08 + hash2(r * 3 + i, c) * 0.8
                        if w.solid(px, py) { ctx.fill(CGRect(x: px, y: py, width: 0.09, height: 0.09)) }
                    }
                }
            }
        }
        // Finds showing through the earth: little flecks of colour where something is buried.
        for b in w.buried where !b.revealed && b.id != "crystal" && b.pos.x >= Double(c0) - 1 && b.pos.x <= Double(c1) + 2 && b.pos.y >= Double(r0) - 1 && b.pos.y <= Double(r1) + 2 {
            let col: UInt32
            switch b.item.id {
            case .copperOre: col = 0x4fc9a0
            case .ironOre: col = 0xc0624a
            case .quartz: col = 0xdff2ff
            case .spores: col = 0x8affc0
            case .coin: col = 0xe8c25a
            default: col = 0xcbb89a
            }
            let n = [.copperOre, .ironOre, .quartz].contains(b.item.id) ? 4 : 2
            for i in 0..<n {
                let px = b.pos.x - 0.25 + hash2(Int(b.pos.x * 10) + i, 3) * 0.5, py = b.pos.y - 0.25 + hash2(Int(b.pos.y * 10) + i, 7) * 0.5
                guard w.solid(px, py) else { continue }
                let s: CGFloat = 0.07 + CGFloat(hash2(i, Int(b.pos.x))) * 0.07
                ctx.setFillColor(color(col, 0.85)); ctx.fillEllipse(in: CGRect(x: px, y: py, width: s, height: s))
            }
        }
        return ctx.makeImage()
    }

    // MARK: parallax layers

    struct Layer { var f: Double; var k: Double; var image: CGImage; var origin: CGPoint; var pxPerUnit: CGFloat }

    /// Where the parallax layers line up with the world.
    static let parallaxAnchorX = 130.0

    /// The far cavern in three hazy layers of rock: a ceiling hung with stalactites, a floor of stalagmites,
    /// columns where the two have met, and arches in the distance. Rendered once.
    static func parallaxLayers() -> [Layer] {
        let specs: [(Double, Double, UInt32, UInt32, CGFloat)] = [(0.18, 0.55, 0x4e3f4a, 0x7a6070, 0.22), (0.42, 0.75, 0x33262f, 0x5a4250, 0.16), (0.68, 0.9, 0x20171d, 0x2e2128, 0.1)]
        var out: [Layer] = []
        for (li, s) in specs.enumerated() {
            let ppu: CGFloat = 6
            let x0: CGFloat = -20, y0: CGFloat = -30, wU: CGFloat = 320, hU: CGFloat = 120
            guard let ctx = CGContext(data: nil, width: Int(wU * ppu), height: Int(hU * ppu), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.translateBy(x: 0, y: hU * ppu); ctx.scaleBy(x: ppu, y: -ppu); ctx.translateBy(x: -x0, y: -y0)
            ctx.setFillColor(color(s.2)); ctx.setStrokeColor(color(s.2))
            let L = Double(li)
            let topY: Double = li == 0 ? 6 : li == 1 ? 3 : 0
            let botY: Double = li == 0 ? 44 : li == 1 ? 47 : 50
            let xa = -20.0, xb = 300.0
            // Ceiling: a lumpy rock mass with stalactites hanging from it.
            let top = CGMutablePath(); top.move(to: CGPoint(x: xa, y: -30))
            var x = xa
            while x <= xb {
                let n = hash2(Int(x * 7), li * 99)
                let base = topY + 2.5 * sin(x * 0.07 + L) + n * 1.5
                top.addLine(to: CGPoint(x: x, y: base))
                if n > 0.45 {
                    // a stalactite: narrow, long, slightly crooked
                    let len = 2 + n * (li == 2 ? 6 : 9), w = 0.5 + n * 1.1
                    top.addLine(to: CGPoint(x: x + w * 0.45, y: base + len * 0.55))
                    top.addLine(to: CGPoint(x: x + w * 0.55 + 0.2, y: base + len))
                    top.addLine(to: CGPoint(x: x + w, y: base + 0.3))
                }
                x += 1.6 + n * 1.4
            }
            top.addLine(to: CGPoint(x: xb, y: -30)); top.closeSubpath()
            // Floor: rubble humps with stalagmites.
            let bot = CGMutablePath(); bot.move(to: CGPoint(x: xa, y: 90))
            x = xa
            while x <= xb {
                let n = hash2(Int(x * 5), li * 77)
                let base = botY - 2 * sin(x * 0.05 + L * 2) - n * 1.2
                bot.addLine(to: CGPoint(x: x, y: base))
                if n > 0.6 {
                    let len = 1.5 + n * (li == 2 ? 4 : 7), w = 0.9 + n * 1.4
                    bot.addLine(to: CGPoint(x: x + w * 0.45, y: base - len))
                    bot.addLine(to: CGPoint(x: x + w, y: base))
                }
                x += 2 + n * 1.6
            }
            bot.addLine(to: CGPoint(x: xb, y: 90)); bot.closeSubpath()
            ctx.addPath(top); ctx.addPath(bot); ctx.fillPath()
            // Columns where a stalactite and stalagmite met: pinched in the middle.
            func column(_ cx: Double, _ wd: Double) {
                let p = CGMutablePath()
                let t0 = topY + 2, b0 = botY - 1, mid = (t0 + b0) / 2
                p.move(to: CGPoint(x: cx - wd, y: t0))
                p.addQuadCurve(to: CGPoint(x: cx - wd * 0.22, y: mid), control: CGPoint(x: cx - wd * 0.3, y: t0 + (mid - t0) * 0.5))
                p.addQuadCurve(to: CGPoint(x: cx - wd * 1.1, y: b0), control: CGPoint(x: cx - wd * 0.3, y: mid + (b0 - mid) * 0.6))
                p.addLine(to: CGPoint(x: cx + wd * 1.1, y: b0))
                p.addQuadCurve(to: CGPoint(x: cx + wd * 0.22, y: mid), control: CGPoint(x: cx + wd * 0.3, y: mid + (b0 - mid) * 0.6))
                p.addQuadCurve(to: CGPoint(x: cx + wd, y: t0), control: CGPoint(x: cx + wd * 0.3, y: t0 + (mid - t0) * 0.5))
                p.closeSubpath(); ctx.addPath(p); ctx.fillPath()
            }
            // Arches in the far wall: dark mouths of other passages.
            func arch(_ cx: Double, _ by: Double, _ wd: Double, _ h: Double) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: cx - wd / 2 - 3, y: by)); p.addLine(to: CGPoint(x: cx - wd / 2 - 3, y: by - h - 3))
                p.addLine(to: CGPoint(x: cx + wd / 2 + 3, y: by - h - 3)); p.addLine(to: CGPoint(x: cx + wd / 2 + 3, y: by))
                p.addLine(to: CGPoint(x: cx + wd / 2, y: by))
                p.addQuadCurve(to: CGPoint(x: cx - wd / 2, y: by), control: CGPoint(x: cx, y: by - h * 2))
                p.closeSubpath(); ctx.addPath(p); ctx.fillPath()
            }
            switch li {
            case 0:
                arch(118, 44, 10, 14); arch(150, 44, 7, 10); column(98, 2.2); column(176, 3)
            case 1:
                column(112, 1.8); column(141, 2.6); column(166, 1.4)
            default:
                column(127, 1.6); column(184, 2.2)
            }
            // atmospheric haze over the layer
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(color(s.3, s.4)); ctx.fill(CGRect(x: -20, y: -30, width: 320, height: 120))
            if let img = ctx.makeImage() { out.append(Layer(f: s.0, k: s.1, image: img, origin: CGPoint(x: x0, y: y0), pxPerUnit: ppu)) }
        }
        return out
    }
}
