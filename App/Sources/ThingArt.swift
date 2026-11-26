import CoreGraphics
import AfterlightCore

/// Drawings for the campaign's `.thing` props, picked by `look`. Base point is the floor; up is negative y.
extension Art {
    static func drawThing(_ ctx: CGContext, _ p: Prop) {
        func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { TerrainArt.color(hex, a) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ a: CGFloat = 1) { ctx.setFillColor(c(hex, a)); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        func round(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat = 1) { ctx.setFillColor(c(hex, a)); ActorArt.rr(ctx, x, y, w, h, r); ctx.fillPath() }
        func wheel(_ x: CGFloat) { ActorArt.dot(ctx, x, -0.12, 0.12, c(0x1e1c1a)); ActorArt.dot(ctx, x, -0.12, 0.05, c(0x6a6a6a)) }
        let brass: UInt32 = 0xd8b04a
        switch p.look ?? "" {
        case "door":
            round(-0.6, -2.2, 1.2, 2.2, 0.08, 0x3a2e28)
            rect(-0.5, -2.1, 1.0, 2.1, 0x5a463a)
            ActorArt.dot(ctx, 0.35, -1.1, 0.06, c(brass))
            rect(-0.55, -2.55, 1.1, 0.28, 0x1e3a2a); rect(-0.48, -2.5, 0.96, 0.18, 0x3c9a5a, 0.7)
        case "desk":
            rect(-1.4, -1.1, 2.8, 1.1, 0x4a2e22); rect(-1.5, -1.15, 3.0, 0.1, 0x6a4430)
            ActorArt.dot(ctx, 0.9, -1.25, 0.1, c(brass))
            if !p.stock.isEmpty { for k in 0..<3 { rect(-0.9 + CGFloat(k) * 0.12, -1.28 - CGFloat(k) * 0.02, 0.4, 0.06, 0xe8e2d2) } }
        case "diagram":
            rect(-0.9, -3.0, 1.8, 1.3, 0xd8d0b8, 0.85); rect(-0.85, -2.95, 1.7, 1.2, 0x2a3a2a, 0.12)
            ActorArt.line(ctx, [CGPoint(x: -0.6, y: -1.95), CGPoint(x: 0.1, y: -1.95), CGPoint(x: 0.1, y: -2.7), CGPoint(x: 0.6, y: -2.7)], c(0x3c9a5a), 0.06)
            ActorArt.line(ctx, [CGPoint(x: 0.5, y: -2.8), CGPoint(x: 0.6, y: -2.7), CGPoint(x: 0.5, y: -2.6)], c(0x3c9a5a), 0.06)
            ActorArt.dot(ctx, -0.6, -1.95, 0.07, c(0xc83a2a))
        case "cupboard":
            rect(-0.8, -1.5, 1.6, 1.5, 0x8a8a84); rect(-0.02, -1.45, 0.04, 1.4, 0x5a5a56)
            ActorArt.dot(ctx, -0.12, -0.8, 0.04, c(0x3a3a3a)); ActorArt.dot(ctx, 0.12, -0.8, 0.04, c(0x3a3a3a))
        case "bench":
            rect(-0.9, -0.55, 1.8, 0.12, 0x7a5a3a); rect(-0.8, -0.45, 0.08, 0.45, 0x4a3a2a); rect(0.72, -0.45, 0.08, 0.45, 0x4a3a2a)
        case "cart", "cartStripped":
            let stripped = p.look == "cartStripped"
            rect(-0.9, -1.3, 1.8, 1.0, 0xd8d4c8); rect(-0.9, -0.9, 1.8, 0.05, 0xa8a49a)
            for k in 0..<3 { rect(-0.8, -1.25 + CGFloat(k) * 0.32, 1.6, 0.04, 0x8a867c) }
            // the ridiculous brass rail
            ActorArt.line(ctx, [CGPoint(x: -1.0, y: -1.3), CGPoint(x: -1.0, y: -1.75), CGPoint(x: 1.0, y: -1.75), CGPoint(x: 1.0, y: -1.3)], c(brass), 0.07)
            ActorArt.dot(ctx, -1.0, -1.75, 0.07, c(0xf0d070)); ActorArt.dot(ctx, 1.0, -1.75, 0.07, c(0xf0d070))
            if stripped { rect(-0.85, -0.3, 0.2, 0.3, 0x5a5a56); rect(0.65, -0.3, 0.2, 0.3, 0x5a5a56) } else { wheel(-0.7); wheel(0.7) }
            if !p.stock.isEmpty { round(-0.6, -1.95, 0.9, 0.6, 0.06, 0x6a5a42) }
        case "handcartFrame", "handcart":
            rect(-0.5, -0.9, 1.0, 0.6, 0x7a6a52); rect(0.45, -1.6, 0.06, 1.3, 0x5a4a3a)
            if p.look == "handcart" { wheel(-0.3); wheel(0.3); rect(-0.45, -1.05, 0.9, 0.15, 0x2e2a26) } else { rect(-0.3, -0.3, 0.6, 0.06, 0x5a5a56) }
        case "shower":
            rect(-0.7, -2.6, 1.4, 2.6, 0xc8ccd0, 0.35)
            ActorArt.line(ctx, [CGPoint(x: 0.4, y: -0.1), CGPoint(x: 0.4, y: -2.3), CGPoint(x: 0.1, y: -2.4)], c(0xa8acb0), 0.06)
            ActorArt.dot(ctx, 0.05, -2.35, 0.12, c(0xb8bcc0))
            ActorArt.dot(ctx, 0.4, -1.3, 0.09, c(0xd8dce0)); rect(0.38, -1.42, 0.04, 0.24, 0x6a6e72)
        case "hotelBed":
            rect(-1.1, -0.55, 2.2, 0.45, 0xe8e4da); rect(-1.1, -0.15, 2.2, 0.15, 0x4a2e22); rect(-1.15, -1.05, 0.12, 1.05, 0x4a2e22)
            round(-0.95, -0.75, 0.55, 0.22, 0.08, 0xf4f0e8); rect(-0.2, -0.6, 1.25, 0.12, 0x8a3a3a)
        case "hatch":
            if p.flags.contains("barred") {
                rect(-0.95, -0.12, 1.9, 0.12, 0x6b7076); rect(-0.8, -0.28, 1.6, 0.12, 0xc83a2a)
            } else { rect(-1.05, -0.9, 0.1, 0.9, 0x6b7076); rect(-0.95, -0.1, 0.2, 0.1, 0x6b7076) }
        case "battery":
            if !p.stock.isEmpty {
                round(-0.6, -1.0, 1.2, 1.0, 0.06, 0x3a4a5a); rect(-0.4, -1.12, 0.2, 0.12, 0xc83a2a); rect(0.2, -1.12, 0.2, 0.12, 0x2a2a2a)
                rect(-0.45, -0.7, 0.9, 0.2, 0xd8b04a, 0.8)
            } else { rect(-0.6, -0.08, 1.2, 0.08, 0x2a2a2a, 0.6) }
            rect(-0.9, -2.2, 1.8, 0.08, 0x3a3a40)
        case "trolley":
            rect(-0.7, -0.9, 1.4, 0.1, 0x8a8a84); rect(-0.7, -0.35, 1.4, 0.08, 0x8a8a84); rect(0.62, -1.4, 0.06, 1.1, 0x6a6a64)
            wheel(-0.55); wheel(0.55)
            if p.stock.contains(where: { $0.id == .hotelBattery }) { round(-0.5, -1.6, 0.9, 0.7, 0.05, 0x3a4a5a) }
            if p.stock.contains(where: { $0.id == .inspectionLamp }) { rect(-0.6, -1.15, 0.3, 0.22, 0xe8c050); ActorArt.dot(ctx, -0.45, -1.04, 0.07, c(0xfff0c0)) }
        case "exitSign":
            rect(-0.8, -3.2, 1.6, 0.5, 0x1e3a2a); rect(-0.72, -3.13, 1.44, 0.36, 0x3cc86a, 0.85)
            ActorArt.line(ctx, [CGPoint(x: 0.3, y: -2.85), CGPoint(x: 0.5, y: -3.05), CGPoint(x: 0.3, y: -3.0)], c(0xffffff), 0.05)
        case "coats":
            rect(-0.15, -0.14, 0.7, 0.14, 0x8a3a2a); rect(-0.1, -2.8, 0.2, 2.8, 0x6a6a6a, 0.0)
            rect(-1.6, -0.14, 0.7, 0.14, 0x2a4a6a)
        case "stall":
            rect(-1.3, -1.0, 2.6, 1.0, 0x5a4a3a); rect(-1.4, -1.05, 2.8, 0.1, 0x7a6a52)
            ActorArt.line(ctx, [CGPoint(x: -1.3, y: -1.0), CGPoint(x: -1.3, y: -2.6), CGPoint(x: 1.3, y: -2.6), CGPoint(x: 1.3, y: -1.0)], c(0x4a3a2a), 0.07)
            rect(-1.4, -2.75, 2.8, 0.25, 0x8a3a2a)
            ActorArt.dot(ctx, 0, -2.3, 0.14, c(0xffe0a0))
            for k in 0..<3 { round(-1.0 + CGFloat(k) * 0.4, -1.3, 0.28, 0.25, 0.04, [0x8a7a5a, 0x5a6a7a, 0x7a5a4a][k]) }
            if p.stock.contains(where: { $0.id == .inspectionLamp }) { rect(0.4, -1.32, 0.34, 0.26, 0xe8c050); ActorArt.dot(ctx, 0.57, -1.19, 0.07, c(0xfff0c0)) }
        case "crossing":
            rect(-3.0, -0.12, 6.0, 0.12, 0x6a5a4a)
            for k in 0..<7 { rect(-3.0 + CGFloat(k) * 1.0, -1.0, 0.06, 1.0, 0x5a4a3a) }
            rect(-3.0, -1.02, 6.0, 0.06, 0x7a6a5a)
        case "tollpost":
            rect(-0.1, -2.0, 0.2, 2.0, 0x4a3a2a)
            rect(-0.1, -1.6, 2.4, 0.12, p.flags.contains("down") ? 0xc83a2a : 0x4a3a2a)
            if p.flags.contains("down") { for k in 0..<4 { rect(0.2 + CGFloat(k) * 0.55, -1.6, 0.25, 0.12, 0xe8e2d2) } }
            round(-0.5, -2.5, 1.0, 0.45, 0.05, 0x2a2a2e); rect(-0.4, -2.42, 0.8, 0.28, 0xc8a050, 0.6)
        case "stationMap":
            rect(-1.2, -3.0, 2.4, 1.6, 0xd8d0b8, 0.85)
            rect(-1.1, -2.9, 2.2, 0.3, 0x3a3a44, 0.7)     // the gallery, a band across the top
            rect(-1.1, -2.2, 2.2, 0.7, 0x6a4a3a, 0.4)     // the inhabited levels below
            if p.flags.contains("closed") { ActorArt.line(ctx, [CGPoint(x: -1.1, y: -2.75), CGPoint(x: 1.1, y: -2.75)], c(0xc83a2a), 0.08) }
            ActorArt.dot(ctx, 0.9, -2.75, 0.08, c(0xc83a2a))
        case "station":
            round(-0.8, -2.2, 1.6, 2.2, 0.08, 0x3a3a40)
            rect(-0.6, -2.0, 1.2, 0.5, 0x1e1e22); rect(-0.5, -1.92, 1.0, 0.34, p.flags.contains("armed") ? 0xc83a2a : 0x3a6a4a, 0.8)
            rect(0.15, -1.3, 0.12, 0.9, 0x8a8a84)
            round(0.05, p.flags.contains("fired") ? -0.55 : -1.45, 0.32, 0.22, 0.05, 0xc83a2a)
        case "surfaceDoor":
            round(-1.0, -2.8, 2.0, 2.8, 0.1, 0x4a4e54)
            rect(-0.9, -2.7, 1.8, 2.7, p.flags.contains("open") ? 0xcfd8e0 : 0x5a5e64)
            if !p.flags.contains("open") { rect(0.55, -1.5, 0.12, 0.5, 0xd8b04a); for k in 0..<3 { rect(-0.8, -2.4 + CGFloat(k) * 0.8, 1.6, 0.06, 0x3a3e44) } }
        case "rubble":
            for k in 0..<9 { let x = -2.6 + CGFloat(k) * 0.62; round(x, -0.5 - CGFloat(k % 3) * 0.3, 0.7, 0.5 + CGFloat(k % 3) * 0.3, 0.2, k % 2 == 0 ? 0x4a4952 : 0x3b3a47) }
        case "regulatorCrate":
            rect(-0.5, -0.6, 1.0, 0.6, 0x6a5a42); rect(-0.5, -0.62, 1.0, 0.06, 0x4a3a2a)
            if !p.stock.isEmpty { ActorArt.dot(ctx, 0, -0.85, 0.2, c(brass)) }
        default:
            rect(-0.5, -1.0, 1.0, 1.0, 0x5a4a3a)
        }
    }
}
