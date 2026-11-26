import Foundation

/// The living quarters: a top-down room behind the workshop with stations Max keeps up.
/// Everything here runs on the real clock, so the home changes while the game is closed.
public struct GardenPlot: Codable, Equatable, Sendable {
    public var crop: ItemID? = nil        // what was planted: seeds → greens, spores → glowcaps
    public var planted: Date? = nil
    public var watered: Date? = nil       // a plot dries out 12 hours after watering
    /// Minutes of good growing (watered and lit) so far.
    public var grown = 0.0
}

public struct Quarters: Codable, Equatable, Sendable {
    public var plots = [GardenPlot(), GardenPlot(), GardenPlot()]
    public var water = 40.0               // litres in the barrel, 0…100
    public var filter = 100.0             // how clean the filter is, 0…100
    public var charge = 60.0              // the lamp rack's battery, 0…100
    public var last: Date? = nil
    /// Things Max built for the room.
    public var decor: Set<String> = []
    public var barrelCap = 100.0
    /// Clean drinking water in the drum, in cups. A new game starts with four: about two working days.
    public var clean = 4.0
    /// The drum's drain fitting is clamped (until then it slowly leaks).
    public var drumSealed = false
    /// The new filter assembly is fitted and primed: the intake runs clean and refills the drum.
    public var filterFitted = false

    enum CodingKeys: String, CodingKey { case plots, water, filter, charge, last, decor, barrelCap, clean, drumSealed, filterFitted }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        plots = try c.decodeIfPresent([GardenPlot].self, forKey: .plots) ?? [GardenPlot(), GardenPlot(), GardenPlot()]
        water = try c.decodeIfPresent(Double.self, forKey: .water) ?? 40
        filter = try c.decodeIfPresent(Double.self, forKey: .filter) ?? 100
        charge = try c.decodeIfPresent(Double.self, forKey: .charge) ?? 60
        last = try c.decodeIfPresent(Date.self, forKey: .last)
        decor = try c.decodeIfPresent(Set<String>.self, forKey: .decor) ?? []
        barrelCap = try c.decodeIfPresent(Double.self, forKey: .barrelCap) ?? 100
        // Saves from before the water mission already lived past it: a sealed drum and a working filter.
        clean = try c.decodeIfPresent(Double.self, forKey: .clean) ?? 8
        drumSealed = try c.decodeIfPresent(Bool.self, forKey: .drumSealed) ?? true
        filterFitted = try c.decodeIfPresent(Bool.self, forKey: .filterFitted) ?? true
    }

    public static let growMinutes = 45.0
    public static let dryHours = 12.0

    public init() {}
}

public enum Station: String, CaseIterable, Sendable {
    case bed, pantry, stove, garden, water, lamps, bench, storage, door
}

extension Game {
    /// Bring the quarters up to the present: water drips in, the filter clogs, lamps drain, crops grow.
    public func quartersTick(now: Date) {
        guard let last = quarters.last else { quarters.last = now; return }
        let hours = Swift.max(0, now.timeIntervalSince(last) / 3600)
        guard hours > 0 else { return }
        quarters.last = now
        let piped = homeWater
        // Water: a steady drip from the rock (and much more once a pump sends water home).
        quarters.water = Swift.min(quarters.barrelCap, quarters.water + hours * (piped ? 12 : 2))
        quarters.filter = Swift.max(0, quarters.filter - hours * 3)
        // Lamps: wired to power they stay full; otherwise they drain.
        quarters.charge = story.flags.contains("power") ? 100 : Swift.max(0, quarters.charge - hours * 4)
        // A working filter refills the clean drum: a cup every half hour, up to twelve.
        if quarters.filterFitted { quarters.clean = Swift.min(Self.drumCap, quarters.clean + hours * 2) }
        // Crops grow while watered and lit.
        let lit = quarters.charge > 0
        for i in quarters.plots.indices where quarters.plots[i].crop != nil {
            guard let w = quarters.plots[i].watered else { continue }
            let wetUntil = w.addingTimeInterval(Quarters.dryHours * 3600)
            let start = Swift.max(last, w)
            let end = Swift.min(now, wetUntil)
            if lit && end > start { quarters.plots[i].grown += end.timeIntervalSince(start) / 60 }
        }
    }

