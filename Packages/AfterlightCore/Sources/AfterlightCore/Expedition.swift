import Foundation

extension Quest {
    public static var farEdge: Quest { Quests.get("far") }
    public static var homeLight: Quest { Quests.get("homeLight") }
    public static var lantern: Quest { Quests.get("lantern") }
}

extension Game {
    /// Names camps by where they stand.
    func campName(at p: V2) -> String {
        if p.y < 4 && p.x < 102 { return "Platform camp" }
        if p.x >= 102 && p.x < 108 { return "Shaft-foot camp" }
        if p.x >= 108 { return "Cavern camp" }
        if p.y < 10 { return "Passage camp" }
        return "Camp"
    }

    /// Why a built thing can't be set down here, or nil if it can.
    func placeObstruction() -> String? {
        guard max.ground, max.mode == .walk else { return "I need my feet on the ground." }
        let p = max.pos
        for dx in [-0.7, 0.0, 0.7] {
            guard let g = world.groundY(p.x + dx, from: p.y - 0.6, to: p.y + 0.6), abs(g - p.y) < 0.25 else { return "Too uneven." }
        }
        if world.solid(p.x, p.y - 1.9) { return "Too cramped." }
        if world.props.contains(where: { ($0.kind == .fieldBench || $0.kind == .cot || $0.kind == .camp) && $0.pos.dist(p) < 1.6 }) { return "Something’s already here." }
        return nil
    }

    /// Is Max at a workbench: the one at home, or a field workbench he set up?
    public var atBench: Bool {
        nearBench || (atHome && abs(max.pos.y - 30) < 0.6) || world.props.contains { $0.kind == .fieldBench && $0.pos.dist(max.pos) < 2.0 }
    }

    /// Why a recipe can't be built right now (nil if it can).
    public func buildBlocker(_ r: Recipe) -> String? {
        if case .tool(let t) = r.output, inv.has(t) { return "Already made" }
        if case .upgrade(let u) = r.output, !upgradeOpen(u) {
            if u.hasPrefix("lantern"), let n = Int(u.dropFirst(7)), lanternLevel < n - 1 { return "Needs level \(n - 1) first" }
            return u == "plot" ? "The room’s full of plots" : "Already built"
        }
        if r.bench && !atBench { return "Needs a workbench" }
        if woodAvailable < r.wood { return "Needs \(r.wood) wood" }
        if let miss = r.inputs.first(where: { available($0.id) < $0.count }) { return "Needs \(miss.id.name.lowercased())" }
        return nil
    }

    /// Why a camp can't go here, or nil if it can.
    func campObstruction() -> String? {
        guard max.ground, max.mode == .walk else { return "I need my feet on the ground." }
        if atHome { return "I don’t need a camp at home. Storage is right there." }
        let p = max.pos
        for dx in [-0.9, 0.0, 0.9] {
            guard let g = world.groundY(p.x + dx, from: p.y - 0.6, to: p.y + 0.6), abs(g - p.y) < 0.25 else { return "Too uneven. I need a flat spot." }
        }
        if world.solid(p.x, p.y - 1.9) || world.solid(p.x + Double(max.face) * 0.8, p.y - 1.2) { return "Too cramped. I need some headroom." }
        if world.props.contains(where: { $0.kind == .camp && $0.pos.dist(p) < 6 }) { return "There’s already a camp right here." }
        return nil
    }

    /// Things Max can set down in the world.
    public static let placeables: Set<ItemID> = [.torch, .lamp, .workbenchKit, .cotKit, .woodLadder, .campCrate]

    /// Pick something to set down: the bag closes and the spot shows where it would go.
    public func beginPlacing(_ item: ItemID) {
        guard Game.placeables.contains(item), inv.count(item) > 0 || (atHome && storage.count(item) > 0) else { return }
        if inv.count(item) == 0 { take(item, 1) }
        guard inv.count(item) > 0 else { think("No room in the bag to carry it.", 2.4); return }
        placing = item
    }
    public func cancelPlacing() { placing = nil }

