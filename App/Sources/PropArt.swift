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
            ctx.saveGState(); ctx.rotate(by: -0.18)
            rect(-2.4, -3.4, 4.8, 3.2, 0x3a3540); rect(-2.2, -3.2, 1.6, 1.4, 0x1c1a20); rect(0.4, -3.2, 1.6, 1.4, 0x1c1a20)
            rect(-2.4, -0.4, 4.8, 0.3, 0x4a4450)
            for i in 0..<6 { rect(-2.3 + CGFloat(i) * 0.8, -3.75, 0.45, 0.35, 0x58505c) }
            ctx.restoreGState()
        case .drillRig:
            rect(-3, -1.8, 5.2, 1.6, 0x3b3640); rect(-2.6, -0.4, 4.6, 0.4, 0x2a2730)
            ctx.setFillColor(c(0x4a4450)); ctx.addLines(between: [CGPoint(x: 2.2, y: -1.8), CGPoint(x: 4.2, y: -1.0), CGPoint(x: 2.2, y: -0.2)]); ctx.fillPath()
            rect(-2.2, -3.0, 0.3, 1.2, 0x3b3640); rect(-2.6, -3.1, 1.1, 0.2, 0x4a4450)
        case .gantry:
            ActorArt.line(ctx, [CGPoint(x: -2.2, y: 0), CGPoint(x: -2.2, y: -6), CGPoint(x: 2.2, y: -6), CGPoint(x: 2.2, y: 0)], c(0x3b3640), 0.3)
            ActorArt.line(ctx, [CGPoint(x: -2.2, y: -3), CGPoint(x: 2.2, y: -5.8)], c(0x3b3640), 0.15)
            ActorArt.line(ctx, [CGPoint(x: 0.6, y: -6), CGPoint(x: 0.6, y: -3.4)], c(0x2a2730), 0.06)
            rect(0.35, -3.5, 0.5, 0.35, 0x4a4450)
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
            rect(-0.05, -1.1, 0.1, 1.1, 0x2c2724); rect(-0.14, -1.35, 0.28, 0.3, 0x2c2724); rect(-0.1, -1.31, 0.2, 0.22, 0xffd08a)
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
        case .liftCar: return (-3.2, -4.6, 6.4, 4.8)
        case .drillRig: return (-3.2, -3.3, 7.6, 3.4)
        case .gantry: return (-2.5, -6.3, 5.0, 6.4)
        case .warmPipe: return (0, -0.3, 44, 0.5)
        case .odiStall: return (-2.8, -1.4, 5.6, 1.5)
        case .bed: return (-1.2, -0.9, 2.5, 1.0)
        default: return (-1.0, -2.2, 2.0, 2.3)
        }
    }
}
