import Foundation

/// Painted text in the world: depth markers and stencils. Purely visual.
public struct Decal: Codable, Equatable, Sendable {
    public var text: String
    public var pos: V2
    public var size: Double
    public var vertical: Bool
}

/// Fixed coordinates the story and renderer refer to.
public enum Landmarks {
    public static let width = 160, height = 60
    public static let workshop = (x0: 20, x1: 31, top: 26, floor: 30)
    public static let bench = V2(26.25, 30)
    public static let shaft = (c0: 25, c1: 26, open: 13, mouth: 25)
    public static let hatchRows = 9...12
    public static let maint = (x0: 17, x1: 34, top: 5, floor: 9)
    public static let outpost = (x0: 74, x1: 86, top: 5, floor: 9, door: 73)
    public static let caveStart = 48
    public static let crystal = V2(37.5, 30.5)
    public static let passage = (x0: 36.0, x1: 73.0, floorY: 9.0)
    public static let shaftRungsID = "rungs.shaft"
}

public enum WorldGen {
    /// Cave floor height profile: valley, launch ramp, long downhill runs.
    static let keyframes: [(Int, Int)] = [(48, 30), (55, 30), (63, 32), (70, 33), (84, 42), (90, 43), (94, 39), (97, 39),
                                          (104, 45), (112, 46), (120, 44), (128, 41), (156, 41)]
    static func profile(_ c: Int) -> Double {
        for i in 0..<(keyframes.count - 1) {
            let a = keyframes[i], b = keyframes[i + 1]
            if c <= b.0 {
                let t = clampD(Double(c - a.0) / Double(b.0 - a.0), 0, 1)
                return Double(a.1) + Double(b.1 - a.1) * t
            }
        }
        return 41
    }

