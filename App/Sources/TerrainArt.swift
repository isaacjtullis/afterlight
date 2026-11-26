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
        return ctx.makeImage()
    }

    // MARK: parallax layers

    struct Layer { var f: Double; var k: Double; var image: CGImage; var origin: CGPoint; var pxPerUnit: CGFloat }

    /// Distant machinery silhouettes in three hazy layers, rendered once.
    static func parallaxLayers() -> [Layer] {
        let specs: [(Double, Double, UInt32, UInt32, CGFloat)] = [(0.18, 0.55, 0xa0636a, 0xc8826e, 0.16), (0.42, 0.75, 0x6c3b49, 0xa05c56, 0.14), (0.68, 0.9, 0x432433, 0x5a2e3a, 0.12)]
        var out: [Layer] = []
        for (li, s) in specs.enumerated() {
            let ppu: CGFloat = 6
            let x0: CGFloat = -60, y0: CGFloat = -30, wU: CGFloat = 320, hU: CGFloat = 120
            guard let ctx = CGContext(data: nil, width: Int(wU * ppu), height: Int(hU * ppu), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.translateBy(x: 0, y: hU * ppu); ctx.scaleBy(x: ppu, y: -ppu); ctx.translateBy(x: -x0, y: -y0)
            ctx.setFillColor(color(s.2)); ctx.setStrokeColor(color(s.2))
            // ceiling teeth and floor
            let topY: Double = li == 0 ? 2 : li == 1 ? 0 : -2
            let botY: Double = li == 0 ? 44 : li == 1 ? 47 : 50
            let topP = CGMutablePath(); topP.move(to: CGPoint(x: -60, y: -30))
            var x = -60.0
            while x <= 260 { let n = hash2(Int(x * 7), li * 99); topP.addLine(to: CGPoint(x: x, y: topY + n * 4 + (n > 0.8 ? 7 * n : 0))); x += 2.5 }
            topP.addLine(to: CGPoint(x: 260, y: -30)); topP.closeSubpath()
            let botP = CGMutablePath(); botP.move(to: CGPoint(x: -60, y: 90))
            x = -60
            while x <= 260 { let n = hash2(Int(x * 5), li * 77); botP.addLine(to: CGPoint(x: x, y: botY - n * 3 - (n > 0.85 ? 5 : 0))); x += 3 }
            botP.addLine(to: CGPoint(x: 260, y: 90)); botP.closeSubpath()
            ctx.addPath(topP); ctx.addPath(botP); ctx.fillPath()
            func tower(_ x: Double, _ b: Double, _ wd: Double, _ h: Double) {
                let p = CGMutablePath()
                p.addLines(between: [CGPoint(x: x - wd / 2, y: b), CGPoint(x: x - wd / 2, y: b - h * 0.72), CGPoint(x: x - wd * 0.28, y: b - h),
                                     CGPoint(x: x + wd * 0.28, y: b - h), CGPoint(x: x + wd / 2, y: b - h * 0.72), CGPoint(x: x + wd / 2, y: b)])
                p.closeSubpath(); ctx.addPath(p); ctx.fillPath()
            }
            func derrick(_ x: Double, _ b: Double, _ wd: Double, _ h: Double, _ lw: CGFloat) {
                ctx.setLineWidth(lw)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x - wd / 2, y: b)); p.addLine(to: CGPoint(x: x - wd * 0.08, y: b - h))
                p.move(to: CGPoint(x: x + wd / 2, y: b)); p.addLine(to: CGPoint(x: x + wd * 0.08, y: b - h))
                for i in 1..<6 {
                    let y = b - h * Double(i) / 6, hw = wd / 2 * (1 - Double(i) / 6 * 0.84)
                    p.move(to: CGPoint(x: x - hw, y: y)); p.addLine(to: CGPoint(x: x + hw, y: y - h / 12))
                    p.move(to: CGPoint(x: x + hw, y: y)); p.addLine(to: CGPoint(x: x - hw, y: y - h / 12))
                }
                ctx.addPath(p); ctx.strokePath()
            }
            switch li {
            case 0:
                tower(70, 44, 7, 26); tower(98, 44, 5, 34); tower(128, 44, 9, 20); derrick(84, 44, 8, 30, 0.5); derrick(140, 44, 6, 24, 0.5)
                let ring = CGMutablePath(); ring.addLines(between: [CGPoint(x: 108, y: 24), CGPoint(x: 113, y: 18), CGPoint(x: 120, y: 18), CGPoint(x: 124, y: 24), CGPoint(x: 120, y: 30), CGPoint(x: 113, y: 30)]); ring.closeSubpath()
                ctx.addPath(ring); ctx.fillPath()
            case 1:
                tower(63, 47, 4, 17); tower(96, 47, 16, 12); derrick(116, 47, 10, 26, 0.6); tower(138, 47, 17, 10)
                ctx.setLineWidth(0.7)
                let g = CGMutablePath(); g.move(to: CGPoint(x: 70, y: 14)); g.addLine(to: CGPoint(x: 70, y: 30)); g.move(to: CGPoint(x: 64, y: 14)); g.addLine(to: CGPoint(x: 98, y: 14)); g.move(to: CGPoint(x: 92, y: 14)); g.addLine(to: CGPoint(x: 92, y: 20))
                ctx.addPath(g); ctx.strokePath()
            default:
                tower(74, 50, 17, 8); tower(111, 50, 19, 6)
                ctx.setLineWidth(0.8)
                let g = CGMutablePath(); g.move(to: CGPoint(x: 92, y: 50)); g.addLine(to: CGPoint(x: 98, y: 36)); g.addLine(to: CGPoint(x: 108, y: 38)); g.move(to: CGPoint(x: 124, y: 50)); g.addLine(to: CGPoint(x: 124, y: 34))
                ctx.addPath(g); ctx.strokePath()
            }
            // atmospheric haze over the layer
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(color(s.3, s.4)); ctx.fill(CGRect(x: -60, y: -30, width: 320, height: 120))
            if let img = ctx.makeImage() { out.append(Layer(f: s.0, k: s.1, image: img, origin: CGPoint(x: x0, y: y0), pxPerUnit: ppu)) }
        }
        return out
    }
}
