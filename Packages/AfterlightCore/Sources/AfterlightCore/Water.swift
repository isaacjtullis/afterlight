import Foundation

// Milestone 1: a home worth saving. Four clean cups in a leaking drum, a drip to trace and clamp,
// a failed filter stamped "Builders' Store B", Dad's unfinished map, and the first clean cup.

extension Quest {
    public static var homeWater: Quest { Quests.get("drum") }
}

extension Game {
    static let drumCap = 12.0
    /// Hydration lost per carved bite, and per minute of hauling something bulky.
    static let thirstPerBite = 0.25, thirstPerHaulMinute = 1.0
    /// The unclamped drum loses a cup every ten minutes of play.
    static let leakMinutesPerCup = 10.0

    public var drum: Prop? { world.prop("drum") }
    public var waterQuestActive: Bool { story.quests.contains { $0.id == "drum" && !$0.done } }
    var drumTraced: Bool { story.flags.contains("dripTraced") }
    var hasClampParts: Bool { available(.hoseClamp) > 0 || (available(.strap) > 0 && available(.gasket) > 0) }
    var carryingBulky: Bool { inv.slots.contains { $0?.id.bulky == true } }
    /// Working days the clean water will last at about two cups a day.
    public var cupsEstimate: String {
        let c = Int(quarters.clean.rounded(.down))
        switch c {
        case 0: return "Empty. Dad’s hand filter can still make a cup."
        case 1: return "1 clean cup. Less than a day’s work."
        default: return "\(c) clean cups. About \(c / 2 == 1 ? "one working day" : "\(c / 2) working days")."
        }
    }

    // MARK: ticking

    func waterTick(_ dt: Double) {
        guard started, cine == nil else { return }
        // The drum leaks until its fitting is clamped (only while playing).
        if !quarters.drumSealed && quarters.clean > 0 {
            quarters.clean = Swift.max(0, quarters.clean - dt / (Self.leakMinutesPerCup * 60))
        }
        // Hauling bulky salvage is thirsty work.
        if carryingBulky && abs(max.vx) > 0.5 { thirst(Self.thirstPerHaulMinute / 60 * dt) }
        // Thirst: slower recovery, then real harm while working.
        if hydration < 30 && !story.flags.contains("said.thirsty") {
            story.flags.insert("said.thirsty")
            think(quarters.clean >= 1 ? "Mouth’s dry. There’s water in the drum at home." : "Mouth’s dry, and the drum’s empty. Dad’s hand filter, then.", 3)
        }
        if hydration > 50 { story.flags.remove("said.thirsty") }
        // A new filter primes the drum while Max is home too (the clock-based refill covers time away).
        // Landmarks on Dad's sketch.
        for (id, flag, line) in [("lm.pipe", "lm.pipe", "A forked pipe. Just like Dad drew it."),
                                 ("lm.stripes", "lm.stripes", "Three white stripes. Survey marks. He was right."),
                                 ("lm.mark", "lm.mark", "A question mark, scratched in the door. Dad’s.")] {
            if let pr = world.prop(id), !story.flags.contains(flag), max.pos.dist(pr.pos) < 3.2 {
                story.flags.insert(flag)
                story.counters["lastLandmark"] = ["lm.pipe": 1, "lm.stripes": 2, "lm.mark": 3][id]
                think(story.flags.contains("gotSketch") ? line : (id == "lm.mark" ? "A question mark scratched in a door." : (id == "lm.pipe" ? "A forked pipe." : "Three white stripes on the wall.")), 3)
            }
        }
        // Finding the store, sketch or not, counts.
        let st = Landmarks.storeB
        if waterQuestActive && max.pos.x > Double(st.x0) && max.pos.x < Double(st.x1) + 1 && max.pos.y > Double(st.top) && max.pos.y <= Double(st.floor) + 0.1 {
            if !story.flags.contains("foundStore") {
                story.flags.insert("foundStore")
                story.step("drum", "stamp"); story.step("drum", "map"); story.step("drum", "store")
                think(story.flags.contains("gotSketch") ? "Builders’ Store B. Dad was right. There was another way in." : "“Builders’ Store B.” The same stamp as the old filter.", 3.6)
                emit(.saveNow)
            }
        }
        if waterQuestActive && available(.filterAssembly) > 0 && atHome { story.step("drum", "assembly") }
    }

