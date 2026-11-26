import CoreGraphics
import AfterlightCore

/// Drawings for the campaign's `.thing` props, picked by `look`.
extension Art {
    static func drawThing(_ ctx: CGContext, _ p: Prop) {
        func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor { TerrainArt.color(hex, a) }
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, _ a: CGFloat = 1) { ctx.setFillColor(c(hex, a)); ctx.fill(CGRect(x: x, y: y, width: w, height: h)) }
        switch p.look ?? "" {
        default:
            rect(-0.5, -1.0, 1.0, 1.0, 0x5a4a3a)
        }
    }
}
