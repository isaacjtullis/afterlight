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
                        appliedJobs: Array(appliedJobs).sorted(), activeJob: activeJob, pinnedRecipe: pinnedRecipe, mara: mara)
    }

    /// Restore a saved game on top of a freshly generated world.
    public static func load(_ s: SaveGame, clock: @escaping () -> Date = { Date() }) -> Game {
        let g = Game()
        g.clock = clock
        let w = g.world
        if let m = RLE.decode(s.mat, count: w.w * w.h) {
            for i in m.indices { w.mat[i] = Mat(rawValue: m[i]) ?? .dirt }
        }
        if let d = RLE.decode(s.dens, count: w.dw * w.dh) {
            for i in d.indices { w.dens[i] = Float(d[i]) / 255 }
        }
        w.buried = s.buried
        w.props = s.props
        w.climbs = s.climbs
        w.markAllDirty()
        g.max.pos = s.maxPos
        g.max.face = s.maxFace
        g.max.stamina = s.stamina
        g.max.digFloor = s.maxPos.y
        g.inv = s.inventory
        g.storage = s.storage
        g.story = s.story
        g.odi = s.odi
        g.appliedJobs = Set(s.appliedJobs)
        g.activeJob = s.activeJob
        g.pinnedRecipe = s.pinnedRecipe
        if let m = s.mara { g.mara = m }
        g.time = s.playSeconds
        g.started = true
        g.candle = 1
        if g.story.flags.contains("broke") { g.ambient = 1 }
        if g.inv.has(.flashlight) && g.story.flags.contains("flashOn") { g.max.flashI = 1 }
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
