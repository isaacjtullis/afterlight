import Foundation

/// Material of one tile.
public enum Mat: UInt8, Codable, Sendable {
    case air = 0      // natural open air (caves, rooms)
    case dug = 1      // air that Max carved
    case dirt = 2     // packed earth: shovel cuts it sideways and down
    case loose = 3    // loose soil: shovel or pick
    case rock = 4     // bedrock: nothing in chapters 1–3 cuts it
    case metal = 5    // built walls, floors, linings
    case seam = 6     // soft overhead seam: the short pick opens it

    public var solid: Bool { rawValue >= 2 }
    public var hard: Bool { self == .rock || self == .metal }
}

/// What sits behind a tile once it is open. Drives the back-wall art and "is this
/// a man-made room" checks.
public enum Backdrop: UInt8, Codable, Sendable {
    case open = 0   // natural cavern: parallax shows through
    case earth      // carved tunnel back wall
    case room       // workshop panels
    case shaft      // lift shaft lining
    case maint      // maintenance room panels
    case outpost    // Mara's outpost
    case sump       // the flooded sump under the outpost
    case transit    // the old transit level, one level up
}

public enum DigTool: String, Codable, Sendable {
    case shovel, pick
    func cuts(_ m: Mat) -> Bool {
        switch self {
        // Crumbs left inside already-dug tiles always come away.
        case .shovel: return m == .dirt || m == .loose || m == .seam || m == .dug
        case .pick: return m == .seam || m == .loose || m == .dug
        }
    }
}

/// Something buried in the earth that pops out once its spot is dug open.
public struct Buried: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var item: ItemStack
    public var pos: V2
    public var revealed: Bool = false
}

/// A vertical climbable: rungs, a ladder Max placed, or footholds he cut.
public struct Climb: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case rungs, ladder, foothold, rope }
    public var id: String
    public var x: Double
    public var top: Double      // smaller y: highest point feet can reach
    public var bottom: Double   // larger y: lowest point
    public var kind: Kind
}

public enum PropKind: String, Codable, Sendable {
    case workbench, locker, buckledLocker, bed, storage
    case liftCar, drillRig, gantry           // cave salvage
    case pump, batteryBank, warmPipe         // maintenance room
    case lamp, planter, waterTank            // placed by the player
    case outpostDoor, odiStall
    // Mara's outpost (chapter 3)
    case maraTap, maraPump, maraLift, maraShelf, sumpHatch, intake, sunkValve, chimney, transitLift
}

public struct Prop: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: PropKind
    public var pos: V2
    public var stock: [ItemStack] = []
    public var flags: Set<String> = []
    public var planted: Date? = nil
    public init(id: String, kind: PropKind, pos: V2, stock: [ItemStack] = []) {
        self.id = id; self.kind = kind; self.pos = pos; self.stock = stock
    }
}

public struct CarveResult {
    public var changed = false
    public var cleared: [(c: Int, r: Int, was: Mat)] = []
    public var revealed: [Buried] = []
    public var touchedOpen: (c: Int, r: Int)? = nil
}

/// The terrain. Tiles hold materials for game logic; a finer density field
/// (K samples per tile) holds the actual carved shape for physics and rendering.
public final class World {
    public static let K = 3
    public static let chunk = 8

    public let w: Int, h: Int
    public let dw: Int, dh: Int
    public internal(set) var mat: [Mat]
    public internal(set) var back: [Backdrop]
    public internal(set) var dens: [Float]

    public var buried: [Buried] = []
    public var props: [Prop] = []
    public var climbs: [Climb] = []
    public var decals: [Decal] = []
    /// Chunk indices whose art must be redrawn.
    public var dirtyChunks = Set<Int>()

    public var chunksX: Int { (w + World.chunk - 1) / World.chunk }
    public var chunksY: Int { (h + World.chunk - 1) / World.chunk }

    public init(w: Int, h: Int) {
        self.w = w; self.h = h
        dw = w * World.K + 1
        dh = h * World.K + 1
        mat = Array(repeating: .dirt, count: w * h)
        back = Array(repeating: .earth, count: w * h)
        dens = Array(repeating: 1, count: dw * dh)
    }

    // MARK: tiles

    @inline(__always) public func inside(_ c: Int, _ r: Int) -> Bool { c >= 0 && r >= 0 && c < w && r < h }
    @inline(__always) public func m(_ c: Int, _ r: Int) -> Mat { inside(c, r) ? mat[r * w + c] : .rock }
    @inline(__always) public func bd(_ c: Int, _ r: Int) -> Backdrop { inside(c, r) ? back[r * w + c] : .open }

