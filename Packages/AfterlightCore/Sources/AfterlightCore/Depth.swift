import Foundation

/// Depth below the surface, in feet. The shelter floor sits about 2,600 ft down; a tile is about six feet.
public enum Depth {
    public static let homeFeet = 2600.0
    public static let feetPerTile = 6.0
    public static func feet(atY y: Double) -> Int {
        let f = homeFeet - (30 - y) * feetPerTile
        return Int((f / 5).rounded() * 5)
    }
    public static func label(atY y: Double) -> String {
        let n = feet(atY: y)
        let f = NumberFormatter(); f.numberStyle = .decimal
        return "−\(f.string(from: NSNumber(value: n)) ?? String(n)) ft"
    }
}
