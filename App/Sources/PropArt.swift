import CoreGraphics
import SpriteKit
import AfterlightCore

/// Shared generated textures and drawings of props.
enum Art {
    static func image(widthTiles w: CGFloat, heightTiles h: CGFloat, ppt: CGFloat = 40, originX ox: CGFloat, originY oy: CGFloat,
                      _ draw: (CGContext) -> Void) -> CGImage? {
        let pw = max(2, Int(w * ppt)), ph = max(2, Int(h * ppt))
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(ph)); ctx.scaleBy(x: ppt, y: -ppt)
        ctx.translateBy(x: ox, y: oy)
        draw(ctx)
        return ctx.makeImage()
    }

    static let radial: SKTexture = {
        let s = 128
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [TerrainArt.color(0xffffff, 1), TerrainArt.color(0xffffff, 0.5), TerrainArt.color(0xffffff, 0)] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 0, endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    static let circle: SKTexture = {
        let s = 32
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(TerrainArt.color(0xffffff)); ctx.fillEllipse(in: CGRect(x: 1, y: 1, width: 30, height: 30))
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    static let star: SKTexture = {
        let s = 96, h = CGFloat(s) / 2
        let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let k = h * 0.1
        let p = CGMutablePath()
        p.move(to: CGPoint(x: h, y: 0)); p.addQuadCurve(to: CGPoint(x: 2 * h, y: h), control: CGPoint(x: h + k, y: h - k))
        p.addQuadCurve(to: CGPoint(x: h, y: 2 * h), control: CGPoint(x: h + k, y: h + k))
        p.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: h - k, y: h + k))
        p.addQuadCurve(to: CGPoint(x: h, y: 0), control: CGPoint(x: h - k, y: h - k))
        ctx.addPath(p); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [TerrainArt.color(0xffffff), TerrainArt.color(0xe8d4ff, 0.95), TerrainArt.color(0xaa78ff, 0)] as CFArray, locations: [0, 0.3, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: h, y: h), startRadius: 0, endCenter: CGPoint(x: h, y: h), endRadius: h, options: [])
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    static func c(_ h: UInt32, _ a: CGFloat = 1) -> CGColor { TerrainArt.color(h, a) }

    /// Draws a prop with its base at (0,0), in tiles, y down.
    static func drawProp(_ ctx: CGContext, _ p: Prop, crop: Double, powered: Bool) {
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ col: UInt32, _ a: CGFloat = 1) { ctx.setFillColor(c(col, a)); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        switch p.kind {
        case .workbench:
            rect(-1.35, -2.65, 2.6, 1.1, 0x34313b)
            ActorArt.line(ctx, [CGPoint(x: -0.85, y: -2.4), CGPoint(x: -0.85, y: -1.7)], c(0x3a3f47), 0.06)
            ActorArt.line(ctx, [CGPoint(x: -0.35, y: -2.45), CGPoint(x: -0.15, y: -1.75)], c(0x3a3f47), 0.06)
            ActorArt.line(ctx, [CGPoint(x: 0.65, y: -2.4), CGPoint(x: 0.65, y: -1.9)], c(0x3a3f47), 0.06)
            rect(-1.4, -0.92, 2.85, 0.14, 0x4a3828); rect(-1.4, -0.78, 2.85, 0.05, 0x2c2119)
            rect(-1.25, -0.73, 0.12, 0.73, 0x2c2119); rect(1.2, -0.73, 0.12, 0.73, 0x2c2119); rect(-0.65, -0.55, 1.2, 0.55, 0x2a221c)
            rect(1.0, -1.2, 0.3, 0.28, 0x3b4148)
            if p.flags.contains("flashlight") { rect(-0.35, -1.14, 0.55, 0.2, 0x4a4f55); rect(0.17, -1.18, 0.12, 0.28, 0x6e747a) }
        case .locker, .buckledLocker:
            rect(-0.42, -1.9, 0.84, 1.9, p.kind == .buckledLocker ? 0x4a4038 : 0x4b5560)
            rect(-0.34, -1.8, 0.68, 0.05, 0x000000, 0.25); rect(-0.34, -1.0, 0.68, 0.05, 0x000000, 0.25)
            rect(0.22, -1.05, 0.06, 0.2, 0xc8b089)
            if p.kind == .buckledLocker { ActorArt.line(ctx, [CGPoint(x: -0.4, y: -1.3), CGPoint(x: 0.1, y: -0.9), CGPoint(x: 0.4, y: -1.4)], c(0x2a221c), 0.06) }
            if p.stock.isEmpty && p.kind == .locker { rect(-0.34, -1.75, 0.68, 1.6, 0x15181c, 0.8) }
        case .bed:
            rect(-1.1, -0.65, 2.3, 0.32, 0x3b3442); rect(-1.05, -0.8, 0.7, 0.22, 0xd9cfc0); rect(-0.3, -0.72, 1.45, 0.2, 0x8a3a36)
            rect(-1.0, -0.33, 0.08, 0.33, 0x24222a); rect(1.05, -0.33, 0.08, 0.33, 0x24222a)
        case .storage:
            rect(-0.6, -0.9, 1.2, 0.9, 0x6b4f3a); rect(-0.6, -0.9, 1.2, 0.12, 0x87674c); rect(-0.08, -0.6, 0.16, 0.2, 0xc9a86a)
        case .liftCar:
            // A lift cabin that came down the shaft and folded on landing. The drive gear sits on its roof.
            ctx.saveGState(); ctx.rotate(by: -0.12)
            rect(-2.3, -3.1, 4.6, 3.0, 0x3a3540); rect(-2.3, -3.1, 4.6, 0.18, 0x4f4858)
            rect(-2.05, -2.8, 1.5, 1.3, 0x18161c); rect(0.45, -2.8, 1.5, 1.3, 0x18161c)
            ActorArt.line(ctx, [CGPoint(x: -1.9, y: -2.7), CGPoint(x: -0.7, y: -1.6)], c(0x8f96a0, 0.5), 0.03)   // cracked pane
            rect(-0.12, -2.95, 0.24, 2.85, 0x2c2832)                                                            // door seam
            rect(-2.3, -0.32, 4.6, 0.26, 0x4a4450)
            ActorArt.line(ctx, [CGPoint(x: 1.6, y: -3.1), CGPoint(x: 1.9, y: -4.4), CGPoint(x: 1.5, y: -5.2)], c(0x5a5560), 0.06)   // snapped cable
            ctx.restoreGState()
            ctx.saveGState(); ctx.translateBy(x: -0.9, y: -3.35); ctx.rotate(by: -0.12)
            ActorArt.dot(ctx, 0, 0, 0.5, c(0x55505c)); ActorArt.dot(ctx, 0, 0, 0.18, c(0x2a2730))
            let hasTooth = p.stock.contains { $0.id == .liftTooth }
            for i in 0..<8 {
                let a = CGFloat(i) * .pi / 4
                ctx.saveGState(); ctx.rotate(by: a)
                rect(0.42, -0.09, 0.22, 0.18, i == 6 && hasTooth ? 0xd8dee6 : 0x6a6470)
                ctx.restoreGState()
            }
            if hasTooth { ActorArt.dot(ctx, -0.05, -0.62, 0.07, c(0xfff1d0, 0.9)) }
            ctx.restoreGState()
        case .pantry:
            // A shelf of tins over a water drum with a tin cup on a hook.
            rect(-0.55, -1.75, 1.1, 0.08, 0x5a3a24); rect(-0.55, -1.35, 1.1, 0.08, 0x5a3a24)
            rect(-0.5, -1.75, 0.06, 0.48, 0x3a2418); rect(0.44, -1.75, 0.06, 0.48, 0x3a2418)
            let tins = p.stock.first(where: { $0.id == .ration })?.count ?? 0
            for k in 0..<min(6, tins) { rect(-0.46 + CGFloat(k % 3) * 0.3, k < 3 ? -1.62 : -2.02, 0.22, 0.27, k % 2 == 0 ? 0x9aa2a8 : 0xb0a070) }
            ctx.setFillColor(c(0x3f5a66)); ActorArt.rr(ctx, -0.42, -0.95, 0.84, 0.95, 0.12); ctx.fillPath()
            rect(-0.42, -0.72, 0.84, 0.05, 0x2c4048); rect(-0.42, -0.3, 0.84, 0.05, 0x2c4048)
            rect(0.22, -0.55, 0.1, 0.12, 0xb8bcc0)                                                    // tap
            ActorArt.dot(ctx, 0.27, -0.38, 0.03, c(0x8fd0ff, 0.8))
        case .pile:
            // Whatever Max set down, in a little heap on a cloth.
            ctx.setFillColor(c(0x6e5a48)); ctx.fillEllipse(in: CGRect(x: -0.45, y: -0.12, width: 0.9, height: 0.16))
            ctx.setFillColor(c(0x8a7660)); ActorArt.rr(ctx, -0.25, -0.38, 0.5, 0.3, 0.1); ctx.fillPath()
            ActorArt.dot(ctx, 0.12, -0.42, 0.1, c(0xa7adb3))
        case .crate:
            // An old tool crate: slats, a rope coiled on the lid, a stencilled mark.
            rect(-0.75, -0.95, 1.5, 0.95, 0x6e4a2e)
            for k in 0..<3 { rect(-0.75, -0.92 + CGFloat(k) * 0.31, 1.5, 0.04, 0x4e3220) }
            rect(-0.75, -0.95, 0.12, 0.95, 0x5a3a24); rect(0.63, -0.95, 0.12, 0.95, 0x5a3a24)
            ActorArt.line(ctx, [CGPoint(x: -0.62, y: -0.06), CGPoint(x: 0.6, y: -0.9)], c(0x5a3a24), 0.08)
            rect(-0.2, -0.62, 0.4, 0.14, 0xc9a86a, 0.55)
            if !p.stock.isEmpty {
                ctx.setStrokeColor(c(0xb89a6a)); ctx.setLineWidth(0.06)
                ctx.strokeEllipse(in: CGRect(x: -0.45, y: -1.12, width: 0.6, height: 0.2))
                ctx.strokeEllipse(in: CGRect(x: -0.38, y: -1.08, width: 0.46, height: 0.13))
            }
        case .drillRig:
            // A tracked boring machine nosed into the slope: treads, a riveted cab, a spiral auger, a dead work lamp.
            let line = { (pts: [CGPoint], col: UInt32, w: CGFloat) in ActorArt.line(ctx, pts, c(col), w) }
            // struts down to wherever the ground is
            line([CGPoint(x: -2.4, y: -0.3), CGPoint(x: -2.7, y: 1.4)], 0x2a2730, 0.16)
            line([CGPoint(x: 1.6, y: -0.3), CGPoint(x: 1.9, y: 1.4)], 0x2a2730, 0.16)
            // tread
            ctx.setFillColor(c(0x221f26)); ActorArt.rr(ctx, -2.9, -0.75, 5.0, 0.75, 0.37); ctx.fillPath()
            for i in 0..<6 { ActorArt.dot(ctx, -2.5 + CGFloat(i) * 0.84, -0.37, 0.26, c(0x3b3640)); ActorArt.dot(ctx, -2.5 + CGFloat(i) * 0.84, -0.37, 0.08, c(0x18161c)) }
            for i in 0..<14 { rect(-2.8 + CGFloat(i) * 0.35, -0.8, 0.14, 0.08, 0x3b3640) }
            // body and cab
            rect(-2.6, -2.0, 4.2, 1.25, 0x4a3f3a); rect(-2.6, -2.0, 4.2, 0.12, 0x6a5a50)
            for i in 0..<8 { rect(-2.4 + CGFloat(i) * 0.5, -1.4, 0.32, 0.1, i % 2 == 0 ? 0xd4a03a : 0x2a2420) }   // warning stripe
            rect(-2.4, -3.1, 1.6, 1.1, 0x3d3540); rect(-2.2, -2.95, 1.1, 0.62, 0x15131a)
            ActorArt.line(ctx, [CGPoint(x: -2.1, y: -2.9), CGPoint(x: -1.5, y: -2.45)], c(0x8f96a0, 0.4), 0.03)
            for i in 0..<5 { ActorArt.dot(ctx, -2.45 + CGFloat(i) * 0.95, -1.88, 0.04, c(0x8a7a6a)) }
            // exhaust and lamp
            rect(-0.5, -3.0, 0.22, 1.0, 0x2a2730); rect(-0.56, -3.1, 0.34, 0.12, 0x3b3640)
            ActorArt.line(ctx, [CGPoint(x: -0.9, y: -3.1), CGPoint(x: -0.7, y: -3.5)], c(0x2a2730), 0.05)
            ActorArt.dot(ctx, -0.7, -3.58, 0.13, c(0x6a6470)); ActorArt.dot(ctx, -0.7, -3.58, 0.07, c(0x9a8a70))
            // auger housing and spiral bit
            rect(1.6, -1.85, 0.5, 1.0, 0x3b3640)
            ctx.setFillColor(c(0x5c5560))
            ctx.addLines(between: [CGPoint(x: 2.1, y: -1.8), CGPoint(x: 4.3, y: -1.32), CGPoint(x: 2.1, y: -0.9)]); ctx.closePath(); ctx.fillPath()
            for i in 0..<5 {
                let x = 2.25 + CGFloat(i) * 0.4, k = 1 - CGFloat(i) * 0.19
                ActorArt.line(ctx, [CGPoint(x: x, y: -1.32 - 0.42 * k), CGPoint(x: x + 0.28, y: -1.32 + 0.42 * k)], c(0x8f8a94), 0.07)
            }
            ActorArt.dot(ctx, 4.3, -1.32, 0.05, c(0xd8dee6))
        case .gantry:
            // An A-frame lifting gantry: lattice legs, a riveted beam, a trolley, chain and hook.
            let L = { (a: CGPoint, b: CGPoint, w: CGFloat, col: UInt32) in ActorArt.line(ctx, [a, b], c(col), w) }
            for side in [-1.0, 1.0] as [CGFloat] {
                let footO = CGPoint(x: side * 2.6, y: 1.2), footI = CGPoint(x: side * 1.7, y: 1.2)
                let topO = CGPoint(x: side * 2.0, y: -6), topI = CGPoint(x: side * 1.6, y: -6)
                L(footO, topO, 0.16, 0x3b3640); L(footI, topI, 0.12, 0x3b3640)
                for k in 0..<8 {
                    let u0 = CGFloat(k) / 8, u1 = CGFloat(k + 1) / 8
                    let a = CGPoint(x: footO.x + (topO.x - footO.x) * u0, y: footO.y + (topO.y - footO.y) * u0)
                    let b = CGPoint(x: footI.x + (topI.x - footI.x) * u1, y: footI.y + (topI.y - footI.y) * u1)
                    L(a, b, 0.05, 0x2f2b34)
                }
                rect(side * 2.6 - 0.35, 1.1, 0.7, 0.18, 0x2a2730)   // foot plate
            }
            rect(-2.5, -6.45, 5.0, 0.5, 0x45404c); rect(-2.5, -6.45, 5.0, 0.08, 0x5f5866)
            for i in 0..<10 { ActorArt.dot(ctx, -2.3 + CGFloat(i) * 0.51, -6.2, 0.04, c(0x8a8090)) }
            rect(0.25, -5.95, 0.7, 0.35, 0x2a2730)                      // trolley
            var y: CGFloat = -5.6
            while y < -2.9 { ctx.setStrokeColor(c(0x6a6470)); ctx.setLineWidth(0.04); ctx.strokeEllipse(in: CGRect(x: 0.53, y: y, width: 0.14, height: 0.2)); y += 0.18 }
            ActorArt.line(ctx, [CGPoint(x: 0.6, y: -2.9), CGPoint(x: 0.6, y: -2.6), CGPoint(x: 0.85, y: -2.45), CGPoint(x: 0.9, y: -2.7)], c(0x8a8490), 0.08)
            rect(0.35, -3.05, 0.5, 0.18, 0xd4a03a)                     // hook block
        case .pump:
            rect(-0.35, -1.3, 0.7, 1.3, 0x45505a); rect(-0.15, -1.9, 0.3, 0.6, 0x55606a)
            ActorArt.line(ctx, [CGPoint(x: 0, y: -1.85), CGPoint(x: 0.7, y: -2.1)], c(0x8a6440), 0.08)
            ActorArt.dot(ctx, -0.0, -0.95, 0.16, c(p.flags.contains("fixed") ? 0xf2efe6 : 0x6a6e72))
        case .batteryBank:
            for i in 0..<3 { rect(-0.9 + CGFloat(i) * 0.62, -1.2, 0.5, 1.2, 0x2f3a33) }
            ActorArt.dot(ctx, 0.85, -1.5, 0.08, c(powered ? 0x9cff9c : 0x3a1a1a))
        case .warmPipe:
            rect(0, -0.12, 44, 0.22, 0x7a4e3a); rect(0, -0.12, 44, 0.05, 0xc9805a, 0.6)
        case .lamp:
            if p.flags.contains("torch") {
                // A root torch: a knotted stake with a resin-soaked head burning.
                ActorArt.line(ctx, [CGPoint(x: -0.02, y: 0), CGPoint(x: 0.04, y: -1.0)], c(0x6e4529), 0.1)
                ctx.setFillColor(c(0x3a2214)); ActorArt.rr(ctx, -0.1, -1.22, 0.24, 0.26, 0.08); ctx.fillPath()
                ActorArt.dot(ctx, 0.02, -1.36, 0.13, c(0xff9a3a)); ActorArt.dot(ctx, 0.02, -1.42, 0.08, c(0xffe08a))
            } else {
                // A lantern on a stake: handle, cap, glass, flame.
                rect(-0.04, -1.0, 0.08, 1.0, 0x2c2724)
                ActorArt.line(ctx, [CGPoint(x: -0.1, y: -1.5), CGPoint(x: 0, y: -1.62), CGPoint(x: 0.1, y: -1.5)], c(0x2c2724), 0.04)
                rect(-0.17, -1.52, 0.34, 0.07, 0x2c2724)
                rect(-0.15, -1.45, 0.3, 0.38, 0x2c2724); rect(-0.11, -1.41, 0.22, 0.3, 0xffd08a)
                ActorArt.dot(ctx, 0, -1.26, 0.06, c(0xfff4d0))
                rect(-0.18, -1.08, 0.36, 0.07, 0x2c2724)
            }
        case .planter:
            rect(-0.8, -0.35, 1.6, 0.35, 0x4a2f24); rect(-0.8, -0.38, 1.6, 0.06, 0x6b4636)
            if crop > 0 {
                let h = CGFloat(0.15 + 0.6 * crop)
                for i in 0..<4 {
                    let x = -0.55 + CGFloat(i) * 0.37
                    ActorArt.line(ctx, [CGPoint(x: x, y: -0.35), CGPoint(x: x + 0.05, y: -0.35 - h)], c(0x6f9a52), 0.06)
                    ActorArt.dot(ctx, x + 0.08, -0.35 - h, 0.07 + 0.08 * CGFloat(crop), c(crop >= 1 ? 0x8cc46a : 0x7aa85a))
                }
            }
        case .waterTank:
            rect(-0.6, -1.6, 1.2, 1.6, 0x55606a); rect(-0.6, -1.6, 1.2, 0.12, 0x6b7682); rect(-0.5, -0.9, 1.0, 0.6, 0x3f7fa0, 0.55)
        case .outpostDoor:
            break
        case .maraTap:
            rect(-0.08, -1.6, 0.16, 1.1, 0x55606a); rect(-0.08, -1.6, 0.45, 0.14, 0x6b7682); rect(0.28, -1.6, 0.1, 0.25, 0x6b7682)
            ActorArt.dot(ctx, 0.0, -1.0, 0.12, c(0xb08a4a))
            rect(-0.45, -0.32, 0.95, 0.32, 0x3f3a36); rect(-0.4, -0.3, 0.85, 0.06, 0x2a2622)
            if p.flags.contains("flowing") { rect(0.3, -1.35, 0.06, 1.0, 0x8fc7e0, 0.7); rect(-0.38, -0.25, 0.8, 0.12, 0x5fa0c0, 0.6) }
        case .maraPump:
            rect(-0.5, -1.4, 1.0, 1.4, 0x4f4a44); rect(-0.42, -1.32, 0.84, 0.2, 0x6b625a)
            rect(0.5, -0.9, 1.4, 0.18, 0x55606a)
            ActorArt.line(ctx, [CGPoint(x: -0.1, y: -1.4), CGPoint(x: -0.1, y: -2.0), CGPoint(x: 0.5, y: -2.25)], c(0x8a6440), 0.08)
            ActorArt.dot(ctx, 0.15, -0.75, 0.17, c(p.flags.contains("running") ? 0xf2efe6 : 0x6a6e72))
            ActorArt.dot(ctx, 0.15, -0.75, 0.05, c(p.flags.contains("running") ? 0x3f7fa0 : 0x3a1a1a))
        case .maraShelf:
            rect(-0.9, -2.0, 1.8, 0.08, 0x6b4f3a); rect(-0.9, -1.2, 1.8, 0.08, 0x6b4f3a)
            rect(-0.85, -2.0, 0.06, 2.0, 0x4f392d); rect(0.8, -2.0, 0.06, 2.0, 0x4f392d)
            rect(-0.6, -1.45, 0.3, 0.25, 0x55606a); rect(0.25, -2.3, 0.4, 0.3, 0x8a6440)
            if !p.stock.isEmpty { ActorArt.dot(ctx, -0.05, -1.32, 0.14, c(0xc9a24a)); rect(-0.2, -1.36, 0.3, 0.08, 0xa8842e) }
        case .maraLift:
            rect(-1.3, -4.9, 0.12, 4.9, 0x3b3640); rect(1.2, -4.9, 0.12, 4.9, 0x3b3640)
            rect(-1.1, -2.5, 2.2, 2.5, p.flags.contains("repaired") ? 0x4a4a52 : 0x3a3540, 0.9)
            for i in 0..<4 { rect(-1.1 + CGFloat(i) * 0.7, -2.5, 0.06, 2.5, 0x58505c) }
            rect(-1.3, -5.0, 2.6, 0.2, 0x4a4450)
            ActorArt.dot(ctx, 1.0, -2.9, 0.09, c(p.flags.contains("repaired") ? 0x9cff9c : 0xff6a4a))
        case .transitLift:
            rect(-1.3, -1.9, 0.12, 1.9, 0x3b3640); rect(1.2, -1.9, 0.12, 1.9, 0x3b3640); rect(-1.3, -1.95, 2.6, 0.15, 0x4a4450)
            ActorArt.dot(ctx, 1.0, -1.4, 0.08, c(p.flags.contains("repaired") ? 0x9cff9c : 0x6a6e72))
        case .sumpHatch:
            if p.flags.contains("open") {
                rect(-0.5, -0.06, 0.12, 0.06, 0x8a8f96); rect(0.38, -0.06, 0.12, 0.06, 0x8a8f96)
                rect(0.5, -0.95, 0.08, 0.9, 0x6b7076)
            } else {
                rect(-0.5, -0.1, 1.0, 0.1, 0x6b7076); rect(-0.1, -0.16, 0.2, 0.08, 0xc9a24a)
            }
        case .intake:
            rect(-0.6, -0.7, 1.2, 0.7, 0x45505a); rect(-0.5, -0.6, 1.0, 0.45, 0x2a2e33)
            if p.flags.contains("clogged") { for i in 0..<5 { ActorArt.dot(ctx, -0.4 + CGFloat(i) * 0.2, -0.35, 0.12, c(0x5a4232)) } }
        case .sunkValve:
            if !p.stock.isEmpty { ActorArt.dot(ctx, 0, -0.18, 0.2, c(0xc9a24a)); rect(-0.32, -0.22, 0.64, 0.1, 0xa8842e) }
        case .chimney:
            rect(-0.9, -2.2, 0.08, 0.5, 0x5a4a3a); rect(0.82, -2.2, 0.08, 0.5, 0x5a4a3a)
        case .signalLamp:
            // A platform signal: a post, a hooded lamp head, a dead or living light.
            let lit = p.flags.contains("lit")
            rect(-0.08, -2.9, 0.16, 2.9, 0x3b3640); rect(-0.35, -0.12, 0.7, 0.12, 0x2a2730)
            ctx.setFillColor(c(0x4a4450)); ActorArt.rr(ctx, -0.32, -3.35, 0.64, 0.5, 0.12); ctx.fillPath()
            ActorArt.dot(ctx, 0, -3.1, 0.18, c(lit ? 0xfff0b8 : 0x2a2530))
            if lit { ActorArt.dot(ctx, 0, -3.1, 0.3, c(0xffe08a, 0.35)) }
            rect(0.08, -1.6, 0.34, 0.5, 0x2f2b34); rect(0.12, -1.55, 0.26, 0.12, lit ? 0x9cff9c : 0x5a3030)
        case .lanternClue:
            // A lantern someone set down, wick still smoking.
            ActorArt.line(ctx, [CGPoint(x: -0.12, y: -0.55), CGPoint(x: 0, y: -0.7), CGPoint(x: 0.12, y: -0.55)], c(0x2c2724), 0.04)
            ctx.setFillColor(c(0x2c2724)); ActorArt.rr(ctx, -0.16, -0.55, 0.32, 0.5, 0.06); ctx.fillPath()
            rect(-0.11, -0.48, 0.22, 0.34, 0xffd08a, p.flags.contains("taken") ? 0.2 : 0.55)
            rect(-0.2, -0.06, 0.4, 0.06, 0x2c2724)
        case .generator:
            // A squat generator on the wall: housing, flywheel, a cable up to the ceiling light.
            let on = p.flags.contains("on")
            rect(-0.5, -1.2, 1.0, 1.2, 0x3e3a44); rect(-0.5, -1.2, 1.0, 0.1, 0x55505c)
            ActorArt.dot(ctx, -0.12, -0.6, 0.3, c(0x2a2730)); ActorArt.dot(ctx, -0.12, -0.6, 0.1, c(0x6a6470))
            rect(0.22, -1.0, 0.18, 0.3, 0x2a2730); ActorArt.dot(ctx, 0.31, -0.85, 0.05, c(on ? 0x9cff9c : 0xff5a4a))
            ActorArt.line(ctx, [CGPoint(x: 0.3, y: -1.2), CGPoint(x: 0.4, y: -2.6), CGPoint(x: 1.2, y: -3.8), CGPoint(x: 2.05, y: -3.95)], c(0x2a2420), 0.05)
        case .fieldBench:
            rect(-0.9, -0.95, 1.8, 0.14, 0x9a6a40); rect(-0.8, -0.82, 0.12, 0.82, 0x5a3a22); rect(0.68, -0.82, 0.12, 0.82, 0x5a3a22)
            rect(-0.7, -0.35, 1.4, 0.06, 0x5a3a22); rect(0.2, -1.2, 0.08, 0.25, 0xa7adb3); rect(-0.5, -1.1, 0.4, 0.15, 0xc9925a)
        case .cot:
            rect(-0.9, -0.5, 1.8, 0.18, 0x5a6e6a); rect(-0.85, -0.62, 0.45, 0.14, 0xe0d2b4)
            rect(-0.85, -0.32, 0.08, 0.32, 0x6e4529); rect(0.77, -0.32, 0.08, 0.32, 0x6e4529)
        case .shelterLight:
            // A caged ceiling lamp on a short chain.
            let lit = p.flags.contains("lit")
            ActorArt.line(ctx, [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.45)], c(0x3a3640), 0.05)
            ctx.setFillColor(c(0x4a4450)); ActorArt.rr(ctx, -0.45, 0.42, 0.9, 0.18, 0.06); ctx.fillPath()
            ActorArt.dot(ctx, 0, 0.72, 0.2, c(lit ? 0xfff0c0 : 0x2a2530))
            ctx.setStrokeColor(c(0x5a5560)); ctx.setLineWidth(0.04)
            for k in -1...1 { ctx.move(to: CGPoint(x: CGFloat(k) * 0.18, y: 0.6)); ctx.addLine(to: CGPoint(x: CGFloat(k) * 0.12, y: 0.95)) }
            ctx.strokePath()
            if lit { ActorArt.dot(ctx, 0, 0.72, 0.38, c(0xffe08a, 0.25)) }
        case .camp:
            // A camp: a lidded crate with a bedroll strapped on top and a little flag.
            rect(-0.6, -0.8, 1.2, 0.8, 0x7a5232); rect(-0.6, -0.86, 1.2, 0.12, 0x9a6a40)
            for k in 0..<2 { rect(-0.6, -0.55 + CGFloat(k) * 0.3, 1.2, 0.04, 0x5a3a22) }
            rect(-0.12, -0.6, 0.24, 0.14, 0xc9a86a, 0.7)
            ctx.setFillColor(c(0x5a6e6a)); ActorArt.rr(ctx, -0.5, -1.15, 1.0, 0.3, 0.14); ctx.fillPath()
            rect(0.52, -2.0, 0.05, 1.2, 0x3a2a22)
            ctx.setFillColor(c(0xc8462f)); ctx.addLines(between: [CGPoint(x: 0.57, y: -2.0), CGPoint(x: 0.95, y: -1.85), CGPoint(x: 0.57, y: -1.7)]); ctx.fillPath()
        case .odiStall:
            rect(-1.6, -0.9, 3.2, 0.12, 0x6b4f3a); rect(-1.5, -0.78, 0.1, 0.78, 0x4f392d); rect(1.4, -0.78, 0.1, 0.78, 0x4f392d)
            for i in 0..<5 { ActorArt.dot(ctx, -1.2 + CGFloat(i) * 0.6, -1.05, 0.18, c(i % 2 == 0 ? 0x6f9a52 : 0x8cc46a)) }
            rect(-2.6, -0.5, 0.9, 0.5, 0x4a2f24); rect(1.8, -0.5, 0.9, 0.5, 0x4a2f24)
        }
    }

    /// How far the art of a prop extends around its base point (tiles): x0, y0, width, height.
    static func bounds(_ k: PropKind) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        switch k {
        case .workbench: return (-1.5, -2.8, 3.0, 2.9)
        case .liftCar: return (-3.0, -5.6, 6.0, 5.8)
        case .crate: return (-0.9, -1.3, 1.8, 1.4)
        case .drillRig: return (-3.2, -3.9, 7.8, 5.5)
        case .gantry: return (-3.2, -6.7, 6.4, 8.1)
        case .warmPipe: return (0, -0.3, 44, 0.5)
        case .odiStall: return (-2.8, -1.4, 5.6, 1.5)
        case .bed: return (-1.2, -0.9, 2.5, 1.0)
        case .maraLift: return (-1.5, -5.2, 3.0, 5.3)
        case .maraPump: return (-0.7, -2.4, 2.8, 2.5)
        case .maraShelf: return (-1.0, -2.4, 2.0, 2.5)
        case .transitLift: return (-1.5, -2.1, 3.0, 2.2)
        case .signalLamp: return (-0.6, -3.7, 1.2, 3.8)
        case .camp: return (-0.8, -2.2, 1.9, 2.3)
        case .shelterLight: return (-0.6, -0.1, 1.2, 1.2)
        case .generator: return (-0.7, -4.2, 3.0, 4.3)
        case .fieldBench: return (-1.0, -1.4, 2.0, 1.5)
        case .cot: return (-1.0, -0.8, 2.0, 0.9)
        default: return (-1.0, -2.2, 2.0, 2.3)
        }
    }
}