    public func plotReady(_ i: Int) -> Bool {
        guard quarters.plots.indices.contains(i) else { return false }
        return quarters.plots[i].crop != nil && quarters.plots[i].grown >= Quarters.growMinutes
    }
    public func plotDry(_ i: Int, now: Date) -> Bool {
        guard quarters.plots.indices.contains(i) else { return false }
        guard quarters.plots[i].crop != nil else { return false }
        guard let w = quarters.plots[i].watered else { return true }
        return now.timeIntervalSince(w) > Quarters.dryHours * 3600
    }

    /// What Max can plant: a seed tin or glowcap spores.
    public var plantables: [ItemID] { [.seedTin, .spores].filter { available($0) > 0 } }

    public func plant(_ i: Int, _ what: ItemID) {
        guard quarters.plots.indices.contains(i), quarters.plots[i].crop == nil, available(what) > 0 else { return }
        consume(what, 1)
        quarters.plots[i] = GardenPlot(crop: what, planted: clock(), watered: nil, grown: 0)
        think(what == .spores ? "Glowcaps. They like the dark." : "In you go.", 1.8)
        emit(.saveNow)
    }

    public func waterPlot(_ i: Int) {
        guard quarters.plots.indices.contains(i), quarters.plots[i].crop != nil else { return }
        guard quarters.water >= 8 else { think("The barrel’s nearly dry.", 1.8); return }
        guard quarters.filter > 15 else { think("The filter’s clogged. That water would rot the roots.", 2.4); return }
        quarters.water -= 8
        quarters.plots[i].watered = clock()
        emit(.pour(at: max.pos))
        emit(.saveNow)
    }

    public func harvestPlot(_ i: Int) {
        guard plotReady(i), let crop = quarters.plots[i].crop else { return }
        let out: ItemID = crop == .spores ? .glowcap : .greens
        let n = crop == .spores ? 2 : 3
        let added = inv.add(out, n)
        if added < n { storage.add(out, n - added) }
        quarters.plots[i] = GardenPlot()
        story.flags.insert("harvested")
        story.step("seeds", "harvest")
        emit(.chime)
        think(out == .glowcap ? "Glowcaps. They glow a little in the bag." : "Greens. Grown here.", 2.2)
        emit(.saveNow)
    }

    /// Rinse the filter: hard work, but the water runs clean again.
    public func rinseFilter() {
        guard quarters.filter < 99 else { think("It’s clean.", 1.4); return }
        guard max.stamina >= 8 else { think("Too tired to scrub it now.", 1.8); return }
        max.stamina -= 8
        quarters.filter = 100
        emit(.pour(at: max.pos))
        think("Clean water again.", 1.6)
        emit(.saveNow)
    }

    /// Drink from the barrel.
    public func drink() {
        guard quarters.water >= 2 else { think("Empty.", 1.2); return }
        quarters.water -= 2
        recover(stamina: quarters.filter > 30 ? 12 : 4, health: quarters.filter > 30 ? 2 : 0)
        think(quarters.filter > 30 ? "Cold and clean." : "Tastes of rust. The filter needs rinsing.", 2)
        emit(.saveNow)
    }

    /// Charge the lamp rack from a cell.
    public func chargeLamps(with item: ItemID) {
        guard available(item) > 0 else { return }
        consume(item, 1)
        quarters.charge = Swift.min(100, quarters.charge + (item == .batteryCell ? 100 : 45))
        emit(.flashOn)
        think("The room brightens.", 1.6)
        emit(.saveNow)
    }

    /// Stove: two greens or two glowcaps make a trail meal.
    public var cookable: Bool { available(.greens) >= 2 || available(.glowcap) >= 2 }
    public func cook() {
        if available(.greens) >= 2 { consume(.greens, 2) } else if available(.glowcap) >= 2 { consume(.glowcap, 2) } else { think("Nothing to cook.", 1.4); return }
        let added = inv.add(.trailMeal, 1)
        if added < 1 { storage.add(.trailMeal, 1) }
        emit(.chime)
        think("Trail meal. That’ll keep me going out there.", 2.2)
        emit(.saveNow)
    }

    /// What needs Max's attention at home right now (for a nudge in the HUD).
    public func quartersNeeds(now: Date) -> [String] {
        var out: [String] = []
        if quarters.filter < 30 { out.append("Rinse the water filter") }
        if quarters.charge < 15 { out.append("Charge the lamps") }
        for i in quarters.plots.indices {
            if plotReady(i) { out.append("Harvest a garden plot"); break }
            if plotDry(i, now: now) { out.append("Water the garden"); break }
        }
        return out
    }
}