    func thirst(_ n: Double) { hydration = Swift.max(0, hydration - n) }

    /// The player asked Max what he's thinking: point the way for a little while.
    public func askHint() { hintAskedAt = time }

    // MARK: context

    func waterContext() -> ContextAction? {
        let p = max.pos
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        if let d = drum, abs(p.x - d.pos.x) < 0.7, abs(p.y - d.pos.y) < 0.5 {
            return act("panel:drum", waterQuestActive && !drumTraced && story.flags.contains("flashOn") ? "That drip…" : "Water drum", V2(d.pos.x, d.pos.y - 2.2), waterQuestActive)
        }
        if let g = world.prop("grate"), abs(p.x - g.pos.x) < 0.45, abs(p.y - g.pos.y) < 0.5,
           story.flags.contains("mapCorner"), !story.flags.contains("gotSketch") {
            return act("grate", "Pry up the floor grate", V2(g.pos.x, g.pos.y - 1.6), true)
        }
        if story.flags.contains("sawStamp") && !story.flags.contains("mapCorner"), abs(p.x - Landmarks.bench.x) < 0.8, abs(p.y - 30) < 0.5 {
            return act("mapClip", "Dad’s map clip", V2(Landmarks.bench.x, 27.2), true)
        }
        for id in ["bunk.broken", "washstand"] {
            if let pr = world.prop(id), near(pr, 0.9), !pr.stock.isEmpty {
                return act("salvage:\(id)", id == "washstand" ? "Old washstand" : "Broken bunk", V2(pr.pos.x, pr.pos.y - 1.8), drumTraced)
            }
        }
        if let pr = world.prop("store.shelf"), near(pr, 1.0) {
            return act("search:store.shelf", pr.stock.isEmpty ? "Dry shelf" : "Store shelf", V2(pr.pos.x, pr.pos.y - 2.0), !pr.stock.isEmpty)
        }
        return nil
    }

    func performWater(_ id: String) -> Bool {
        switch id {
        case "grate":
            guard let g = world.prop("grate") else { return true }
            hammer(at: V2(g.pos.x, g.pos.y - 0.2), for: 1.2)
            later(1.3) { g in
                g.story.flags.insert("gotSketch")
                _ = g.inv.add(.sketch, 1)
                g.emit(.pickup(ItemID.sketch.name))
                g.story.step("drum", "map")
                g.think("Dad’s sketch. A forked pipe, three white stripes, a question mark. A second way in.", 4.2)
                g.later(4.4) { $0.think("The forked pipe’s past the old lift car. He drew a ladder going down.", 3.6) }
                g.emit(.saveNow)
            }
        case "mapClip":
            story.flags.insert("mapCorner")
            think("A torn corner of paper caught in Dad’s map clip. Pencil lines. The rest must have slipped…", 3.6)
            later(3.8) { $0.think("…through the floor grate.", 2.4) }
        default: return false
        }
        return true
    }

    // MARK: the drum panel

