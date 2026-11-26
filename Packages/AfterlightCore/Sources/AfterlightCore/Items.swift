import Foundation

public enum ItemID: String, Codable, CaseIterable, Sendable {
    case chargeCrystal, liftTooth, spareGrip, fasteners, pipe, wire, lampCell
    case seedTin, pressureGauge, batteryCell, greens, trailMeal
    case lamp, ladderSection, waterTank
    case pressureValve, rope
    case ration
    // finds in the earth
    case copperOre, ironOre, quartz, coin, photo, toy, spores
    case campCrate
    case glowcap
    case workbenchKit, cotKit
    case woodLadder, torch
    case tape
    // Milestone 1: water
    case strap, gasket, hoseClamp, waterCan, filterAssembly, sketch, roster

    public var name: String { ItemTable.row(self)?.name ?? rawValue }

    public var blurb: String { ItemTable.row(self)?.blurb ?? "" }

    /// Bulky things take a whole backpack slot and don't stack.
    public var bulky: Bool { ItemTable.row(self)?.bulky ?? false }
    public var maxStack: Int { bulky ? 1 : 6 }
}

public struct ItemStack: Codable, Equatable, Hashable, Sendable {
    public var id: ItemID
    public var count: Int
    public init(_ id: ItemID, _ count: Int = 1) { self.id = id; self.count = count }
}

public enum Tool: String, Codable, CaseIterable, Sendable {
    case shovel, flashlight, shortPick, hammer, breaker
    public var name: String {
        switch self {
        case .shovel: return "Shovel"
        case .flashlight: return "Flashlight"
        case .shortPick: return "Short pick"
        case .hammer: return "Hammer"
        case .breaker: return "Rock breaker"
        }
    }
}

/// Max's belt (tools), his bag (ten slots, small stacks) and the wood bundle strapped outside it.
public struct Inventory: Codable, Equatable, Sendable {
    public static let capacity = 10
    public static let woodCap = 200
    public static let woodPerRootTile = 10
    public static let plankCost = 5
    public var slots: [ItemStack?] = Array(repeating: nil, count: Inventory.capacity)
    public var belt: [Tool] = [.shovel, .hammer]
    /// Wood rides lashed to the outside of the bag and doesn't take a slot.
    public var wood = 0

    public init() {}

    enum CodingKeys: String, CodingKey { case slots, belt, wood }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        var s = try c.decodeIfPresent([ItemStack?].self, forKey: .slots) ?? []
        // Older saves had a six-slot pack.
        if s.count < Inventory.capacity { s += Array(repeating: nil, count: Inventory.capacity - s.count) }
        slots = s
        belt = try c.decodeIfPresent([Tool].self, forKey: .belt) ?? [.shovel]
        // Max always carries his father's hammer.
        if !belt.contains(.hammer) { belt.insert(.hammer, at: Swift.min(1, belt.count)) }
        wood = try c.decodeIfPresent(Int.self, forKey: .wood) ?? 0
    }

    /// Adds wood up to the cap; returns how much fit.
    @discardableResult
    public mutating func addWood(_ n: Int) -> Int {
        let k = Swift.max(0, Swift.min(n, Inventory.woodCap - wood))
        wood += k
        return k
    }

    public func count(_ id: ItemID) -> Int { slots.reduce(0) { $0 + (($1?.id == id) ? $1!.count : 0) } }
    public var freeSlots: Int { slots.filter { $0 == nil }.count }
    public func has(_ t: Tool) -> Bool { belt.contains(t) }

    /// How many of `id` would fit right now.
    public func room(for id: ItemID) -> Int {
        var n = 0
        for s in slots {
            if let s, s.id == id { n += id.maxStack - s.count } else if s == nil { n += id.maxStack }
        }
        return n
    }

    /// Adds as many as fit; returns how many were added.
    @discardableResult
    public mutating func add(_ id: ItemID, _ count: Int = 1) -> Int {
        var left = count
        for i in slots.indices where left > 0 {
            if var s = slots[i], s.id == id, s.count < id.maxStack {
                let k = min(left, id.maxStack - s.count)
                s.count += k; left -= k; slots[i] = s
            }
        }
        for i in slots.indices where left > 0 && slots[i] == nil {
            let k = min(left, id.maxStack)
            slots[i] = ItemStack(id, k); left -= k
        }
        return count - left
    }

    @discardableResult
    public mutating func remove(_ id: ItemID, _ count: Int = 1) -> Bool {
        guard self.count(id) >= count else { return false }
        var left = count
        for i in slots.indices.reversed() where left > 0 {
            if var s = slots[i], s.id == id {
                let k = min(left, s.count)
                s.count -= k; left -= k
                slots[i] = s.count > 0 ? s : nil
            }
        }
        return true
    }
}