    public static func make() -> World {
        let W = Landmarks.width, H = Landmarks.height
        let w = World(w: W, h: H)

        // Base earth with a few bedrock pockets away from the story paths.
        for r in 0..<H {
            for c in 0..<W {
                let onPath = (c >= 14 && c <= 56 && r >= 23 && r <= 33) || (c >= 14 && c <= 90 && r >= 2 && r <= 13) || (c >= 22 && c <= 29 && r <= 26)
                if r < 2 || r > H - 3 || c < 1 || c > W - 3 {
                    w.set(c, r, .rock)
                } else if !onPath && (hash2(c >> 1, r >> 1) < 0.06 || hash2(c, r) < 0.03) {
                    w.set(c, r, .rock)
                }
            }
        }

        // Workshop: a small steel room. The east side is raw earth (where digging begins).
        let ws = Landmarks.workshop
        for c in 19...31 {
            for r in 25...30 {
                if c == 19 || r == 25 || r == 30 { w.set(c, r, .metal, back: .room) } else { w.set(c, r, .air, back: .room) }
            }
        }

        // Lift shaft: lined, open from its mouth up to a soft seam plug, then the maintenance hatch.
        for r in 10...24 {
            w.set(24, r, .metal, back: .shaft)
            w.set(27, r, .metal, back: .shaft)
        }
        for r in Landmarks.shaft.open...Landmarks.shaft.mouth {
            w.set(25, r, .air, back: .shaft); w.set(26, r, .air, back: .shaft)
        }
        for r in Landmarks.hatchRows {
            w.set(25, r, .seam, back: .shaft); w.set(26, r, .seam, back: .shaft)
        }

        // Maintenance room above.
        let mr = Landmarks.maint
        for c in 16...35 {
            for r in 4...9 {
                if c == 16 || c == 35 || r == 4 || r == 9 { w.set(c, r, .metal, back: .maint) } else { w.set(c, r, .air, back: .maint) }
            }
        }
        w.set(25, 9, .seam, back: .shaft); w.set(26, 9, .seam, back: .shaft)
        w.set(35, 7, .dirt, back: .earth); w.set(35, 8, .dirt, back: .earth)   // the warm pipe leaves through a soft patch

        // The grower's outpost, east along the warm pipe.
        let op = Landmarks.outpost
        for c in op.door...(op.x1 + 1) {
            for r in 4...9 {
                let wall = c == op.door || c == op.x1 + 1 || r == 4 || r == 9
                if wall { w.set(c, r, .metal, back: .outpost) } else { w.set(c, r, .air, back: .outpost) }
            }
        }
        w.set(op.door, 7, .air, back: .outpost); w.set(op.door, 8, .air, back: .outpost)

        // The great cavern east of the workshop.
        var f = 30
        for c in Landmarks.caveStart..<(W - 3) {
            let t = Int(profile(c).rounded())
            if c < Landmarks.caveStart + 6 { f = 30 } else if t > f { f += 1 } else if t < f { f -= 1 }
            var g = Int((17 + 2.4 * sin(Double(c) * 0.23) + 2 * sin(Double(c) * 0.071 + 1)).rounded())
            if hash2(c, 3) < 0.2 { g += 2 + Int(hash2(c, 4) * 4) }
            g = min(g, f - 9)
            for r in g..<f { w.set(c, r, .air, back: .open) }
            for r in 0..<H where w.m(c, r).solid { w.setBack(c, r, .open) }
        }
        for r in 0..<H { w.setBack(Landmarks.caveStart - 1, r, .open) }

        w.rebuildDensity()

        // Buried things.
        w.set(36, 30, .loose); w.set(37, 30, .loose); w.set(38, 30, .loose)
        w.rebuildDensity()
        w.buried = [Buried(id: "crystal", item: ItemStack(.chargeCrystal), pos: Landmarks.crystal)]

        // Props.
        func floorAt(_ x: Int) -> Double { Double(w.groundY(Double(x) + 0.5, from: 14, to: 58) ?? 30) }
        w.props = [
            Prop(id: "bench", kind: .workbench, pos: Landmarks.bench),
            Prop(id: "locker.ws", kind: .locker, pos: V2(20.7, 30), stock: [ItemStack(.spareGrip), ItemStack(.fasteners, 2), ItemStack(.lampCell), ItemStack(.wire)]),
            Prop(id: "bed", kind: .bed, pos: V2(22.4, 30)),
            Prop(id: "storage", kind: .storage, pos: V2(29.8, 30)),
            Prop(id: "liftcar", kind: .liftCar, pos: V2(64.5, floorAt(64)), stock: [ItemStack(.liftTooth), ItemStack(.pipe, 2), ItemStack(.fasteners, 4)]),
            Prop(id: "drill", kind: .drillRig, pos: V2(80.5, floorAt(80)), stock: [ItemStack(.fasteners, 6), ItemStack(.pressureGauge), ItemStack(.batteryCell)]),
            Prop(id: "gantry", kind: .gantry, pos: V2(97.5, floorAt(97)), stock: [ItemStack(.pipe, 2), ItemStack(.wire, 2)]),
            Prop(id: "locker.m1", kind: .locker, pos: V2(18.6, 9), stock: [ItemStack(.seedTin), ItemStack(.wire, 2)]),
            Prop(id: "locker.m2", kind: .locker, pos: V2(19.8, 9), stock: [ItemStack(.lampCell, 3)]),
            Prop(id: "locker.m3", kind: .buckledLocker, pos: V2(21.0, 9)),
            Prop(id: "battery", kind: .batteryBank, pos: V2(22.8, 9)),
            Prop(id: "pump", kind: .pump, pos: V2(31.0, 9)),
            Prop(id: "pipe", kind: .warmPipe, pos: V2(30.0, 8.75)),
            Prop(id: "odi", kind: .odiStall, pos: V2(81.0, 9)),
        ]
        _ = mr; _ = ws

        w.climbs = [Climb(id: Landmarks.shaftRungsID, x: 26.0, top: 13.0, bottom: 25.6, kind: .rungs)]

        w.decals = [
            Decal(text: "LEVEL −214 MI", pos: V2(20.4, 27.3), size: 0.3, vertical: false),
            Decal(text: "SERVICE SHAFT 7  ▸  MAINT", pos: V2(25.08, 18.8), size: 0.28, vertical: true),
            Decal(text: "MAINT · −213.98 MI", pos: V2(27.6, 6.1), size: 0.3, vertical: false),
            Decal(text: "LINE 4 · WARM", pos: V2(31.6, 8.2), size: 0.22, vertical: false),
        ]
        return w
    }
}