    func drumPanel() -> Panel {
        let at = drum?.pos ?? max.pos
        var lines = [cupsEstimate]
        var rows: [PanelRow] = []
        if !quarters.drumSealed {
            lines.append(drumTraced ? "The drain fitting weeps. A strap and a gasket would clamp it, or a proper hose clamp." : "Something’s dripping.")
        }
        if quarters.drumSealed && !quarters.filterFitted {
            lines.append(story.flags.contains("sawStamp") ? "The intake runs cloudy. The old filter is spent." : "The water from the intake runs cloudy.")
        }
        if quarters.filterFitted { lines.append("The new filter runs clean. About a cup every half hour.") }
        if hydration < 90 && quarters.clean >= 1 {
            rows.append(PanelRow(id: "drum.drink", label: "Drink a cup", detail: "Leaves \(Int(quarters.clean - 1)) cup\(Int(quarters.clean - 1) == 1 ? "" : "s").", style: .primary))
        }
        if quarters.clean < 1 {
            rows.append(PanelRow(id: "drum.crank", label: "Crank Dad’s hand filter", detail: "Slow, hard work for one cup of cloudy-but-safe water.", style: .primary))
        }
        if !quarters.drumSealed && story.flags.contains("flashOn") && !drumTraced {
            rows.append(PanelRow(id: "drum.trace", label: "Trace the drip", style: .primary))
        }
        if !quarters.drumSealed && drumTraced {
            let how = available(.hoseClamp) > 0 ? "Your hose clamp will do it." : "Needs a strap (\(Swift.min(1, available(.strap)))/1) and a gasket (\(Swift.min(1, available(.gasket)))/1)."
            rows.append(PanelRow(id: "drum.clamp", label: "Clamp the fitting", detail: how, enabled: hasClampParts, style: .primary))
        }
        if quarters.drumSealed && story.flags.contains("clampedNow") && !story.flags.contains("pouredBack") {
            rows.append(PanelRow(id: "drum.pour", label: "Pour your cup back in", style: .primary))
        }
        if quarters.drumSealed && !story.flags.contains("sawStamp") && waterQuestActive {
            rows.append(PanelRow(id: "drum.intake", label: "Look at the old filter", style: .primary))
        }
        if available(.waterCan) > 0 {
            rows.append(PanelRow(id: "drum.can", label: "Open the sealed can", detail: "Six clean cups into the drum."))
        }
        if available(.filterAssembly) > 0 && !quarters.filterFitted {
            rows.append(PanelRow(id: "drum.fit", label: "Fit the filter assembly", style: .primary))
        }
        if story.flags.contains("filterIn") && !story.flags.contains("primed") {
            rows.append(PanelRow(id: "drum.prime", label: "Prime the intake", detail: "Pump the handle until it draws.", style: .primary))
        }
        if story.flags.contains("primed") && !quarters.filterFitted {
            rows.append(PanelRow(id: "drum.cup", label: "Draw the first clean cup", style: .primary))
        }
        return Panel(id: "drum", title: "Water drum", lines: lines, anchor: V2(at.x, at.y - 2.2), rows: rows)
    }

    func drumAction(_ row: String) {
        guard let d = drum else { return }
        switch row {
        case "drum.drink":
            guard quarters.clean >= 1 else { return }
            quarters.clean -= 1
            hydration = Swift.min(100, hydration + 50)
            recover(stamina: 6, health: 1)
            emit(.pour(at: d.pos))
            think("Cold and clean.", 1.6)
        case "drum.crank":
            max.busy = 6
            for k in 0..<6 { later(Double(k)) { $0.emit(.clank(at: V2(d.pos.x, d.pos.y - 1))) } }
            later(6) { g in
                g.hydration = Swift.min(100, g.hydration + 35)
                g.think("One cup. Dad cranked this every night when I was small.", 3)
            }
        case "drum.trace":
            story.flags.insert("dripTraced")
            story.step("drum", "drip")
            think("There. The drain fitting at the bottom. It’s weeping, a drop at a time.", 3.6)
            later(3.8) { g in
                g.think(g.available(.hoseClamp) > 0 ? "My hose clamp would seal that." : "A strap to cinch it and a gasket to seal it. The old bunk room, past the roots.", 3.8)
            }
        case "drum.clamp":
            guard hasClampParts else { return }
            if available(.hoseClamp) > 0 { consume(.hoseClamp, 1) } else { consume(.strap, 1); consume(.gasket, 1) }
            hammer(at: V2(d.pos.x, d.pos.y - 0.3), for: 1.4)
            later(1.5) { g in
                g.quarters.drumSealed = true
                g.story.flags.insert("clampedNow")
                g.story.step("drum", "clamp")
                g.think("Holding. Not a drop.", 2.4)
                g.emit(.saveNow)
            }
        case "drum.pour":
            story.flags.insert("pouredBack")
            quarters.clean = Swift.min(Self.drumCap, quarters.clean + 1)
            emit(.pour(at: d.pos))
            think("Back where it belongs. And it stays.", 2.4)
        case "drum.intake":
            story.flags.insert("sawStamp")
            story.step("drum", "stamp")
            think("The filter’s spent. Stamped on the housing: “BUILDERS’ STORE B.”", 3.6)
            later(3.8) { $0.think("Dad talked about a second way in, after the corridor fell. He kept his map at the bench.", 4) }
        case "drum.can":
            guard available(.waterCan) > 0 else { return }
            consume(.waterCan, 1)
            quarters.clean = Swift.min(Self.drumCap, quarters.clean + 6)
            emit(.pour(at: d.pos))
            think("Six more cups. Another outing.", 2.4)
        case "drum.fit":
            guard available(.filterAssembly) > 0 else { return }
            consume(.filterAssembly, 1)
            story.step("drum", "assembly")
            hammer(at: V2(d.pos.x, d.pos.y - 0.5), for: 2)
            later(2.1) { g in g.story.flags.insert("filterIn"); g.think("Seated. Now it has to draw.", 2.4) }
        case "drum.prime":
            max.busy = 4
            for k in 0..<8 { later(Double(k) * 0.5) { $0.emit(.clank(at: V2(d.pos.x, d.pos.y - 1))) } }
            later(4) { g in g.story.flags.insert("primed"); g.think("A cough, a gurgle… it’s drawing.", 2.6) }
        case "drum.cup":
            quarters.filterFitted = true
            quarters.clean = Swift.min(Self.drumCap, quarters.clean + 1)
            hydration = 100
            story.flags.insert("firstCup")
            story.step("drum", "cup")
            emit(.pour(at: d.pos))
            emit(.chapter(1, "A Home Worth Saving"))
            think("Clear. Cold. Ours.", 3)
            later(3.4) { $0.think("Dad would have liked that.", 3) }
            emit(.saveNow)
        default: break
        }
    }