    public func set(_ c: Int, _ r: Int, _ v: Mat, back b: Backdrop? = nil) {
        guard inside(c, r) else { return }
        mat[r * w + c] = v
        if let b { back[r * w + c] = b }
    }
    public func setBack(_ c: Int, _ r: Int, _ b: Backdrop) {
        guard inside(c, r) else { return }
        back[r * w + c] = b
    }

    // MARK: density field

    /// Rebuild the fine field from tiles, smoothing corners so natural earth reads organic.
    public func rebuildDensity() {
        let cw = w + 1
        var cc = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for j in 0...h {
            for i in 0...w {
                var n = 0
                if m(i - 1, j - 1).solid { n += 1 }
                if m(i, j - 1).solid { n += 1 }
                if m(i - 1, j).solid { n += 1 }
                if m(i, j).solid { n += 1 }
                cc[j * cw + i] = Double(n) / 4
            }
        }
        func cf(_ i: Int, _ j: Int) -> Double { (i < 0 || j < 0 || i > w || j > h) ? 1 : cc[j * cw + i] }
        let k = Double(World.K)
        for j in 0..<dh {
            for i in 0..<dw {
                let x = Double(i) / k, y = Double(j) / k
                let ci = Int(x.rounded(.down)), cj = Int(y.rounded(.down))
                let u = x - Double(ci), v = y - Double(cj)
                let val = (cf(ci, cj) * (1 - u) + cf(ci + 1, cj) * u) * (1 - v)
                    + (cf(ci, cj + 1) * (1 - u) + cf(ci + 1, cj + 1) * u) * v
                dens[j * dw + i] = Float(val)
            }
        }
        markAllDirty()
    }

    @inline(__always) public func d(_ i: Int, _ j: Int) -> Double {
        (i < 0 || j < 0 || i >= dw || j >= dh) ? 1 : Double(dens[j * dw + i])
    }

    public func density(_ x: Double, _ y: Double) -> Double {
        let k = Double(World.K)
        let fx = x * k, fy = y * k
        let i = Int(fx.rounded(.down)), j = Int(fy.rounded(.down))
        let u = fx - Double(i), v = fy - Double(j)
        return (d(i, j) * (1 - u) + d(i + 1, j) * u) * (1 - v) + (d(i, j + 1) * (1 - u) + d(i + 1, j + 1) * u) * v
    }

    @inline(__always) public func solid(_ x: Double, _ y: Double) -> Bool { density(x, y) >= 0.5 }

    /// First solid surface scanning down from y0 to y1 at column x, refined by bisection.
    public func groundY(_ x: Double, from y0: Double, to y1: Double) -> Double? {
        var prev = y0
        var y = y0
        while y <= y1 {
            if solid(x, y) {
                var a = prev, b = y
                for _ in 0..<6 {
                    let mid = (a + b) / 2
                    if solid(x, mid) { b = mid } else { a = mid }
                }
                return b
            }
            prev = y
            y += 0.04
        }
        return nil
    }

    /// Is the tile containing (x,y) hard (metal/rock)?
    public func hardAt(_ x: Double, _ y: Double) -> Bool {
        m(Int(x.rounded(.down)), Int(y.rounded(.down))).hard
    }

    // MARK: carving

