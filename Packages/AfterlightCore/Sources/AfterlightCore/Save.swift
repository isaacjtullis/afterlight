import Foundation

/// Everything needed to restore a game: positions, terrain, objects, inventories, quests,
/// relationships and jobs. Terrain is stored as run-length-encoded bytes so cloud saves stay small.
public struct SaveGame: Codable, Sendable {
    public static let currentVersion = 1
    public var version = SaveGame.currentVersion
    public var savedAt: Date
    public var playSeconds: Double
    public var maxPos: V2
    public var maxFace: Int
    public var stamina: Double
    public var inventory: Inventory
    public var storage: Storage
    public var story: Story
    public var odi: NPCState
    public var mat: String          // base64 RLE of tile materials
    public var dens: String         // base64 RLE of the quantized density field
    public var buried: [Buried]
    public var props: [Prop]
    public var climbs: [Climb]
    public var appliedJobs: [String]
    public var activeJob: JobRecord?
    public var pinnedRecipe: String?
    public var mara: NPCState?
    public var health: Double?
    public var battery: Double?
    public var quarters: Quarters?
    public var hunger: Double?
}

enum RLE {
    static func encode(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count / 8)
        var i = 0
        while i < bytes.count {
            let v = bytes[i]
            var n = 1
            while i + n < bytes.count && bytes[i + n] == v && n < 255 { n += 1 }
            out.append(UInt8(n)); out.append(v)
            i += n
        }
        return Data(out).base64EncodedString()
    }
    static func decode(_ s: String, count: Int) -> [UInt8]? {
        guard let d = Data(base64Encoded: s) else { return nil }
        let b = [UInt8](d)
        var out: [UInt8] = []
        out.reserveCapacity(count)
        var i = 0
        while i + 1 < b.count {
            out.append(contentsOf: repeatElement(b[i + 1], count: Int(b[i])))
            i += 2
        }
        return out.count == count ? out : nil
    }
}

extension Game {
    public func makeSave() -> SaveGame {
        let matBytes = world.mat.map(\.rawValue)
        let densBytes = world.dens.map { UInt8(clampD(Double($0) * 255, 0, 255).rounded()) }
        return SaveGame(savedAt: clock(), playSeconds: time, maxPos: max.pos, maxFace: max.face, stamina: max.stamina,
                        inventory: inv, storage: storage, story: story, odi: odi,
                        mat: RLE.encode(matBytes), dens: RLE.encode(densBytes),
                        buried: world.buried, props: world.props, climbs: world.climbs,
                        appliedJobs: Array(appliedJobs).sorted(), activeJob: activeJob, pinnedRecipe: pinnedRecipe, mara: mara, health: max.health, battery: battery, quarters: quarters, hunger: max.hunger)
    }

