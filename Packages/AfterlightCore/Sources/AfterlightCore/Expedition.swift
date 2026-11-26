import Foundation

extension Quest {
    public static let farEdge = Quest(id: "far", title: "The Far Edge", side: false, steps: [
        QuestStep(id: "east", text: "Find a way east off the platform"),
        QuestStep(id: "camp", text: "Make a camp crate and pitch a camp"),
        QuestStep(id: "cavern", text: "Reach the great cavern"),
        QuestStep(id: "cell", text: "Bring a battery cell back to the platform’s signal lamp"),
    ])
    public static let homeLight = Quest(id: "homeLight", title: "A Light at Home", side: false, steps: [
        QuestStep(id: "parts", text: "Find a lamp cell and some wire"),
        QuestStep(id: "fix", text: "Fix the shelter’s light"),
    ])
    public static let lantern = Quest(id: "lantern", title: "Someone Else Down Here", side: true, steps: [
        QuestStep(id: "find", text: "Find whose lantern this is"),
    ])
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

    /// Why a camp can't go here, or nil if it can.
    func campObstruction() -> String? {
        guard max.ground, max.mode == .walk else { return "I need my feet on the ground." }
        if atHome { return "I don’t need a camp at home. Storage is right there." }
        let p = max.pos
        for dx in [-0.9, 0.0, 0.9] {
            guard let g = world.groundY(p.x + dx, from: p.y - 0.6, to: p.y + 0.6), abs(g - p.y) < 0.25 else { return "Too uneven. I need a flat spot." }
        }
        if world.solid(p.x, p.y - 2.1) || world.solid(p.x + Double(max.face) * 0.8, p.y - 1.2) { return "Too cramped. I need some headroom." }
        if world.props.contains(where: { $0.kind == .camp && $0.pos.dist(p) < 6 }) { return "There’s already a camp right here." }
        return nil
    }

    func expeditionContext() -> ContextAction? {
        let p = max.pos
        let f = story.flags
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        // Pitch a camp
        if inv.count(.campCrate) > 0 && max.ground {
            if campObstruction() == nil { return act("pitchCamp", "Pitch camp here", V2(p.x, p.y - 2.4), true) }
            if !atHome { return act("campSpot", "Camp here?", V2(p.x, p.y - 2.4)) }
        }
        for pr in world.props where abs(pr.pos.x - p.x) < 1.5 && abs(pr.pos.y - p.y) < 1.3 {
            switch pr.kind {
            case .camp: return act("camp:\(pr.id)", pr.flags.first(where: { $0.hasPrefix("name:") }).map { String($0.dropFirst(5)) } ?? "Camp crate", V2(pr.pos.x, pr.pos.y - 1.9))
            case .signalLamp:
                if !pr.flags.contains("lit") {
                    if available(.batteryCell) > 0 { return act("signal", "Fit the battery cell", V2(pr.pos.x, pr.pos.y - 3.2), true) }
                    return act("signalLook", "Signal lamp", V2(pr.pos.x, pr.pos.y - 3.2))
                }
            case .lanternClue:
                if !f.contains("sawLantern") { return act("lantern", "Look at the lantern", V2(pr.pos.x, pr.pos.y - 1.6), true) }
            default: break
            }
        }
        // The shelter's own light: the first thing that makes home feel like home.
        if let sl = world.prop("shelter.light"), !f.contains("shelterLit"), abs(p.x - sl.pos.x) < 1.4, abs(p.y - 30) < 0.5, f.contains("flashOn") {
            if available(.lampCell) > 0 && available(.wire) > 0 { return act("fixLight", "Fix the light", V2(sl.pos.x, 27.4), true) }
            return act("lookLight", "Light fixture", V2(sl.pos.x, 27.4))
        }
        // The optional first lamp, at the tunnel mouth
        if inv.count(.lamp) > 0 && f.contains("lampIdea") && abs(p.x - Landmarks.lampSpot.x) < 1.2 && abs(p.y - 30) < 0.5
            && !world.props(of: .lamp).contains(where: { $0.pos.dist(Landmarks.lampSpot) < 2.5 }) {
            return act("placeLamp", "Place lantern at the tunnel mouth", V2(p.x, p.y - 2.4), true)
        }
        return nil
    }

    func performExpedition(_ id: String) -> Bool {
        switch id {
        case "pitchCamp":
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
        case "fixLight":
            guard available(.lampCell) > 0, available(.wire) > 0 else { return true }
            consume(.lampCell, 1); consume(.wire, 1)
            story.flags.insert("shelterLit")
            story.step("homeLight", "parts"); story.step("homeLight", "fix")
            if let i = world.propIndex("shelter.light") { world.props[i].flags.insert("lit") }
            max.busy = 1.0
            think("There. Home looks like home again.", 3.4)
            emit(.flashOn); emit(.swell)
            emit(.saveNow)
        case "lookLight":
            think("The shelter light. A dead cell and a cut wire. A lamp cell and some wire would fix it.", 3.8)
            later(4) { g in if g.available(.lampCell) == 0 { g.hint("The locker by the door has lamp cells and wire.", 6) } }
        case "campSpot":
            think(campObstruction() ?? "This’ll do.", 2.4)
        case "signal":
            guard let i = world.propIndex("signal"), available(.batteryCell) > 0 else { return true }
            consume(.batteryCell, 1)
            world.props[i].flags.insert("lit")
            story.step("far", "cell")
            story.flags.insert("signalLit")
            think("It’s alive. Anyone on the line can see that now.", 3.4)
            emit(.chime); emit(.swell)
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
        if available(.lampCell) > 0 && available(.wire) > 0 { story.step("homeLight", "parts") }
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

    static let mapBlock = 2
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
}