    // MARK: guidance

    /// Where the water quest's next step happens, and the last landmark seen (for a hint).
    func waterGuide() -> V2? {
        guard let q = story.quests.first(where: { $0.id == "drum" && !$0.done }), let st = q.nextStep else { return nil }
        let d = drum?.pos ?? Landmarks.drum
        switch st.id {
        case "drip": return V2(d.x, d.y - 1.5)
        case "clamp":
            if hasClampParts || !drumTraced { return V2(d.x, d.y - 1.5) }
            if available(.strap) == 0, let b = world.prop("bunk.broken") { return V2(b.pos.x, b.pos.y - 1.5) }
            if let w = world.prop("washstand") { return V2(w.pos.x, w.pos.y - 1.5) }
            return nil
        case "stamp": return V2(d.x, d.y - 1.5)
        case "map": return story.flags.contains("mapCorner") ? V2(Landmarks.grate.x, 28.5) : V2(Landmarks.bench.x, 28.5)
        case "store":
            // Along Dad's landmarks, or straight at the store if he's dug toward it.
            if !story.flags.contains("lm.pipe") { return V2(48.6, 28.5) }
            return V2(Double(Landmarks.storeB.x1) - 1, Double(Landmarks.storeB.floor) - 1.5)
        case "assembly":
            if available(.filterAssembly) > 0 { return V2(d.x, d.y - 1.5) }
            if let s = world.prop("store.shelf") { return V2(s.pos.x, s.pos.y - 1.5) }
            return nil
        case "cup": return V2(d.x, d.y - 1.5)
        default: return nil
        }
    }

    /// The hint a stuck player gets: the last landmark of Dad's they saw, and what comes next.
    public var landmarkHint: String? {
        guard waterQuestActive, story.isDone("drum", "map") || story.flags.contains("gotSketch") else { return nil }
        switch story.counters["lastLandmark"] ?? 0 {
        case 1: return "Last landmark: the forked pipe, down the ladder from the lift pit. Next on Dad’s sketch: three white stripes."
        case 2: return "Last landmark: the three white stripes on the service walk. Next: the question mark. The span is broken; planks or a dig around."
        case 3: return "The question mark is the store door. Builders’ Store B is right there."
        default: return "Dad’s sketch starts at a forked pipe. He drew a ladder going down past the old lift car."
        }
    }
}