    /// Restore a saved game on top of a freshly generated world.
    public static func load(_ s: SaveGame, clock: @escaping () -> Date = { Date() }) -> Game {
        let g = Game()
        g.clock = clock
        let w = g.world
        let freshMat = w.mat, freshDens = w.dens, freshProps = w.props, freshClimbs = w.climbs
        if let m = RLE.decode(s.mat, count: w.w * w.h) {
            for i in m.indices { w.mat[i] = Mat(rawValue: m[i]) ?? .dirt }
        }
        if let d = RLE.decode(s.dens, count: w.dw * w.dh) {
            for i in d.indices { w.dens[i] = Float(d[i]) / 255 }
        }
        w.buried = s.buried
        w.props = s.props
        w.climbs = s.climbs
        for f in freshProps where Game.addedLater.contains(f.id) && w.propIndex(f.id) == nil { w.props.append(f) }
        for c in freshClimbs where c.kind == .rungs && !w.climbs.contains(where: { $0.id == c.id }) { w.climbs.append(c) }
        if !s.story.flags.contains("world3") {
            // The broken east end of the transit platform and the loading shaft, added after these saves.
            let K = World.K
            for r in 0..<w.h { for c in 100...108 { w.mat[r * w.w + c] = freshMat[r * w.w + c] } }
            for j in 0..<w.dh { for i in (100 * K)...(109 * K) where i < w.dw { w.dens[j * w.dw + i] = freshDens[j * w.dw + i] } }
        }
        var story = s.story
        story.flags.insert("world3")
        // The steel over the warm-pipe patch was low enough to catch Max's head: it's packed earth now.
        if w.m(35, 6) == .metal { w.mat[6 * w.w + 35] = Mat.dirt }
        if !story.flags.contains("gen1") {
            // The generator mission came later: give the lift car its battery cell and lay in the ore near home.
            if !story.flags.contains("shelterLit"), let i = w.propIndex("liftcar"), !w.props[i].stock.contains(where: { $0.id == .batteryCell }) {
                w.props[i].stock.insert(ItemStack(.batteryCell), at: 0)
            }
            for b in [Buried(id: "home.cu1", item: ItemStack(.copperOre), pos: V2(33.6, 31.4)), Buried(id: "home.cu2", item: ItemStack(.copperOre), pos: V2(34.5, 31.6)),
                      Buried(id: "home.cu3", item: ItemStack(.copperOre), pos: V2(35.3, 31.3)), Buried(id: "home.qz", item: ItemStack(.quartz), pos: V2(39.4, 27.4))]
            where !w.buried.contains(where: { $0.id == b.id }) && w.m(Int(b.pos.x), Int(b.pos.y)).solid { w.buried.append(b) }
            story.flags.insert("gen1")
        }
        if !story.flags.contains("finds1") {
            let have = Set(w.buried.map(\.id))
            for b in WorldGen.scatterFinds(w) where !have.contains(b.id) && w.m(Int(b.pos.x), Int(b.pos.y)) == .dirt { w.buried.append(b) }
            story.flags.insert("finds1")
        }
        var maxPos = s.maxPos
        if !story.flags.contains(Game.worldVersionFlag) {
            // Saves from before the cavern moved: keep everything Max did up top (the shaft, the maintenance
            // level, the warm passage, Mara's outpost) and lay the new ground in below it.
            let K = World.K
            let keepShaft = 23...28
            for r in Game.reworkTopRow..<w.h { for c in 0..<w.w where !keepShaft.contains(c) { w.mat[r * w.w + c] = freshMat[r * w.w + c] } }
            for j in (Game.reworkTopRow * K)..<w.dh {
                for i in 0..<w.dw where !keepShaft.contains(i / K) { w.dens[j * w.dw + i] = freshDens[j * w.dw + i] }
            }
            for f in freshProps {
                if let i = w.propIndex(f.id) {
                    if f.pos.y >= Double(Game.reworkTopRow) && !keepShaft.contains(Int(f.pos.x)) && [.liftCar, .drillRig, .gantry, .crate].contains(f.kind) { w.props[i].pos = f.pos }
                } else if f.pos.y >= Double(Game.reworkTopRow) {
                    w.props.append(f)
                }
            }
            w.climbs.removeAll { $0.kind == .foothold && $0.bottom > Double(Game.reworkTopRow) && !keepShaft.contains(Int($0.x)) }
            if maxPos.y > Double(Game.reworkTopRow) && !keepShaft.contains(Int(maxPos.x)) { maxPos = V2(22.6, 30) }
            story.flags.remove("broke")
            story.flags.insert(Game.worldVersionFlag)
        }
        w.markAllDirty()
        g.max.pos = maxPos
        g.max.face = s.maxFace
        g.max.stamina = s.stamina
        g.max.health = s.health ?? 100
        g.battery = s.battery ?? 100
        if let q = s.quarters { g.quarters = q }
        g.max.hunger = s.hunger ?? 100
        g.max.digFloor = maxPos.y
        g.inv = s.inventory
        g.storage = s.storage
        g.story = story
        g.odi = s.odi
        g.appliedJobs = Set(s.appliedJobs)
        g.activeJob = s.activeJob
        g.pinnedRecipe = s.pinnedRecipe
        if let m = s.mara { g.mara = m }
        g.time = s.playSeconds
        g.started = true
        g.candle = 1
        if g.story.flags.contains("broke") { g.ambient = 1 }
        // Older builds turned the light off by clearing the story flag; keep the story, just switch it off.
        if g.inv.has(.flashlight) && !g.story.flags.contains("flashOn") && g.story.flags.contains("sawShaft") { g.story.flags.formUnion(["flashOn", "lightOff"]) }
        if g.flashlightLit { g.max.flashI = 1 }
        // Work that continued while the game was closed.
        g.advanceSharedJobs(to: g.clock())
        return g
    }

    public func encodeSave() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return try e.encode(makeSave())
    }

    public static func decodeSave(_ data: Data) throws -> SaveGame {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(SaveGame.self, from: data)
    }
}