/// Workshop storage: no limits, crafting at home pulls from here too.
public struct Storage: Codable, Equatable, Sendable {
    public var items: [String: Int] = [:]
    public init() {}
    public func count(_ id: ItemID) -> Int { items[id.rawValue] ?? 0 }
    /// Wood kept in storage (no cap).
    public var wood: Int {
        get { items["wood"] ?? 0 }
        set { items["wood"] = newValue > 0 ? newValue : nil }
    }
    public mutating func add(_ id: ItemID, _ n: Int) { items[id.rawValue, default: 0] += n }
    @discardableResult public mutating func remove(_ id: ItemID, _ n: Int) -> Bool {
        guard count(id) >= n else { return false }
        items[id.rawValue] = count(id) - n
        if items[id.rawValue] == 0 { items[id.rawValue] = nil }
        return true
    }
}

public struct Recipe: Identifiable, Sendable {
    public enum Output: Sendable { case item(ItemID, Int), tool(Tool), upgrade(String) }
    public var id: String
    public var name: String
    public var inputs: [ItemStack]
    public var output: Output
    public var note: String
    /// Story flag that makes this recipe appear (Max has seen the problem it solves).
    public var unlockFlag: String
    /// Wood from the bundle on the bag.
    public var wood = 0
    /// Needs a workbench nearby (home, or a field workbench).
    public var bench = true
}

extension ItemID {
    /// What eating it does: hunger filled, stamina and health restored.
    public var food: (hunger: Double, stamina: Double, health: Double)? {
        ItemTable.row(self)?.food.map { ($0.hunger, $0.stamina, $0.health) }
    }
}

public enum Recipes {
    /// Every recipe, from Content/items/recipes.json.
    public static let all: [Recipe] = load().recipes
    /// Anything in the file the game couldn't understand (a validation test keeps this empty).
    public static let loadErrors: [String] = load().errors

    struct Row: Decodable {
        struct Stack: Decodable { var item: String; var count: Int? }
        struct Out: Decodable { var item: String?; var count: Int?; var tool: String?; var upgrade: String? }
        var id: String, name: String, inputs: [Stack], output: Out, note: String, unlock: String
        var wood: Int?, bench: Bool?
    }

    static func load() -> (recipes: [Recipe], errors: [String]) {
        guard let d = ContentFiles.file("items/recipes.json") else { return ([], ["recipes.json is missing"]) }
        let rows: [Row]
        do { rows = try JSONDecoder().decode([Row].self, from: d) } catch { return ([], ["recipes.json: \(error)"]) }
        var out: [Recipe] = [], errs: [String] = []
        for r in rows {
            var inputs: [ItemStack] = []
            for s in r.inputs {
                guard let id = ItemID(rawValue: s.item) else { errs.append("\(r.id): unknown item \(s.item)"); continue }
                inputs.append(ItemStack(id, s.count ?? 1))
            }
            let output: Recipe.Output
            if let i = r.output.item, let id = ItemID(rawValue: i) { output = .item(id, r.output.count ?? 1) }
            else if let t = r.output.tool, let tool = Tool(rawValue: t) { output = .tool(tool) }
            else if let u = r.output.upgrade { output = .upgrade(u) }
            else { errs.append("\(r.id): bad output"); continue }
            out.append(Recipe(id: r.id, name: r.name, inputs: inputs, output: output, note: r.note, unlockFlag: r.unlock,
                              wood: r.wood ?? 0, bench: r.bench ?? true))
        }
        if Set(out.map(\.id)).count != out.count { errs.append("duplicate recipe ids") }
        return (out, errs)
    }
}

/// Item facts from Content/items/items.json: names, descriptions, bulk and food value.
public enum ItemTable {
    public struct Row: Decodable, Sendable {
        public struct Food: Decodable, Sendable { public var hunger: Double, stamina: Double, health: Double }
        public var id: String, name: String, blurb: String
        public var bulky: Bool?
        public var food: Food?
    }
    static let rows: [String: Row] = {
        guard let d = ContentFiles.file("items/items.json"), let r = try? JSONDecoder().decode([Row].self, from: d) else { return [:] }
        return Dictionary(r.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }()
    public static func row(_ id: ItemID) -> Row? { rows[id.rawValue] }
    /// Item ids with no entry in the file (a validation test keeps this empty).
    public static var missing: [ItemID] { ItemID.allCases.filter { rows[$0.rawValue] == nil } }
}
