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
        case .lamp: return "Lantern"
        case .ladderSection: return "Ladder section"
        case .waterTank: return "Water tank"
        case .pressureValve: return "Pressure valve"
        case .rope: return "Rope"
        case .ration: return "Tinned ration"
        case .copperOre: return "Copper ore"
        case .ironOre: return "Iron ore"
        case .tape: return "Duct tape"
        case .quartz: return "Quartz"
        case .coin: return "Old coin"
        case .photo: return "Faded photo"
        case .toy: return "Tin toy"
        case .spores: return "Glowcap spores"
        case .campCrate: return "Camp crate"
        case .glowcap: return "Glowcap"
        case .workbenchKit: return "Field workbench"
        case .cotKit: return "Cot"
        case .woodLadder: return "Wooden ladder"
        case .torch: return "Root torch"
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
        case .lamp: return "Set it down anywhere and it keeps burning. Light the way home."
        case .ladderSection: return "Place under an opening to climb it."
        case .waterTank: return "Place it in the workshop to store water."
        case .pressureValve: return "Brass, heavy, threaded both ends. A pump won't hold pressure without one."
        case .rope: return "Old climbing line. Two lengths and an anchor will get you up a chimney."
        case .ration: return "Beans, mostly. Eat one at the pantry to get your strength back."
        case .copperOre: return "Green-streaked rock. Smelted down, it’s wire."
        case .ironOre: return "Heavy and rust-red. Good for tools and fittings."
        case .tape: return "Silver and sticky. Holds most things together, for a while."
        case .quartz: return "Clear as ice. Lenses, lamps, maybe a radio."
        case .coin: return "Money from before. Worth nothing, except to someone who misses it."
        case .photo: return "A family at a beach, squinting into a sun nobody here has seen."
        case .toy: return "A wind-up bird. It still hops, a little."
        case .spores: return "A pinch of dust that glows faintly. They grow in the dark."
        case .campCrate: return "Pitch it somewhere flat to make a camp: a crate to stash things in, far from home."
        case .glowcap: return "A pale mushroom with a faint glow. Two of them, cooked, make a meal."
        case .workbenchKit: return "Set it up anywhere and build there, not just at home."
        case .cotKit: return "A place to lie down and get your strength back, wherever you set it."
        case .woodLadder: return "Lean it against any ledge and it stays there: a way up and back down."
        case .torch: return "Bundled root fibre soaked in resin. Set it down for a warm light that keeps burning."
        }
    }

    /// Bulky things take a whole backpack slot and don't stack.
    public var bulky: Bool {
        switch self {
        case .pipe, .batteryCell, .ladderSection, .waterTank, .campCrate, .workbenchKit, .cotKit, .woodLadder: return true
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
        switch self {
        case .ration: return (45, 20, 8)
        case .trailMeal: return (60, 30, 10)
        case .greens: return (25, 10, 5)
        case .glowcap: return (15, 5, 3)
        default: return nil
        }
    }
}