    /// Remove a round bite of earth. `floorY` keeps the floor flat for sideways digging.
    public func carve(center: V2, radius R: Double, floorY: Double? = nil, tool: DigTool) -> CarveResult {
        var res = CarveResult()
        let k = Double(World.K)
        let i0 = Int(((center.x - R) * k).rounded(.down)), i1 = Int(((center.x + R) * k).rounded(.up))
        let j0 = Int(((center.y - R) * k).rounded(.down)), j1 = Int(((center.y + R) * k).rounded(.up))
        func blocks(_ x: Double, _ y: Double) -> Int {
            let t = m(Int(x.rounded(.down)), Int(y.rounded(.down)))
            return (t.solid && !tool.cuts(t)) ? 1 : 0
        }
        let jl = max(0, j0), jh = min(dh - 1, j1), il = max(0, i0), ih = min(dw - 1, i1)
        guard jl <= jh, il <= ih else { return res }
        for j in jl...jh {
            for i in il...ih {
                let x = Double(i) / k, y = Double(j) / k
                let dd = ((x - center.x) * (x - center.x) + (y - center.y) * (y - center.y)).squareRoot() / R
                if dd >= 1 { continue }
                let e = 0.01
                if blocks(x - e, y - e) + blocks(x + e, y - e) + blocks(x - e, y + e) + blocks(x + e, y + e) >= 2 { continue }
                var v = smoothstepD(0.6, 1.0, dd)
                if let fy = floorY, y >= fy - 0.01 { v = max(v, y > fy + 0.01 ? 1 : 0.5) }
                let o = Double(dens[j * dw + i])
                if v < o {
                    if (o >= 0.5 && v < 0.5) || (o > 0.52 && v <= 0.5) { res.changed = true }
                    dens[j * dw + i] = Float(v)
                }
            }
        }
        // Tiles whose middle is now open become dug.
        let c0 = Int((center.x - R).rounded(.down)), c1 = Int((center.x + R).rounded(.down))
        let r0 = Int((center.y - R).rounded(.down)), r1 = Int((center.y + R).rounded(.down))
        for r in r0...r1 {
            for c in c0...c1 {
                let t = m(c, r)
                guard t.solid, tool.cuts(t), density(Double(c) + 0.5, Double(r) + 0.5) < 0.5 else { continue }
                set(c, r, .dug, back: bd(c, r) == .open ? .open : (bd(c, r) == .room ? .room : .earth))
                res.cleared.append((c, r, t))
                for (dc, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where res.touchedOpen == nil {
                    if m(c + dc, r + dr) == .air && bd(c + dc, r + dr) == .open { res.touchedOpen = (c + dc, r + dr) }
                }
            }
        }
        for idx in buried.indices where !buried[idx].revealed {
            let p = buried[idx].pos
            if p.dist(center) < R + 0.8 && density(p.x, p.y) < 0.5 {
                buried[idx].revealed = true
                res.revealed.append(buried[idx])
            }
        }
        markDirty(x0: center.x - R - 0.5, y0: center.y - R - 0.5, x1: center.x + R + 0.5, y1: center.y + R + 0.5)
        return res
    }

    /// Open or close one built tile (a hatch), reshaping only the fine field inside it.
    public func setHatch(_ c: Int, _ r: Int, open: Bool) {
        set(c, r, open ? .air : .metal)
        let K = World.K
        for j in (r * K)...((r + 1) * K) {
            for i in (c * K + 1)...((c + 1) * K - 1) {
                let edge = j == r * K || j == (r + 1) * K
                dens[j * dw + i] = open ? 0 : (edge ? 0.5 : 1)
            }
        }
        markDirty(x0: Double(c) - 1, y0: Double(r) - 1, x1: Double(c) + 2, y1: Double(r) + 2)
    }

    // MARK: dirty tracking

    public func markDirty(x0: Double, y0: Double, x1: Double, y1: Double) {
        let s = Double(World.chunk)
        let cx0 = max(0, Int((x0 / s).rounded(.down))), cx1 = min(chunksX - 1, Int((x1 / s).rounded(.down)))
        let cy0 = max(0, Int((y0 / s).rounded(.down))), cy1 = min(chunksY - 1, Int((y1 / s).rounded(.down)))
        guard cx0 <= cx1, cy0 <= cy1 else { return }
        for cy in cy0...cy1 { for cx in cx0...cx1 { dirtyChunks.insert(cy * chunksX + cx) } }
    }
    public func markAllDirty() {
        for i in 0..<(chunksX * chunksY) { dirtyChunks.insert(i) }
    }

    // MARK: queries

    public func prop(_ id: String) -> Prop? { props.first { $0.id == id } }
    public func propIndex(_ id: String) -> Int? { props.firstIndex { $0.id == id } }
    public func props(of kind: PropKind) -> [Prop] { props.filter { $0.kind == kind } }

    /// Ray march for light occlusion. Returns endpoints of `n+1` rays between angles a0 and a1.
    public func castLight(from o: V2, radius R: Double, a0: Double, a1: Double, rays n: Int) -> [V2] {
        var pts: [V2] = []
        pts.reserveCapacity(n + 1)
        for i in 0...n {
            let a = a0 + (a1 - a0) * Double(i) / Double(n)
            let dx = cos(a), dy = sin(a)
            var t = 0.0, hit = R, pen = -1.0
            while t < R {
                t += 0.17
                if solid(o.x + dx * t, o.y + dy * t) {
                    if pen < 0 { pen = t }
                    if t - pen > 0.45 { hit = t; break }
                }
            }
            pts.append(V2(o.x + dx * hit, o.y + dy * hit))
        }
        return pts
    }
}