    /// Where the thing being placed would go, and why not if it can't.
    public func placementCheck(_ item: ItemID) -> (pos: V2, reason: String?) {
        let p = max.pos
        switch item {
        case .campCrate: return (p, campObstruction())
        case .woodLadder:
            if let s = ladderSpot() { return (V2(s.x, s.top), nil) }
            return (p, "No room to stand it up here")
        case .torch:
            guard max.ground else { return (p, "Feet on the ground first") }
            return (p, nil)
        case .lamp:
            guard max.ground else { return (p, "Feet on the ground first") }
            if world.props(of: .lamp).contains(where: { $0.pos.dist(p) < 2.5 && !$0.flags.contains("torch") }) { return (p, "There’s a lantern right here") }
            return (p, nil)
        default: return (p, placeObstruction())
        }
    }

    func expeditionContext() -> ContextAction? {
        let p = max.pos
        let f = story.flags
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        // Setting something down: only while placing it (chosen from Build or the bag).
        if let item = placing {
            guard inv.count(item) > 0 else { placing = nil; return nil }
            let spot = placementCheck(item)
            if let why = spot.reason { return act("placeNo", why, V2(spot.pos.x, spot.pos.y - 2.4)) }
            switch item {
            case .campCrate: return act("pitchCamp", "Set camp here", V2(p.x, p.y - 2.4), true)
            case .woodLadder: return act("setLadder", "Set the ladder", V2(spot.pos.x, spot.pos.y - 0.8), true)
            case .torch: return act("placeTorch", "Set the torch", V2(p.x, p.y - 2.2), true)
            case .lamp: return act("placeLamp", "Set the lantern", V2(p.x, p.y - 2.4), true)
            default: return act("place:\(item.rawValue)", "Set the \(item.name.lowercased())", V2(p.x, p.y - 2.4), true)
            }
        }
        for pr in world.props where abs(pr.pos.x - p.x) < 1.5 && abs(pr.pos.y - p.y) < 1.3 {
            switch pr.kind {
            case .camp: return act("camp:\(pr.id)", pr.flags.first(where: { $0.hasPrefix("name:") }).map { String($0.dropFirst(5)) } ?? "Camp crate", V2(pr.pos.x, pr.pos.y - 1.9))
            case .signalLamp:
                if !pr.flags.contains("lit") {
                    if available(.batteryCell) > 0 { return act("signal", "Fit the battery cell", V2(pr.pos.x, pr.pos.y - 3.2), true) }
                    return act("signalLook", "Signal lamp", V2(pr.pos.x, pr.pos.y - 3.2))
                }
                return act("flash.signal", "Flash the signal", V2(pr.pos.x, pr.pos.y - 3.2))
            case .lanternClue:
                if !f.contains("sawLantern") { return act("lantern", "Look at the lantern", V2(pr.pos.x, pr.pos.y - 1.6), true) }
            default: break
            }
        }
        // The generator: the first thing to fix, so home feels like home.
        if let gen = world.prop("generator"), !f.contains("shelterLit"), abs(p.x - gen.pos.x) < 0.8, abs(p.y - 30) < 0.5, f.contains("flashOn") {
            if !f.contains("genLooked") { return act("genLook", "Look at the generator", V2(gen.pos.x, 27.4), true) }
            if !f.contains("genFreed") { return act("genFree", "Hammer it loose", V2(gen.pos.x, 27.4), true) }
            if available(.batteryCell) > 0 { return act("genPower", "Fit the battery cell", V2(gen.pos.x, 27.4), true) }
            return act("genLook", "Generator", V2(gen.pos.x, 27.4))
        }
        for pr in world.props where (pr.kind == .fieldBench || pr.kind == .cot) && abs(pr.pos.x - p.x) < 1.2 && abs(pr.pos.y - p.y) < 1.0 {
            return pr.kind == .fieldBench ? act("fieldBench", "Workbench", V2(pr.pos.x, pr.pos.y - 1.8)) : act("cotRest", "Rest", V2(pr.pos.x, pr.pos.y - 1.4))
        }
        // The optional first lamp, at the tunnel mouth
        if inv.count(.lamp) > 0 && f.contains("lampIdea") && abs(p.x - Landmarks.lampSpot.x) < 1.2 && abs(p.y - 30) < 0.5
            && !world.props(of: .lamp).contains(where: { $0.pos.dist(Landmarks.lampSpot) < 2.5 }) {
            return act("placeLamp", "Place lantern at the tunnel mouth", V2(p.x, p.y - 2.4), true)
        }
        return nil
    }

