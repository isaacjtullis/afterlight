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
    /// The great cavern is far from home now; it opens much later.
    public static let caveStart = 104
    /// The bottom of an old lift shaft just east of the workshop, where the lift car came down.
    public static let liftPit = (x0: 41, x1: 47, top: 26, floor: 30)
    public static let liftCarPos = V2(44.6, 30)
    /// The root hollow behind the workshop's west door.
    public static let hollow = (x0: 10, x1: 18, top: 26, floor: 30, door: 19)
    public static let crystal = V2(37.5, 30.5)
    public static let passage = (x0: 36.0, x1: 73.0, floorY: 9.0)
    public static let shaftRungsID = "rungs.shaft"
    // Chapter 3: Mara's outpost, its flooded sump, the old chimney and the transit level above.
    public static let sump = (x0: 80, x1: 86, top: 10, floor: 14)
    public static let hatch = (c: 86, r: 9)
    public static let chimney = 70
    public static let transit = (x0: 62, x1: 100, floor: 3)
    public static let maraHome = V2(80.5, 9)
    public static let liftX = 84.0
    /// The old loading shaft from the east end of the transit platform down into the great cavern.
    public static let loadingShaft = (c0: 104, c1: 105)
    public static let signalLampX = 66.5
    /// Where an optional first lamp goes: the mouth of the tunnel out of the workshop.
    public static let lampSpot = V2(32.6, 30)
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
                let onPath = (c >= 14 && c <= 56 && r >= 23 && r <= 33) || (c >= 14 && c <= 101 && r >= 2 && r <= 16) || (c >= 22 && c <= 29 && r <= 26)
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

        // The lift pit: the bottom of an old lift shaft, just past where the crystal is buried.
        let lp = Landmarks.liftPit
        for c in (lp.x0 - 1)...(lp.x1 + 1) {
            for r in (lp.top - 1)...lp.floor {
                let edge = c == lp.x0 - 1 || c == lp.x1 + 1 || r == lp.top - 1 || r == lp.floor
                w.set(c, r, edge ? .dirt : .air, back: (c >= 43 && c <= 45) ? .shaft : .earth)
            }
        }
        for r in 19...(lp.top - 1) { for c in 43...45 { w.set(c, r, .loose, back: .shaft) } }   // the collapsed shaft above

        // The root hollow west of the workshop. Giant roots have grown through its door.
        let ho = Landmarks.hollow
        for c in (ho.x0 - 1)...ho.x1 {
            for r in (ho.top - 1)...ho.floor {
                let edge = c == ho.x0 - 1 || r == ho.top - 1 || r == ho.floor
                w.set(c, r, edge ? .dirt : .air, back: .earth)
            }
        }
        for r in 27...29 { w.set(ho.door, r, .root, back: .room) }
        let rootDoor = [(18, 26), (18, 27), (18, 28), (18, 29), (17, 25), (17, 26), (16, 24)]
        let rootHang = [(13, 25), (13, 26), (13, 27), (12, 24), (12, 25), (14, 27), (14, 28), (14, 29), (11, 23), (15, 29)]
        for (c, r) in rootDoor + rootHang { w.set(c, r, .root, back: .earth) }

        // Mara's outpost, east along the warm pipe. Built after the cavern so nothing cuts into it.
        let op = Landmarks.outpost
        for c in op.door...(op.x1 + 1) {
            for r in 4...9 {
                let wall = c == op.door || c == op.x1 + 1 || r == 4 || r == 9
                if wall { w.set(c, r, .metal, back: .outpost) } else { w.set(c, r, .air, back: .outpost) }
            }
        }
        w.set(op.door, 7, .air, back: .outpost); w.set(op.door, 8, .air, back: .outpost)

        // The sump under the east end: cold water, the pump's intake, and a valve that blew off.
        let sp = Landmarks.sump
        for c in (sp.x0 - 1)...(sp.x1 + 1) {
            for r in sp.top...(sp.floor + 1) {
                let wall = c == sp.x0 - 1 || c == sp.x1 + 1 || r >= sp.floor
                if wall { w.set(c, r, r == sp.floor + 1 ? .dirt : .metal, back: .sump) } else { w.set(c, r, .air, back: .sump) }
            }
        }
        w.set(Landmarks.hatch.c, Landmarks.hatch.r, .air, back: .sump)

        // The transit level: an old platform one level up, reached by Mara's lift or the old chimney.
        let tr = Landmarks.transit
        for c in tr.x0...tr.x1 {
            w.set(c, 0, .rock)
            w.set(c, 1, .air, back: .transit); w.set(c, 2, .air, back: .transit)
            w.set(c, tr.floor, .metal, back: .transit)
        }
        w.set(tr.x0 - 1, 1, .metal, back: .transit); w.set(tr.x0 - 1, 2, .metal, back: .transit)
        w.set(tr.x1 + 1, 1, .metal, back: .transit); w.set(tr.x1 + 1, 2, .metal, back: .transit)
        // East end of the platform: the wall is broken through onto a stub of decking and the old
        // loading shaft, which drops all the way into the great cavern.
        for r in 1...2 { w.set(tr.x1 + 1, r, .air, back: .transit) }
        for c in (tr.x1 + 1)...(Landmarks.loadingShaft.c1 + 1) {
            w.set(c, 0, .rock)
            for r in 1...2 { w.set(c, r, .air, back: .transit) }
            if c < Landmarks.loadingShaft.c0 { w.set(c, tr.floor, .metal, back: .transit) }
        }
        w.set(Landmarks.loadingShaft.c1 + 2, 1, .metal, back: .transit); w.set(Landmarks.loadingShaft.c1 + 2, 2, .metal, back: .transit)
        for c in Landmarks.loadingShaft.c0...Landmarks.loadingShaft.c1 {
            for r in 3..<30 where !(w.m(c, r) == .air && w.bd(c, r) == .open) { w.set(c, r, .air, back: .shaft) }
        }
        for r in 3..<30 {
            w.set(Landmarks.loadingShaft.c0 - 1, r, w.m(Landmarks.loadingShaft.c0 - 1, r) == .air && w.bd(Landmarks.loadingShaft.c0 - 1, r) == .open ? .air : .metal, back: .shaft)
            w.set(Landmarks.loadingShaft.c1 + 1, r, w.m(Landmarks.loadingShaft.c1 + 1, r) == .air && w.bd(Landmarks.loadingShaft.c1 + 1, r) == .open ? .air : .metal, back: .shaft)
        }
        // The old maintenance chimney: two tiles wide, from the warm passage's ceiling up through the platform.
        for r in 3...6 { for c in Landmarks.chimney...(Landmarks.chimney + 1) { w.set(c, r, .air, back: .shaft) } }
        // Mara dug the last stretch of the warm passage from her side, up to her door.
        for c in (Landmarks.chimney - 1)...(op.door - 1) { for r in 7...8 { w.set(c, r, .dug, back: .earth) } }

        w.rebuildDensity()

        // Buried things.
        w.set(36, 30, .loose); w.set(37, 30, .loose); w.set(38, 30, .loose)
        w.rebuildDensity()
        w.buried = [Buried(id: "crystal", item: ItemStack(.chargeCrystal), pos: Landmarks.crystal)] + scatterFinds(w)
        scatterRoots(w)
        w.rebuildDensity()

        // Props.
        // The cavern floor at a column: start in the cavern's own open air, never in the earth above its ceiling.
        func floorAt(_ x: Int) -> Double {
            let top = (10..<58).first { w.m(x, $0) == .air && w.bd(x, $0) == .open } ?? 20
            return w.groundY(Double(x) + 0.5, from: Double(top) + 0.5, to: 58) ?? 30
        }
        w.props = [
            Prop(id: "bench", kind: .workbench, pos: Landmarks.bench),
            Prop(id: "locker.ws", kind: .locker, pos: V2(20.7, 30), stock: [ItemStack(.spareGrip), ItemStack(.fasteners, 2), ItemStack(.lampCell), ItemStack(.wire)]),
            Prop(id: "bed", kind: .bed, pos: V2(22.4, 30)),
            Prop(id: "storage", kind: .storage, pos: V2(29.8, 30)),
            Prop(id: "pantry", kind: .pantry, pos: V2(28.3, 30), stock: [ItemStack(.ration, 12)]),
            Prop(id: "liftcar", kind: .liftCar, pos: Landmarks.liftCarPos, stock: [ItemStack(.liftTooth), ItemStack(.pipe, 2), ItemStack(.fasteners, 4)]),
            Prop(id: "crate.west", kind: .crate, pos: V2(11.6, 30), stock: [ItemStack(.rope), ItemStack(.lampCell), ItemStack(.fasteners, 3), ItemStack(.pressureGauge)]),
            Prop(id: "drill", kind: .drillRig, pos: V2(118.5, floorAt(118)), stock: [ItemStack(.fasteners, 6), ItemStack(.batteryCell), ItemStack(.rope)]),
            Prop(id: "gantry", kind: .gantry, pos: V2(136.5, floorAt(136)), stock: [ItemStack(.pipe, 2), ItemStack(.wire, 2), ItemStack(.rope)]),
            Prop(id: "locker.m1", kind: .locker, pos: V2(18.6, 9), stock: [ItemStack(.seedTin), ItemStack(.wire, 2)]),
            Prop(id: "locker.m2", kind: .locker, pos: V2(19.8, 9), stock: [ItemStack(.lampCell, 3)]),
            Prop(id: "locker.m3", kind: .buckledLocker, pos: V2(21.0, 9)),
            Prop(id: "battery", kind: .batteryBank, pos: V2(22.8, 9)),
            Prop(id: "pump", kind: .pump, pos: V2(31.0, 9)),
            Prop(id: "pipe", kind: .warmPipe, pos: V2(30.0, 8.75)),
            // Mara's outpost
            Prop(id: "mara.tap", kind: .maraTap, pos: V2(75.8, 9)),
            Prop(id: "mara.pump", kind: .maraPump, pos: V2(78.3, 9)),
            Prop(id: "mara.shelf", kind: .maraShelf, pos: V2(82.4, 9), stock: [ItemStack(.pressureValve)]),
            Prop(id: "mara.lift", kind: .maraLift, pos: V2(Landmarks.liftX, 9)),
            Prop(id: "sump.hatch", kind: .sumpHatch, pos: V2(Double(Landmarks.hatch.c) + 0.5, 9)),
            Prop(id: "sump.intake", kind: .intake, pos: V2(81.2, Double(Landmarks.sump.floor))),
            Prop(id: "sump.valve", kind: .sunkValve, pos: V2(84.4, Double(Landmarks.sump.floor)), stock: [ItemStack(.pressureValve)]),
            Prop(id: "chimney", kind: .chimney, pos: V2(Double(Landmarks.chimney) + 1.0, 9)),
            Prop(id: "transit.lift", kind: .transitLift, pos: V2(Landmarks.liftX, Double(Landmarks.transit.floor))),
            Prop(id: "signal", kind: .signalLamp, pos: V2(Landmarks.signalLampX, Double(Landmarks.transit.floor))),
            Prop(id: "lantern.clue", kind: .lanternClue, pos: V2(96.2, Double(Landmarks.transit.floor))),
        ]
        if let i = w.propIndex("sump.intake") { w.props[i].flags = ["clogged"] }
        if let i = w.propIndex("mara.shelf") { w.props[i].flags = ["owner:mara"] }
        if let i = w.propIndex("sump.hatch") { w.props[i].flags = ["open"] }
        _ = mr; _ = ws

        w.climbs = [
            Climb(id: Landmarks.shaftRungsID, x: 26.0, top: 13.0, bottom: 25.6, kind: .rungs),
            Climb(id: "rungs.loading", x: Double(Landmarks.loadingShaft.c0) + 1.0, top: Double(Landmarks.transit.floor), bottom: 30, kind: .rungs),
            Climb(id: "rungs.sump", x: Double(Landmarks.hatch.c) + 0.5, top: 9.0, bottom: Double(Landmarks.sump.floor), kind: .rungs),
        ]

        w.decals = [
            Decal(text: "SHELTER 4 · −2,600 FT", pos: V2(20.4, 27.3), size: 0.3, vertical: false),
            Decal(text: "SERVICE SHAFT 7  ▸  MAINT", pos: V2(25.08, 18.8), size: 0.28, vertical: true),
            Decal(text: "MAINT · −2,475 FT", pos: V2(27.6, 6.1), size: 0.3, vertical: false),
            Decal(text: "LINE 4 · WARM", pos: V2(31.6, 8.2), size: 0.22, vertical: false),
            Decal(text: "OUTPOST 9 · −2,475 FT", pos: V2(74.4, 5.9), size: 0.26, vertical: false),
            Decal(text: "SUMP", pos: V2(80.4, 11.0), size: 0.26, vertical: false),
            Decal(text: "TRANSIT · −2,440 FT", pos: V2(64.0, 1.5), size: 0.26, vertical: false),
            Decal(text: "LOADING ▾ DEPOT", pos: V2(101.2, 1.4), size: 0.22, vertical: false),
            Decal(text: "↓ gardens  —O.", pos: V2(102.0, 2.6), size: 0.2, vertical: false),
        ]
        return w
    }

    /// Things in the earth, placed the same way in every world: ore and quartz veins, old-world relics,
    /// spores. Only in packed dirt, away from the rooms and the crystal.
    static func scatterFinds(_ w: World) -> [Buried] {
        var out: [Buried] = []
        func open(_ c: Int, _ r: Int) -> Bool { w.m(c, r) == .dirt && w.bd(c, r) == .earth }
        for r in 11..<(Landmarks.height - 3) {
            for c in 3..<(Landmarks.width - 4) where open(c, r) {
                if abs(Double(c) + 0.5 - Landmarks.crystal.x) < 3 && abs(Double(r) - Landmarks.crystal.y) < 3 { continue }
                let h = hash2(c * 13 + 7, r * 7 + 3)
                guard h < 0.03 else { continue }
                let k = hash2(c * 3 + 1, r * 17 + 5)
                let depth = Double(r) / Double(Landmarks.height)
                let item: ItemID
                switch k {
                case ..<0.34: item = .copperOre
                case ..<(0.52 + depth * 0.1): item = .ironOre
                case ..<0.68: item = .quartz
                case ..<0.76: item = .coin
                case ..<0.82: item = .photo
                case ..<0.87: item = .toy
                case ..<0.95: item = .spores
                default: item = .seedTin
                }
                // Ore comes in veins: a few pieces together.
                let n = (item == .copperOre || item == .ironOre || item == .quartz) ? 1 + Int(hash2(c, r * 5) * 3) : 1
                for j in 0..<n {
                    let dc = j == 0 ? 0 : Int(hash2(c + j, r) * 3) - 1, dr = j == 0 ? 0 : Int(hash2(c, r + j) * 3) - 1
                    guard open(c + dc, r + dr) else { continue }
                    let p = V2(Double(c + dc) + 0.3 + hash2(c, j) * 0.4, Double(r + dr) + 0.3 + hash2(r, j) * 0.4)
                    out.append(Buried(id: "f.\(c + dc).\(r + dr)", item: ItemStack(item), pos: p))
                }
            }
        }
        // one per tile
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// Roots wander down through the earth here and there: wood for planks, wherever Max digs.
    static func scatterRoots(_ w: World) {
        for r in 12..<(Landmarks.height - 6) {
            for c in 3..<(Landmarks.width - 4) where w.m(c, r) == .dirt && w.bd(c, r) == .earth && hash2(c * 5 + 11, r * 11 + 2) < 0.0045 {
                var x = c, y = r
                let len = 5 + Int(hash2(c, r * 3) * 7)
                for i in 0..<len {
                    guard w.m(x, y) == .dirt && w.bd(x, y) == .earth else { break }
                    w.set(x, y, .root)
                    y += 1
                    if hash2(x * 7, y + i) < 0.35 { x += hash2(x, y * 3) < 0.5 ? -1 : 1 }
                }
            }
        }
    }
}