public enum Recipes {
    public static let all: [Recipe] = [
        Recipe(id: "flashlight", name: "Repair flashlight", inputs: [ItemStack(.chargeCrystal)], output: .tool(.flashlight),
               note: "Bridge the cracked cell with the crystal.", unlockFlag: "sawFlashlight"),
        Recipe(id: "pick", name: "Short pick", inputs: [ItemStack(.liftTooth), ItemStack(.spareGrip)], output: .tool(.shortPick),
               note: "Opens soft seams overhead and cuts footholds.", unlockFlag: "needPick"),
        Recipe(id: "ladder", name: "Ladder section", inputs: [ItemStack(.pipe, 2), ItemStack(.fasteners, 4)], output: .item(.ladderSection, 1),
               note: "Bridges a tall opening, like the bottom of the shaft.", unlockFlag: "needLadder"),
        Recipe(id: "lamp", name: "Lantern", inputs: [ItemStack(.lampCell), ItemStack(.wire), ItemStack(.fasteners)], output: .item(.lamp, 1),
               note: "Stays where you place it. Lights the way home.", unlockFlag: "lampIdea"),
        Recipe(id: "tank", name: "Water tank", inputs: [ItemStack(.pipe), ItemStack(.fasteners, 2)], output: .item(.waterTank, 1),
               note: "Stores what the pump sends home.", unlockFlag: "sawPump"),
        Recipe(id: "meal", name: "Trail meal", inputs: [ItemStack(.greens, 2)], output: .item(.trailMeal, 1),
               note: "Eat it on a dig to get your strength back.", unlockFlag: "harvested"),
        Recipe(id: "rope", name: "Rope", inputs: [ItemStack(.wire, 2)], output: .item(.rope, 1),
               note: "Braid wire into a climbing line.", unlockFlag: "sawChimney"),
        Recipe(id: "camp", name: "Camp crate", inputs: [ItemStack(.fasteners, 1), ItemStack(.tape, 1)], output: .item(.campCrate, 1),
               note: "Pitch it far from home to keep things there.", unlockFlag: "sawPlatform", wood: 20, bench: false),
        Recipe(id: "cell", name: "Ore cell", inputs: [ItemStack(.copperOre, 3), ItemStack(.quartz, 1)], output: .item(.batteryCell, 1),
               note: "Copper plates and a quartz spacer: a crude battery cell. Powers the generator.", unlockFlag: "genLooked"),
        Recipe(id: "fieldBench", name: "Field workbench", inputs: [ItemStack(.fasteners, 1), ItemStack(.tape, 1)], output: .item(.workbenchKit, 1),
               note: "Thirty wood. Set it up anywhere and build there.", unlockFlag: "wood", wood: 30, bench: false),
        Recipe(id: "cot", name: "Cot", inputs: [ItemStack(.tape, 1)], output: .item(.cotKit, 1),
               note: "Rest wherever you set it.", unlockFlag: "wood", wood: 25),
        Recipe(id: "woodLadder", name: "Wooden ladder", inputs: [], output: .item(.woodLadder, 1),
               note: "Lean it on any ledge up to six tiles high. It stays: a way up and back.", unlockFlag: "wood", wood: 15),
        Recipe(id: "torch", name: "Root torch", inputs: [], output: .item(.torch, 1),
               note: "A warm light that keeps burning. No cell needed.", unlockFlag: "wood", wood: 6, bench: false),
        Recipe(id: "breaker", name: "Rock breaker", inputs: [ItemStack(.ironOre, 4), ItemStack(.fasteners, 2)], output: .tool(.breaker),
               note: "An iron wedge-hammer. Cracks bedrock into rubble the shovel can clear.", unlockFlag: "hitRock", wood: 10),
        Recipe(id: "lantern2", name: "Reflector lantern", inputs: [ItemStack(.copperOre, 2), ItemStack(.tape, 1)], output: .upgrade("lantern2"),
               note: "Level 2. Polished copper behind the flame: every lantern reaches further.", unlockFlag: "lampIdea", wood: 5),
        Recipe(id: "lantern3", name: "Quartz lantern", inputs: [ItemStack(.quartz, 2), ItemStack(.copperOre, 2)], output: .upgrade("lantern3"),
               note: "Level 3. A quartz lens spreads the light wide.", unlockFlag: "lampIdea", wood: 10),
        Recipe(id: "lantern4", name: "Arc lantern", inputs: [ItemStack(.batteryCell, 1), ItemStack(.quartz, 2), ItemStack(.wire, 2)], output: .upgrade("lantern4"),
               note: "Level 4. A crackling arc instead of a wick.", unlockFlag: "lampIdea"),
        Recipe(id: "lantern5", name: "Iron beam lantern", inputs: [ItemStack(.ironOre, 4), ItemStack(.quartz, 3), ItemStack(.batteryCell, 1)], output: .upgrade("lantern5"),
               note: "Level 5. Iron housing, a big lens. Floods a whole cavern with light.", unlockFlag: "lampIdea", wood: 20),
        Recipe(id: "plot", name: "Garden plot", inputs: [], output: .upgrade("plot"),
               note: "A raised bed for the quarters. More plots, more food.", unlockFlag: "wood", wood: 12),
        Recipe(id: "barrel", name: "Bigger barrel", inputs: [ItemStack(.pipe, 1), ItemStack(.tape, 1)], output: .upgrade("barrel"),
               note: "Doubles what the water barrel holds.", unlockFlag: "wood", wood: 20),
        Recipe(id: "table", name: "Table and chair", inputs: [ItemStack(.fasteners, 2)], output: .upgrade("table"),
               note: "Somewhere to sit and eat. Meals at home go further.", unlockFlag: "wood", wood: 30),

    ]
}
