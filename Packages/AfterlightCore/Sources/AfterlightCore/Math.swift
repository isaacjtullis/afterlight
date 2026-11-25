import Foundation

/// 2D vector in world units. One unit is one tile. x grows right, y grows DOWN (rows),
/// matching the prototype. Renderers flip y for SpriteKit.
public struct V2: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func + (a: V2, b: V2) -> V2 { V2(a.x + b.x, a.y + b.y) }
    public static func - (a: V2, b: V2) -> V2 { V2(a.x - b.x, a.y - b.y) }
    public static func * (a: V2, s: Double) -> V2 { V2(a.x * s, a.y * s) }
    public var length: Double { (x * x + y * y).squareRoot() }
    public func dist(_ o: V2) -> Double { (self - o).length }
}

@inline(__always) public func clampD(_ v: Double, _ a: Double, _ b: Double) -> Double { v < a ? a : (v > b ? b : v) }
@inline(__always) public func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
/// Frame-rate independent exponential approach.
@inline(__always) public func damp(_ a: Double, _ b: Double, _ k: Double, _ dt: Double) -> Double { a + (b - a) * (1 - exp(-k * dt)) }
public func smoothstepD(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = clampD((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)
}

/// Stable integer hash in [0,1), used for deterministic world detail.
public func hash2(_ a: Int, _ b: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: a &* 374_761_393 &+ b &* 668_265_263)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h) / 4_294_967_296.0
}

/// Small deterministic RNG for world generation and job plans.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