    /// Power reaches home: the shelter light and the generator come on.
    func lightHome() {
        story.flags.insert("shelterLit")
        story.step("homeLight", "parts"); story.step("homeLight", "fix")
        if let i = world.propIndex("shelter.light") { world.props[i].flags.insert("lit") }
        if let i = world.propIndex("generator") { world.props[i].flags.insert("on") }
        quarters.charge = 100
        emit(.saveNow)
    }

    func performExpedition(_ id: String) -> Bool {
        switch id {
        case "pitchCamp":
            placing = nil
            guard campObstruction() == nil else { return true }
            inv.remove(.campCrate, 1)
            let name = campName(at: max.pos)
            var pr = Prop(id: "camp.\(Int(time * 1000))", kind: .camp, pos: max.pos)
            pr.flags = ["name:\(name)"]
            world.props.append(pr)
            story.step("far", "camp")
            think("\(name). Somewhere to leave things.", 2.6)
            emit(.placed("camp"))
            emit(.saveNow)
        case "genLook":
            story.flags.insert("genLooked")
            story.step("homeLight", "look")
            if !story.flags.contains("genFreed") {
                think("The generator. Seized solid, and its cell is dead. That’s why the lights are out.", 3.8)
                later(4) { $0.think("A few good knocks with the hammer, then a battery cell.", 3) }
            } else {
                think("Free and turning, but nothing to run on. It needs a battery cell.", 3.4)
                later(3.6) { $0.hint("Battery cells: the wrecked lift car just east has one. Or build an Ore cell from 3 copper ore and 1 quartz you dig up.", 8) }
            }
        case "genFree":
            guard let gen = world.prop("generator") else { return true }
            hammer(at: V2(gen.pos.x, 28.4), for: 1.5)
            story.flags.insert("genFreed")
            story.step("homeLight", "free")
            later(1.6) { g in
                g.think("It turns. Now it needs something to run on.", 2.8)
                g.later(3) { $0.hint("Battery cells: the wrecked lift car just east has one. Or build an Ore cell from 3 copper ore and 1 quartz you dig up.", 8) }
            }
            emit(.saveNow)
        case "genPower":
            guard let gen = world.prop("generator"), available(.batteryCell) > 0 else { return true }
            consume(.batteryCell, 1)
            hammer(at: V2(gen.pos.x, 28.4), for: 0.9)
            later(1.0) { g in
                g.lightHome()
                g.think("Light. Home looks like home again.", 3.4)
                g.emit(.flashOn); g.emit(.swell)
                g.later(4) { g2 in
                    if !g2.packedFood { g2.hint("Before heading out, pack food: the pantry by the storage has tins. Hunger drops while you work.", 8) }
                }
                g.emit(.saveNow)
            }
            _ = gen
        case "setLadder":
            placing = nil
            guard let spot = ladderSpot() else { return true }
            inv.remove(.woodLadder, 1)
            world.climbs.append(Climb(id: "wladder.\(Int(time * 1000))", x: spot.x, top: spot.top, bottom: max.pos.y, kind: .ladder))
            hammer(at: V2(spot.x, max.pos.y - 1), for: 0.9)
            emit(.placed("ladder"))
            emit(.saveNow)
        case "placeTorch":
            placing = nil
            inv.remove(.torch, 1)
            var pr = Prop(id: "torch.\(Int(time * 1000))", kind: .lamp, pos: max.pos)
            pr.flags = ["torch"]
            world.props.append(pr)
            emit(.placed("lamp"))
            emit(.saveNow)
        case "fieldBench":
            emit(.openSheet(.workbench))
        case "cotRest":
            recover(stamina: 100, health: 35)
            emit(.sleep)
            later(3.8) { $0.think("A short rest. Better.", 1.8) }
            emit(.saveNow)
        case "campSpot":
            think(campObstruction() ?? "This’ll do.", 2.4)
        case "placeNo":
            if let item = placing, let why = placementCheck(item).reason { think(why + ".", 2) }
        case "signal":
            guard let i = world.propIndex("signal"), available(.batteryCell) > 0 else { return true }
            consume(.batteryCell, 1)
            world.props[i].flags.insert("lit")
            story.step("far", "cell")
            story.flags.insert("signalLit")
            think("It’s alive. Anyone on the line can see that now.", 3.4)
            emit(.chime); emit(.swell)
            later(3.6) { g in if !g.story.flags.contains("answered") { g.startAnswer() } }
            emit(.saveNow)
        case "signalLook":
            story.flags.insert("sawSignal")
            think("A signal lamp. The cell’s long dead. A heavy battery cell would wake it.", 3.6)
            if !story.flags.contains("said.cellWhere") {
                story.flags.insert("said.cellWhere")
                later(3.8) { $0.hint("Battery cells are bulky: each takes a whole pocket. The old drill rig in the cavern might have one.", 7) }
            }
        case "lantern":
            story.flags.insert("sawLantern")
            story.addQuest(.lantern)
            think("A lantern. Still warm. Someone was here, not long ago.", 3.4)
            later(3.6) { $0.think("Chalk by the shaft: “gardens,” and an O.", 3) }
            emit(.saveNow)
        default:
            if id.hasPrefix("place:"), let item = ItemID(rawValue: String(id.dropFirst(6))) {
                guard placeObstruction() == nil, inv.count(item) > 0 else { return true }
                placing = nil
                inv.remove(item, 1)
                world.props.append(Prop(id: "\(item.rawValue).\(Int(time * 1000))", kind: item == .workbenchKit ? .fieldBench : .cot, pos: max.pos))
                hammer(at: V2(max.pos.x + Double(max.face) * 0.6, max.pos.y - 0.4), for: 0.9)
                emit(.placed("camp"))
                emit(.saveNow)
                return true
            }
            if id.hasPrefix("camp:") {
                openCamp = String(id.dropFirst(5))
                emit(.openSheet(.camp))
                return true
            }
            return false
        }
        return true
    }

