import Foundation

public enum ItemID: String, Codable, CaseIterable, Sendable {
    case chargeCrystal, liftTooth, spareGrip, fasteners, pipe, wire, lampCell
    case seedTin, pressureGauge, batteryCell, greens, trailMeal
    case lamp, ladderSection, waterTank
    case pressureValve, rope
    case ration

    public var name: String {
        switch self {
        case .chargeCrystal: return "Charge crystal"
        case .liftTooth: return "Lift tooth"
        case .spareGrip: return "Spare grip"
        case .fasteners: return "Fasteners"
        case .pipe: return "Pipe length"
        case .wire: return "Wire"
        case .lampCell: return "Lamp cell"
        case .seedTin: return "Seed tin"
        case .pressureGauge: return "Cracked pressure gauge"
        case .batteryCell: return "Battery cell"
        case .greens: return "Greens"
        case .trailMeal: return "Trail meal"
        case .lamp: return "Lamp"
        case .ladderSection: return "Ladder section"
        case .waterTank: return "Water tank"
        case .pressureValve: return "Pressure valve"
        case .rope: return "Rope"
        case .ration: return "Tinned ration"
        }
    }

    public var blurb: String {
        switch self {
        case .chargeCrystal: return "Violet, faintly warm. Could bridge a cracked cell."
        case .liftTooth: return "A hardened tooth off a lift rack. With a grip, it's a pick."
        case .spareGrip: return "A worn shovel grip from the locker."
        case .fasteners: return "Bolts, washers, a few rivets."
        case .pipe: return "Bulky. Good for ladder rails or a tank."
        case .wire: return "Copper, mostly unkinked."
        case .lampCell: return "Holds a charge for a long while."
        case .seedTin: return "Old seeds. Some might still wake up."
        case .pressureGauge: return "Cracked glass, working needle. A pump needs one."
        case .batteryCell: return "Heavy. Enough to wake a battery bank."
        case .greens: return "Fresh. Grown at home."
        case .trailMeal: return "Restores Max's strength on a long dig."
        case .lamp: return "Place it to light the way home."
        case .ladderSection: return "Place under an opening to climb it."
        case .waterTank: return "Place it in the workshop to store water."
        case .pressureValve: return "Brass, heavy, threaded both ends. A pump won't hold pressure without one."
        case .rope: return "Old climbing line. Two lengths and an anchor will get you up a chimney."
        case .ration: return "Beans, mostly. Eat one at the pantry to get your strength back."
        }
    }

    /// Bulky things take a whole backpack slot and don't stack.
    public var bulky: Bool {
        switch self {
        case .pipe, .batteryCell, .ladderSection, .waterTank: return true
        default: return false
        }
    }
    public var maxStack: Int { bulky ? 1 : 6 }
}

public struct ItemStack: Codable, Equatable, Hashable, Sendable {
    public var id: ItemID
    public var count: Int
    public init(_ id: ItemID, _ count: Int = 1) { self.id = id; self.count = count }
}

public enum Tool: String, Codable, CaseIterable, Sendable {
    case shovel, flashlight, shortPick
    public var name: String {
        switch self {
        case .shovel: return "Shovel"
        case .flashlight: return "Flashlight"
        case .shortPick: return "Short pick"
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
    public var belt: [Tool] = [.shovel]
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
    public mutating func add(_ id: ItemID, _ n: Int) { items[id.rawValue, default: 0] += n }
    @discardableResult public mutating func remove(_ id: ItemID, _ n: Int) -> Bool {
        guard count(id) >= n else { return false }
        items[id.rawValue] = count(id) - n
        if items[id.rawValue] == 0 { items[id.rawValue] = nil }
        return true
    }
}

public struct Recipe: Identifiable, Sendable {
    public enum Output: Sendable { case item(ItemID, Int), tool(Tool) }
    public var id: String
    public var name: String
    public var inputs: [ItemStack]
    public var output: Output
    public var note: String
    /// Story flag that makes this recipe appear (Max has seen the problem it solves).
    public var unlockFlag: String
}

public enum Recipes {
    public static let all: [Recipe] = [
        Recipe(id: "flashlight", name: "Repair flashlight", inputs: [ItemStack(.chargeCrystal)], output: .tool(.flashlight),
               note: "Bridge the cracked cell with the crystal.", unlockFlag: "sawFlashlight"),
        Recipe(id: "pick", name: "Short pick", inputs: [ItemStack(.liftTooth), ItemStack(.spareGrip)], output: .tool(.shortPick),
               note: "Opens soft seams overhead and cuts footholds.", unlockFlag: "needPick"),
        Recipe(id: "ladder", name: "Ladder section", inputs: [ItemStack(.pipe, 2), ItemStack(.fasteners, 4)], output: .item(.ladderSection, 1),
               note: "Bridges a tall opening, like the bottom of the shaft.", unlockFlag: "needLadder"),
        Recipe(id: "lamp", name: "Lamp", inputs: [ItemStack(.lampCell), ItemStack(.wire), ItemStack(.fasteners)], output: .item(.lamp, 1),
               note: "Stays where you place it. Lights the way home.", unlockFlag: "ch2Done"),
        Recipe(id: "tank", name: "Water tank", inputs: [ItemStack(.pipe), ItemStack(.fasteners, 2)], output: .item(.waterTank, 1),
               note: "Stores what the pump sends home.", unlockFlag: "sawPump"),
        Recipe(id: "meal", name: "Trail meal", inputs: [ItemStack(.greens, 2)], output: .item(.trailMeal, 1),
               note: "Eat it on a dig to get your strength back.", unlockFlag: "harvested"),
        Recipe(id: "rope", name: "Rope", inputs: [ItemStack(.wire, 2)], output: .item(.rope, 1),
               note: "Braid wire into a climbing line.", unlockFlag: "sawChimney"),
    ]
}