    func expeditionTick(_ dt: Double) {
        let p = max.pos
        // Once the flashlight works, the first job is light at home.
        if story.flags.contains("flashOn") && !story.flags.contains("homeLightQuest") {
            story.flags.insert("homeLightQuest")
            if !story.flags.contains("shelterLit") {
                story.addQuest(.homeLight)
                later(10) { g in
                    guard !g.story.flags.contains("shelterLit") else { return }
                    g.think("The shelter’s light is out too. I want to come home to light.", 3.6)
                }
            }
        }
        if available(.batteryCell) > 0 { story.step("homeLight", "parts") }
        if packedFood { story.step("homeLight", "pack") }
        if inv.wood > 0 { story.flags.insert("wood") }
        // Leaving home without food, once: a nudge.
        if story.flags.contains("shelterLit") && !packedFood && p.x > 34 && p.y > 26 && !story.flags.contains("said.noFood") {
            story.flags.insert("said.noFood")
            think("I didn’t bring anything to eat.", 2.4)
            later(2.6) { $0.hint("Hunger drops as you work. Pack a ration at the pantry, then eat it from the bag when you need to.", 7) }
        }
        // Optional first build, once the flashlight works.
        if story.flags.contains("flashOn") && story.flags.contains("sawShaft") && !story.flags.contains("said.lampIdea") && time > 20 {
            story.flags.formUnion(["said.lampIdea", "lampIdea"])
            later(9) { g in
                guard g.world.props(of: .lamp).isEmpty else { return }
                g.think("The tunnel mouth is pitch black. A lamp there would light the way home.", 3.6)
                g.later(3.8) { $0.hint("Optional: make a lamp at the workbench (lamp cell, wire, fasteners) and place it at the glowing spot.", 7) }
            }
        }
        if story.chapter >= 4 {
            if p.x > Double(Landmarks.transit.x1) - 1 && p.y < 4 { story.step("far", "east") }
            if p.x > Double(Landmarks.caveStart) + 1 && p.y > 14 {
                if !story.flags.contains("reachedCavern") {
                    story.flags.insert("reachedCavern")
                    story.step("far", "cavern")
                    think("The great cavern. It just keeps going.", 3.2)
                }
            }
        }
        // Map: mark what Max can see around him.
        markExplored(around: p)
    }

    // MARK: camp storage

    public func campStock(_ id: String) -> [ItemStack] { world.prop(id)?.stock ?? [] }

    /// Move a pocket into a camp crate.
    public func stash(slot i: Int, in id: String) {
        guard let pi = world.propIndex(id), inv.slots.indices.contains(i), let s = inv.slots[i] else { return }
        inv.slots[i] = nil
        if let k = world.props[pi].stock.firstIndex(where: { $0.id == s.id && !s.id.bulky }) { world.props[pi].stock[k].count += s.count }
        else { world.props[pi].stock.append(s) }
        emit(.saveNow)
    }

    /// Take a stack out of a camp crate, as much as fits in the bag.
    public func takeFromCamp(_ id: String, item: ItemID) {
        guard let pi = world.propIndex(id), let k = world.props[pi].stock.firstIndex(where: { $0.id == item }) else { return }
        let have = world.props[pi].stock[k].count
        let got = inv.add(item, have)
        guard got > 0 else { think("My bag’s full.", 1.6); return }
        world.props[pi].stock[k].count -= got
        if world.props[pi].stock[k].count <= 0 { world.props[pi].stock.remove(at: k) }
        emit(.saveNow)
    }

    // MARK: map

    public static let mapBlock = 2
    public static var mapCols: Int { Landmarks.width / mapBlock }
    public static var mapRows: Int { Landmarks.height / mapBlock }

    func markExplored(around p: V2) {
        let b = Game.mapBlock
        let cx = Int(p.x) / b, cy = Int(p.y) / b
        for dy in -3...2 {
            for dx in -4...4 where dx * dx + dy * dy <= 18 {
                let x = cx + dx, y = cy + dy
                guard x >= 0, y >= 0, x < Game.mapCols, y < Game.mapRows else { continue }
                story.explored.insert(y * Game.mapCols + x)
            }
        }
    }

    // MARK: home upgrades

    /// How bright every placed lantern burns: 1 (a cell and a wick) to 5 (an iron beam lantern).
    public var lanternLevel: Int { story.counters["lanternLv", default: 1] }
    /// The light radius, in tiles, of a lantern at each level.
    public static func lanternRadius(_ lv: Int) -> Double { [9, 11, 13.5, 16, 20][Swift.max(0, Swift.min(4, lv - 1))] }

    func upgradeOpen(_ u: String) -> Bool {
        switch u {
        case "plot": return quarters.plots.count < 6
        case _ where u.hasPrefix("lantern"): return lanternLevel == (Int(u.dropFirst(7)) ?? 0) - 1
        case "barrel": return quarters.barrelCap < 200
        default: return !quarters.decor.contains(u)
        }
    }

    func applyUpgrade(_ u: String) {
        switch u {
        case "plot": quarters.plots.append(GardenPlot()); think("Another bed for the garden.", 2)
        case _ where u.hasPrefix("lantern"):
            let lv = Int(u.dropFirst(7)) ?? 1
            story.counters["lanternLv"] = lv
            think(lv >= 5 ? "An iron beam lantern. It throws light like daylight." : "Every lantern burns brighter now.", 2.6)
        case "barrel": quarters.barrelCap = 200; think("Twice the water now.", 2)
        default: quarters.decor.insert(u); think("A table. Like a real home.", 2.4)
        }
    }

    /// Where a wooden ladder would go: against the ledge Max is facing.
    func ladderSpot() -> (x: Double, top: Double)? {
        guard max.ground, max.mode == .walk, inv.count(.woodLadder) > 0 else { return nil }
        for dir in [max.face, -max.face] {
            let x = max.pos.x + Double(dir) * 0.75
            guard world.solid(x, max.pos.y - 0.5) else { continue }
            var y = max.pos.y - 0.5
            while y > max.pos.y - 6.5 {
                if !world.solid(x, y) && !world.solid(x, y - 0.6) && !world.solid(x, y - 1.2) {
                    guard let t = world.groundY(x, from: y, to: max.pos.y), max.pos.y - t > 0.9 else { break }
                    if world.solid(max.pos.x, t - 1.0) { break }
                    return (max.pos.x + Double(dir) * 0.15, t)
                }
                y -= 0.1
            }
        }
        // No ledge beside him: stand it straight up, as tall as the headroom allows (up a shaft, under a hole).
        var y = max.pos.y - 1.9
        while y > max.pos.y - 7.9 && !world.solid(max.pos.x, y - 0.1) && !world.solid(max.pos.x - 0.35, y - 0.1) && !world.solid(max.pos.x + 0.35, y - 0.1) { y -= 0.1 }
        let top = Swift.max(max.pos.y - 6, y + 1.9)
        if max.pos.y - top >= 1.2 { return (max.pos.x, top) }
        return nil
    }
}
