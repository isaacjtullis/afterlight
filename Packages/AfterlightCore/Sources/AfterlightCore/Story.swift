import Foundation

/// A moment worth a card: a step done, a quest finished, a new quest.
public struct Checkpoint: Equatable, Sendable {
    public enum Kind: Sendable { case step, questDone, newQuest }
    public var kind: Kind
    public var title: String
    public var text: String
    public var next: String? = nil
    public var side = false
}

public struct QuestStep: Codable, Equatable, Sendable {
    public var id: String
    public var text: String
    public var done = false
}

public struct Quest: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var side: Bool
    public var steps: [QuestStep]
    public var done = false
    public var outcome: String? = nil

    public var nextStep: QuestStep? { steps.first { !$0.done } }

    public static let blackout = Quest(id: "blackout", title: "The Blackout", side: false, steps: [
        QuestStep(id: "dig", text: "Cut into the dirt wall"),
        QuestStep(id: "crystal", text: "Dig out what’s glinting"),
        QuestStep(id: "repair", text: "Repair the flashlight at the workbench"),
        QuestStep(id: "light", text: "Switch it on"),
    ])
    public static let firstAscent = Quest(id: "ascent", title: "First Ascent", side: false, steps: [
        QuestStep(id: "tooth", text: "Find something hard enough for a pick"),
        QuestStep(id: "pick", text: "Make a short pick"),
        QuestStep(id: "ladder", text: "Build a ladder section"),
        QuestStep(id: "place", text: "Place the ladder in the shaft"),
        QuestStep(id: "seam", text: "Climb and open the seam overhead"),
        QuestStep(id: "maint", text: "See what’s above"),
    ])
    public static let placeToReturn = Quest(id: "home", title: "A Place to Come Back To", side: false, steps: [
        QuestStep(id: "pipe", text: "Follow the warm pipe east"),
        QuestStep(id: "meet", text: "Find who’s knocking"),
        QuestStep(id: "pump", text: "Get the old pump running"),
        QuestStep(id: "water", text: "Decide where the water goes"),
        QuestStep(id: "light", text: "Light the passage between home and the outpost"),
    ])
    public static let seedTin = Quest(id: "seeds", title: "The Last Seed Tin", side: true, steps: [
        QuestStep(id: "decide", text: "Plant them, give them to a grower, or split them"),
        QuestStep(id: "harvest", text: "Grow something"),
    ])
    public static let lights = Quest(id: "lights", title: "A Light Every Twenty Feet", side: true, steps: [
        QuestStep(id: "make", text: "Make lamps at the workbench"),
        QuestStep(id: "place", text: "Place lamps along the warm-pipe passage"),
        QuestStep(id: "used", text: "See if anyone uses it"),
    ])
    public static let power = Quest(id: "power", title: "A Little Power", side: true, steps: [
        QuestStep(id: "cell", text: "Find a battery cell"),
        QuestStep(id: "bank", text: "Wake the battery bank"),
    ])
}

public struct Story: Codable, Sendable {
    public var chapter = 1
    public var flags: Set<String> = []
    public var quests: [Quest] = []
    public var counters: [String: Int] = [:]
    /// Map blocks Max has seen.
    public var explored: Set<Int> = []
    public var waterTo: String? = nil      // where the home pump sends its water: "home" for now
    /// Shared jobs, agreements, ownership and water routing with other survivors.
    public var coop = Coop()
    /// Steps finished since the app last showed them (not saved).
    public var checkpoints: [Checkpoint] = []

    public init() {}

    enum CodingKeys: String, CodingKey { case chapter, flags, quests, counters, explored, waterTo, coop }
    /// Every field is optional on the way in, so saves from older builds always load.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        chapter = try c.decodeIfPresent(Int.self, forKey: .chapter) ?? 1
        flags = try c.decodeIfPresent(Set<String>.self, forKey: .flags) ?? []
        quests = try c.decodeIfPresent([Quest].self, forKey: .quests) ?? []
        counters = try c.decodeIfPresent([String: Int].self, forKey: .counters) ?? [:]
        explored = try c.decodeIfPresent(Set<Int>.self, forKey: .explored) ?? []
        waterTo = try c.decodeIfPresent(String.self, forKey: .waterTo)
        coop = try c.decodeIfPresent(Coop.self, forKey: .coop) ?? Coop()
    }

    public mutating func addQuest(_ q: Quest) {
        if !quests.contains(where: { $0.id == q.id }) {
            quests.append(q)
            checkpoints.append(Checkpoint(kind: .newQuest, title: q.title, text: q.steps.first?.text ?? "", side: q.side))
        }
    }
    public mutating func step(_ quest: String, _ step: String) {
        guard let qi = quests.firstIndex(where: { $0.id == quest }),
              let si = quests[qi].steps.firstIndex(where: { $0.id == step }) else { return }
        guard !quests[qi].steps[si].done else { return }
        quests[qi].steps[si].done = true
        let q = quests[qi]
        if q.steps.allSatisfy(\.done) {
            quests[qi].done = true
            checkpoints.append(Checkpoint(kind: .questDone, title: q.title, text: q.steps[si].text, side: q.side))
        } else {
            checkpoints.append(Checkpoint(kind: .step, title: q.title, text: q.steps[si].text, next: q.nextStep?.text, side: q.side))
        }
    }
    public func isDone(_ quest: String, _ step: String) -> Bool {
        quests.first { $0.id == quest }?.steps.first { $0.id == step }?.done ?? false
    }
    /// The one clue to show in the journal pill.
    public var nextClue: String? {
        quests.first { !$0.side && !$0.done }?.nextStep?.text ?? quests.first { !$0.done }?.nextStep?.text
    }
    func once(_ key: String) -> Bool { !flags.contains("said." + key) }
}

public struct NPCState: Codable, Sendable {
    public var id: String
    public var pos: V2
    public var face = -1
    public var met = false
    public var trust = 0
    public var walking = false
    public var routeT = 0.0
    public var vx = 0.0
}

public struct ConvoChoice: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String
}

public struct Conversation: Identifiable, Equatable, Sendable {
    public var id: String
    public var speaker: String
    public var lines: [String]
    public var choices: [ConvoChoice]
}

extension Game {

    // MARK: hooks from play

    /// The first time anything goes in the bag, say how the bag works.
    func explainBag() {
        guard !story.flags.contains("said.bag") else { return }
        story.flags.insert("said.bag")
        later(1.2) { $0.hint("Into the bag. It holds \(Inventory.capacity) things, and small parts stack up to 6. Tap the bag to look inside.", 7) }
    }

    func onPickup(_ id: ItemID) {
        explainBag()
        switch id {
        case .chargeCrystal:
            story.step("blackout", "crystal")
            think(story.flags.contains("inspected") ? "That’ll bridge the cell." : "A charge crystal. That could wake the flashlight.", 3.4)
            later(1.5) { g in if !g.inv.has(.flashlight) { g.hint("Carry it back to the workbench", 6) } }
        default: break
        }
    }

    func onCrafted(_ id: String) {
        switch id {
        case "flashlight":
            story.step("blackout", "repair")
            think("Cell’s bridged. Let’s see.", 2.6)
        case "pick":
            story.step("ascent", "pick")
            think("Short, mean, and it bites upward.", 2.6)
        case "ladder":
            story.step("ascent", "ladder")
            hint("Place it at the bottom of the shaft", 5)
        case "lamp":
            story.step("lights", "make")
        case "meal":
            think("Something to keep me going.", 2)
        default: break
        }
    }

    func onCarved(_ res: CarveResult) {
        // Roots come away as wood; a plank comes back as its wood.
        let roots = res.cleared.filter { $0.was == .root }.count
        let planks = res.cleared.filter { $0.was == .plank }.count
        let wood = roots * Inventory.woodPerRootTile + planks * Inventory.plankCost
        if wood > 0 {
            let got = inv.addWood(wood)
            if got > 0 { emit(.wood(got)) }
            if got < wood { if time - clankAt > 4 { clankAt = time; think("Can’t lash any more wood to the bag.", 2.4) } }
            if roots > 0 && !story.flags.contains("said.wood") {
                story.flags.insert("said.wood")
                later(0.6) { $0.hint("Wood straps to the outside of your bag, up to \(Inventory.woodCap). A plank costs \(Inventory.plankCost).", 7) }
            }
        }
        if !story.isDone("blackout", "dig") && res.changed { story.step("blackout", "dig"); clearHint() }
        // The hatch seam: once it's open, the rungs continue up into the room.
        if !story.flags.contains("hatchOpen") {
            // The bottom three rows are what the climber can reach. Once most of the plug is gone,
            // the rest crumbles and the way into the room is open.
            var solid = 0
            for r in (Landmarks.hatchRows.lowerBound + 1)...Landmarks.hatchRows.upperBound { for c in 25...26 where world.m(c, r).solid { solid += 1 } }
            if solid <= 2 {
                for y in [9.6, 10.6, 11.6, 12.4] { _ = world.carve(center: V2(26, y), radius: 1.1, tool: .pick) }
                for r in Landmarks.hatchRows { for c in 25...26 where world.m(c, r).solid { world.set(c, r, .dug, back: .shaft) } }
                story.flags.insert("hatchOpen")
                if let i = world.climbs.firstIndex(where: { $0.id == Landmarks.shaftRungsID }) { world.climbs[i].top = 9.0 }
                story.step("ascent", "seam")
                think("Light up there. A room.", 2.6)
                emit(.saveNow)
            }
        }
    }

    func afterTryUp() {
        guard !story.flags.contains("triedUp") else { return }
        story.flags.insert("triedUp")
        think("Swinging up just brings the ceiling down on me.", 3)
        later(3.2) { $0.think("The rungs start too high, and that plug’s packed hard. I need a pick, and something to climb.", 4.5) }
        later(7.8) { g in g.finishChapter1() }
    }

    func finishChapter1() {
        guard story.chapter == 1 else { return }
        story.step("blackout", "light")
        story.chapter = 2
        story.flags.formUnion(["needPick", "needLadder", "ordersOK"])
        story.addQuest(.firstAscent)
        emit(.chapter(2, "First Ascent"))
        later(8.2) { g in
            if g.inv.count(.liftTooth) == 0 { g.think("The old lift car came down just east of here, past where the crystal was. Its drive teeth are hard steel.", 4.5) }
        }
        later(13) { $0.hint("Follow the arrow. Dig east from the workshop.", 6) }
        emit(.saveNow)
    }

    // MARK: beats

    func storyTick(_ dt: Double) {
        guard started else { return }
        expeditionTick(dt)
        let p = max.pos
        let f = story.flags
        func once(_ k: String, _ body: () -> Void) {
            if !story.flags.contains("said." + k) { story.flags.insert("said." + k); body() }
        }

        // Chapter 1
        if !f.contains("moved") && time > 3.2 && time < 40 { hint("Push the wheel left or right to walk. Past the ring to run.", 3) }
        if nearBench && time > 2 { once("bench") { later(0.4) { g in if !g.story.flags.contains("inspected") { g.think("The flashlight. Dead since the power went.", 3) } } } }
        if f.contains("moved") && !f.contains("dug") && p.x > 29.3 && max.face > 0 && planning == nil { hint("Hold DIG against the dirt wall", 3) }
        if abs(p.x - Landmarks.crystal.x) < 4.3 && p.y < 31 && !(world.buried.first { $0.id == "crystal" }?.revealed ?? true) {
            once("glint") {
                think("…a glint. Something’s down there.", 3)
                later(1.2) { $0.hint("Dig toward the glint, then stand over it and press DOWN", 7) }
            }
        }

        // Chapter 2
        if f.contains("broke") && p.x > Double(Landmarks.caveStart) + 1 {
            once("cave") {
                think("It’s enormous. And there’s light down here.", 3.4)
                later(3.6) { $0.hint("Walk downhill and Max picks up speed. Let go to glide.", 6) }
            }
        }
        for pr in world.props where [.liftCar, .drillRig, .gantry].contains(pr.kind) && abs(pr.pos.x - p.x) < 5 {
            story.flags.insert("seen.\(pr.id)")
        }
        if let car = world.prop("liftcar"), abs(p.x - car.pos.x) < 4, abs(p.y - car.pos.y) < 3 {
            once("car") {
                think("A lift car. It fell all the way down here.", 3)
                if f.contains("needPick") { later(3.2) { $0.think("The drive teeth are hard steel. That’s my pick.", 3.4) } }
            }
        }
        if max.stamina < 15 && !f.contains("said.tired") {
            story.flags.insert("said.tired")
            think("Out of breath.", 1.8)
            later(2) { $0.hint("Stand still a moment to catch your breath.", 4) }
        }
        if max.stamina > 60 { story.flags.remove("said.tired") }
        // In a hole with no way to walk out: point at ▲.
        if max.mode == .walk && max.ground && !max.swingOn && Int(time * 2) % 4 == 0 && time - (story.counters["climbHintAt"].map(Double.init) ?? -99) > 14,
           (footholdTop(max.face) != nil || footholdTop(-max.face) != nil), wallBeside(max.face) || wallBeside(-max.face),
           world.solid(max.pos.x - 0.9, max.pos.y - 0.5) && world.solid(max.pos.x + 0.9, max.pos.y - 0.5) {
            story.counters["climbHintAt"] = Int(time)
            hint("Push the wheel up against the wall to cut footholds and climb out.", 4)
        }
        // The root door: say what roots are good for the first time Max stands at them.
        if abs(p.x - Double(Landmarks.hollow.door) - 1.2) < 1.2 && abs(p.y - 30) < 0.6 && world.m(Landmarks.hollow.door, 28) == .root {
            once("roots") {
                think("Roots grew right through the door. That’s a lot of wood.", 3.2)
                later(3.4) { $0.hint("Hold DIG to hack at the roots. Each root is about 100 wood.", 6) }
            }
        }
        if f.contains("needPick") && inv.count(.liftTooth) + storage.count(.liftTooth) > 0 && !inv.has(.shortPick) {
            once("tooth") { story.step("ascent", "tooth"); think("A lift tooth. Hard steel. With a grip, that’s a pick.", 3.4) }
        }
        if story.chapter == 2 && p.y < 9.3 && p.x > 17 && p.x < 35 && max.mode == .walk { finishChapter2() }

        // Chapter 3
        if story.chapter >= 3 {
            if let pipe = world.prop("pipe"), abs(p.x - pipe.pos.x) < 4, p.y < 9.5 {
                once("pipe") { think("This pipe’s warm. Someone’s heating water somewhere.", 3.2); later(3.4) { $0.hint("Follow the warm pipe east.", 6) } }
            }
            if let pump = world.prop("pump"), abs(p.x - pump.pos.x) < 2, p.y < 9.5, !f.contains("pumpFixed") {
                once("pump") { story.flags.insert("sawPump"); think("A hand pump. The gauge is smashed. Needs a pressure gauge.", 3.4) }
            }
            if let bank = world.prop("battery"), abs(p.x - bank.pos.x) < 2, p.y < 9.5, !f.contains("power") {
                once("bank") { story.addQuest(.power); think("A battery bank. Dead. One good cell could wake it.", 3.2) }
            }
            if inv.count(.batteryCell) > 0 { story.step("power", "cell") }
            checkPassageLit()
            maraBeats()
        }
    }

    func finishChapter2() {
        guard story.chapter == 2 else { return }
        story.step("ascent", "maint")
        story.chapter = 3
        story.flags.formUnion(["ch2Done", "lampIdea"])
        story.addQuest(.dryTaps)
        story.addQuest(.lights)
        emit(.chapter(3, "Dry Taps"))
        emit(.saveNow)
    }

    func checkPassageLit() {
        guard !story.flags.contains("passageLit") else { return }
        let lamps = world.props(of: .lamp).filter { $0.pos.y > 8 && $0.pos.y < 10.5 && $0.pos.x > 33 && $0.pos.x < 75 }.map(\.pos.x).sorted()
        guard !lamps.isEmpty else { return }
        var xs = [Landmarks.passage.x0 - 1]
        xs.append(contentsOf: lamps)
        xs.append(Landmarks.passage.x1)
        var ok = true
        for i in 1..<xs.count where xs[i] - xs[i - 1] > 11 { ok = false }
        if ok && world.m(Int(Landmarks.passage.x1) - 1, 8) == .dug {
            story.flags.insert("passageLit")
            story.step("lights", "place")
            story.step("home", "light")
            think("A light every few steps, all the way to the outpost.", 3)
            emit(.saveNow)
        }
    }

    // MARK: Odi

    /// Odi now belongs to a later chapter; until then she isn't in the world.
    func odiTick(_ dt: Double) {
        guard story.chapter >= 5 else { return }
        let homeX = 81.0, visitX = 34.0
        if story.flags.contains("passageLit") && odi.met {
            // She uses the lit passage: walks to the maintenance room, lingers, walks home.
            odi.routeT += dt
            let cycle = odi.routeT.truncatingRemainder(dividingBy: 140)
            let target = cycle < 70 ? visitX : homeX
            let dx = target - odi.pos.x
            if abs(dx) > 0.2 {
                odi.vx = (dx > 0 ? 1 : -1) * 1.6
                odi.face = dx > 0 ? 1 : -1
                odi.pos.x += odi.vx * dt
                odi.walking = true
            } else { odi.walking = false; odi.vx = 0 }
            if abs(odi.pos.x - max.pos.x) < 3 && abs(odi.pos.y - max.pos.y) < 1.5 {
                if !story.isDone("lights", "used") {
                    story.step("lights", "used")
                    emit(.conversation("odi.lamps"))
                }
            }
        } else {
            odi.walking = false
            odi.face = max.pos.x < odi.pos.x ? -1 : 1
        }
    }

    public var nearOdi: Bool { story.chapter >= 5 && abs(odi.pos.x - max.pos.x) < 1.8 && abs(odi.pos.y - max.pos.y) < 1.2 }

    // MARK: conversations

    public func conversation(_ id: String) -> Conversation? {
        let ok = ConvoChoice(id: "ok", label: "Okay.")
        switch id {
        case "odi.meet":
            return Conversation(id: id, speaker: "Odi", lines: [
                "You came along the warm line? Nobody’s used that pipe in years.",
                "I’m Odi. I grow what I can out here. Our seep went dry last winter."
            ], choices: [ConvoChoice(id: "up", label: "I’m trying to get to the surface."), ConvoChoice(id: "help", label: "Do you need anything?")])
        case "odi.up":
            return Conversation(id: id, speaker: "Odi", lines: [
                "Up? Then you’ll want Tamsin. She kept the lifts before they stopped.",
                "Get that old pump in your maintenance room running and share a little water. I’ll send word to her."
            ], choices: [ConvoChoice(id: "ok", label: "I’ll see what I can do.")])
        case "odi.help":
            return Conversation(id: id, speaker: "Odi", lines: [
                "Water. There’s an old hand pump on this line, in your maintenance room.",
                "If it ever runs again, a share would keep my beds alive."
            ], choices: [ConvoChoice(id: "ok", label: "I’ll look at it.")])
        case "odi.seeds":
            return Conversation(id: id, speaker: "Odi", lines: [
                "Is that a seed tin? Old stock. Old seeds wake better with someone who knows them.",
                "I keep a seed library. What do you want to do with it?"
            ], choices: [ConvoChoice(id: "give", label: "Take them. Grow more."),
                         ConvoChoice(id: "split", label: "Half for you, half for me."),
                         ConvoChoice(id: "keep", label: "I’ll plant them myself.")])
        case "odi.water":
            return Conversation(id: id, speaker: "Odi", lines: [
                "I felt the line shudder. The pump’s running?",
                "There’s only so much. Where does it go?"
            ], choices: [ConvoChoice(id: "share", label: "Half to you, half home."),
                         ConvoChoice(id: "all", label: "Run it all to your beds."),
                         ConvoChoice(id: "keep", label: "I need it at home for now.")])
        case "odi.amend":
            return Conversation(id: id, speaker: "Odi", lines: ["Still keeping all of it?"],
                                choices: [ConvoChoice(id: "share", label: "No. Half is yours."), ConvoChoice(id: "keep", label: "For now.")])
        case "odi.lamps":
            return Conversation(id: id, speaker: "Odi", lines: ["I walked your lamps last night. Felt like a street again."], choices: [ok])
        case "odi.chat":
            var lines = ["The line’s warm because I keep a kettle on it. Old habit."]
            if odi.trust >= 3 { lines = ["Tamsin’s at the old transit level, past the flooded stretch. She’ll want to see you."] }
            if story.counters["giftDue"] == 1 { lines = ["Your seeds took. Here, starts for your beds, and some greens."] }
            return Conversation(id: id, speaker: "Odi", lines: lines, choices: [ok])
        default:
            return nil
        }
    }

    public func choose(_ convo: String, _ choice: String) {
        switch (convo, choice) {
        case ("odi.meet", let c):
            odi.met = true
            story.step("home", "meet")
            story.addQuest(.seedTin)
            emit(.conversation(c == "up" ? "odi.up" : "odi.help"))
        case ("odi.up", _), ("odi.help", _):
            if inv.count(.seedTin) + storage.count(.seedTin) > 0 && !story.flags.contains("seedsDecided") { emit(.conversation("odi.seeds")) }
            emit(.saveNow)
        case ("odi.seeds", let c):
            story.flags.insert("seedsDecided")
            story.step("seeds", "decide")
            consume(.seedTin, 1)
            switch c {
            case "give":
                odi.trust += 2; story.counters["giftDue"] = 1
                setOutcome("seeds", "Gave the tin to Odi.")
            case "split":
                odi.trust += 1; story.counters["seeds", default: 0] += 3
                setOutcome("seeds", "Split the seeds with Odi.")
            default:
                story.counters["seeds", default: 0] += 6
                setOutcome("seeds", "Kept the seeds.")
            }
            emit(.saveNow)
        case ("odi.water", let c), ("odi.amend", let c):
            switch c {
            case "share": story.waterTo = "share"; odi.trust += 2
            case "all": story.waterTo = "odi"; odi.trust += 3
            default: story.waterTo = "home"; odi.trust -= 1
            }
            story.step("home", "water")
            if c != "keep" { story.flags.insert("tamsinWord") }
            emit(.saveNow)
        case ("odi.chat", _):
            if story.counters["giftDue"] == 1 {
                story.counters["giftDue"] = 2
                story.counters["seeds", default: 0] += 8
                let added = inv.add(.greens, 2)
                if added < 2 { storage.add(.greens, 2 - added) }
            }
        default: break
        }
    }

    // MARK: context actions

    func near(_ prop: Prop, _ r: Double = 1.6) -> Bool { abs(prop.pos.x - max.pos.x) < r && abs(prop.pos.y - max.pos.y) < 1.3 }

    func computeContext() -> ContextAction? {
        guard started, cine == nil, planning == nil, order == nil, max.busy <= 0, max.oneShot == nil, max.mode == .walk else { return nil }
        let p = max.pos
        let f = story.flags
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }

        if max.stamina < 25 && inv.count(.trailMeal) > 0 { return act("eat", "Eat a trail meal", V2(p.x, p.y - 2.4), true) }
        if let c = maraContext() { return c }
        if let c = expeditionContext() { return c }
        if let s = plankSpot() { return act("plank", "Lay plank · \(Inventory.plankCost) wood", V2(Double(s.c) + 0.5, Double(s.r) - 0.9), true) }
        if nearOdi { return act("talk", odi.met ? "Talk to Odi" : "Say hello", V2(odi.pos.x, odi.pos.y - 2.4), !odi.met) }
        if underShaft && f.contains("sawShaft") && !f.contains("triedUp") { return act("tryUp", "Dig up", V2(p.x, p.y - 2.4)) }
        if underShaft && available(.ladderSection) > 0 && !world.climbs.contains(where: { $0.id == "ladder.shaft" }) {
            return act("placeLadder", "Place ladder", V2(26, 27.5), true)
        }
        if nearBench {
            let at = V2(Landmarks.bench.x, 28.2)
            if !inv.has(.flashlight) && available(.chargeCrystal) > 0 { return act("repair", "Repair flashlight", at, true) }
            if !f.contains("inspected") && !inv.has(.flashlight) { return act("inspect", "Look at flashlight", at) }
            if inv.has(.flashlight) && !f.contains("flashOn") { return act("switchOn", "Switch on", at, true) }
            // Always reachable once the flashlight works, whether or not Max looked at it first.
            if let r = knownRecipes.first(where: { canCraft($0) }) { return act("bench", "Make \(r.name.lowercased())", at, true) }
            if inv.has(.flashlight) || f.contains("inspected") { return act("bench", "Workbench", at) }
        }
        if abs(p.y - 30) < 0.5 && p.x > 32 && p.x < 47 {
            if let bed = world.props(of: .planter).first(where: { near($0, 1.2) }) {
                if bed.planted == nil && seedsAvailable > 0 { return act("plant", "Plant seeds", V2(bed.pos.x, bed.pos.y - 1.8), true) }
                if bed.planted != nil && cropReady(bed) { return act("harvest", "Harvest", V2(bed.pos.x, bed.pos.y - 1.8), true) }
            } else if seedsAvailable > 0 && world.props(of: .planter).count < 3 {
                return act("prepBed", "Prepare a bed", V2(p.x, p.y - 2.4))
            }
        }
        if let pile = world.props.first(where: { $0.kind == .pile && near($0, 1.1) }), let s = pile.stock.first {
            return act("search:\(pile.id)", pile.stock.count > 1 ? "Pick up" : "Pick up \(s.id.name.lowercased())", V2(pile.pos.x, pile.pos.y - 1.4))
        }
        if let pp = world.prop("pantry"), near(pp, 0.9) { return act("pantry", "Pantry", V2(pp.pos.x, pp.pos.y - 2.0), max.hunger < 60) }
        for pr in world.props where near(pr) {
            switch pr.kind {
            case .locker where !pr.stock.isEmpty: return act("search:\(pr.id)", "Search locker", V2(pr.pos.x, pr.pos.y - 2.2))
            case .buckledLocker: return act("buckled", "Buckled shut", V2(pr.pos.x, pr.pos.y - 2.2))
            case .liftCar, .drillRig, .gantry: if !pr.stock.isEmpty { return act("salvage:\(pr.id)", "Salvage", V2(pr.pos.x, pr.pos.y - 2.4), pr.kind == .liftCar) }
            case .crate: if !pr.stock.isEmpty { return act("search:\(pr.id)", "Open crate", V2(pr.pos.x, pr.pos.y - 1.8), true) }
            case .pile: if let s = pr.stock.first { return act("search:\(pr.id)", pr.stock.count > 1 ? "Pick up" : "Pick up \(s.id.name.lowercased())", V2(pr.pos.x, pr.pos.y - 1.4)) }
            case .pantry: return act("pantry", "Pantry", V2(pr.pos.x, pr.pos.y - 2.0), max.hunger < 60)
            case .sunkValve: if !pr.stock.isEmpty { return act("salvage:\(pr.id)", "Take the valve", V2(pr.pos.x, pr.pos.y - 1.8), true) }
            case .storage: return act("storage", "Storage", V2(pr.pos.x, pr.pos.y - 2.0))
            case .pump:
                if !f.contains("pumpFixed") && available(.pressureGauge) > 0 && available(.fasteners) >= 2 { return act("fixPump", "Repair pump", V2(pr.pos.x, pr.pos.y - 2.2), true) }
                if f.contains("pumpFixed") && story.waterTo == "home" && odi.met { return act("amend", "Pump", V2(pr.pos.x, pr.pos.y - 2.2)) }
            case .batteryBank:
                if !f.contains("power") && available(.batteryCell) > 0 && available(.wire) > 0 { return act("power", "Wake the battery bank", V2(pr.pos.x, pr.pos.y - 2.2), true) }
            case .bed: return act("rest", "Rest", V2(pr.pos.x, pr.pos.y - 2.0))
            default: break
            }
        }
        if inv.count(.waterTank) > 0 && p.x > 20 && p.x < 31.5 && abs(p.y - 30) < 0.5 && world.props(of: .waterTank).isEmpty {
            return act("placeTank", "Place water tank", V2(p.x, p.y - 2.4), true)
        }
        return nil
    }

    public var seedsAvailable: Int { story.counters["seeds", default: 0] + (story.flags.contains("seedsDecided") ? 0 : available(.seedTin) * 6) }

    public func performContext() {
        guard let a = context else { return }
        context = nil
        let p = max.pos
        if performExpedition(a.id) { return }
        switch a.id {
        case "inspect":
            story.flags.formUnion(["inspected", "sawFlashlight"])
            think(inv.count(.chargeCrystal) > 0 ? "" : "Flashlight’s dead. The charge cell cracked. A crystal could bridge it.", 4.2)
            if !story.flags.contains("dug") { later(4.4) { g in if !g.story.flags.contains("dug") { g.hint("Walk to the dirt wall and hold DIG", 6) } } }
        case "repair":
            story.flags.insert("sawFlashlight")
            max.face = Landmarks.bench.x > p.x ? 1 : -1
            max.busy = 1.6
            for i in 0..<6 { later(Double(i) * 0.22) { $0.emit(.spark(at: V2(26.4, 29.0))) } }
            later(1.6) { $0.craft("flashlight") }
        case "switchOn":
            story.flags.insert("flashOn"); story.flags.remove("lightOff")
            // The first look up the shaft plays once.
            if !story.flags.contains("sawShaft") { cine = Cinematic(kind: "flash") }
            emit(.flashOn)
            clearHint()
        case "bench": emit(.openSheet(.workbench))
        case "storage": emit(.openSheet(.storage))
        case "tryUp": startOneShot(.tryUp, at: nil)
        case "placeLadder":
            consume(.ladderSection, 1)
            world.climbs.append(Climb(id: "ladder.shaft", x: 26.0, top: 25.2, bottom: 30.0, kind: .ladder))
            story.step("ascent", "place")
            emit(.placed("ladder"))
            hint("Push the wheel up to climb", 5)
            emit(.saveNow)
        case "eat":
            inv.remove(.trailMeal, 1)
            recover(stamina: 55, health: 10)
            think("Better.", 1.5)
        case "talk":
            if !odi.met { emit(.conversation("odi.meet")) }
            else if story.flags.contains("pumpFixed") && story.waterTo == nil { emit(.conversation("odi.water")) }
            else if available(.seedTin) > 0 && !story.flags.contains("seedsDecided") { emit(.conversation("odi.seeds")) }
            else { emit(.conversation("odi.chat")) }
        case "fixPump":
            consume(.pressureGauge, 1); consume(.fasteners, 2)
            story.flags.insert("pumpFixed")
            story.step("home", "pump")
            max.busy = 1.4
            for i in 0..<5 { later(Double(i) * 0.25) { $0.emit(.spark(at: V2(31, 8))) } }
            later(1.5) { g in
                g.think("It catches. Water.", 2.4)
                if g.story.waterTo == nil { g.story.waterTo = "home"; g.later(2.6) { $0.hint("The home pump fills your tank.", 4) } }
            }
            emit(.saveNow)
        case "amend": emit(.conversation("odi.amend"))
        case "clearIntake": clearIntake()
        case "power":
            consume(.batteryCell, 1); consume(.wire, 1)
            story.flags.insert("power")
            story.step("power", "bank")
            emit(.flashOn); emit(.swell)
            if let i = world.propIndex("battery") { world.props[i].flags.insert("lit") }
            if !story.flags.contains("shelterLit") {
                lightHome()
                think("The bank hums. Lights here… and down below, home lights up too.", 3.8)
            } else {
                think("The bank hums awake. Light up here now, and more power for home.", 3.4)
            }
            emit(.saveNow)
        case "placeTank":
            inv.remove(.waterTank, 1)
            world.props.append(Prop(id: "tank", kind: .waterTank, pos: V2(p.x, p.y)))
            emit(.placed("tank"))
            emit(.saveNow)
        case "placeLamp":
            placing = nil
            inv.remove(.lamp, 1)
            world.props.append(Prop(id: "lamp.\(Int(time * 1000))", kind: .lamp, pos: V2(p.x, p.y)))
            emit(.placed("lamp"))
            emit(.saveNow)
        case "prepBed":
            world.props.append(Prop(id: "bed.\(Int(time * 1000))", kind: .planter, pos: V2(p.x, p.y)))
            max.busy = 0.8
            emit(.bite(at: V2(p.x, p.y), kind: .down, carved: true, face: max.face))
            emit(.saveNow)
        case "plant":
            if !story.flags.contains("seedsDecided") && available(.seedTin) > 0 {
                consume(.seedTin, 1); story.flags.insert("seedsDecided"); story.counters["seeds", default: 0] += 6
                story.step("seeds", "decide")
                setOutcome("seeds", "Planted them at home.")
            }
            story.counters["seeds", default: 0] -= 2
            if let i = world.props.firstIndex(where: { $0.kind == .planter && near($0, 1.2) }) { world.props[i].planted = clock() }
            think(cropConditions == "" ? "In they go." : "In they go. " + cropConditions, 3)
            emit(.saveNow)
        case "harvest":
            if let i = world.props.firstIndex(where: { $0.kind == .planter && near($0, 1.2) }) {
                world.props[i].planted = nil
                let added = inv.add(.greens, 3)
                if added < 3 { storage.add(.greens, 3 - added) }
                story.flags.insert("harvested")
                story.step("seeds", "harvest")
                emit(.chime)
                think("Greens. Grown here.", 2.4)
                emit(.saveNow)
            }
        case "rest":
            recover(stamina: 100, health: 50)
            emit(.sleep)
            later(3.8) { $0.emit(.openSheet(.mission)) }
        case "pantry":
            emit(.openSheet(.pantry))
        case "plank":
            guard let s = plankSpot() else { break }
            inv.wood -= Inventory.plankCost
            world.setPlank(s.c, s.r)
            emit(.placed("plank"))
            if !story.flags.contains("said.plank") { story.flags.insert("said.plank"); think("Good and solid. I can bridge a gap or cover a hole this way.", 3) }
            emit(.saveNow)
        case "buckled":
            think("Buckled shut. A pry bar would open it.", 2.6)
        default:
            if a.id.hasPrefix("panel:") {
                emit(.panel(String(a.id.dropFirst("panel:".count))))
            } else if a.id.hasPrefix("search:") || a.id.hasPrefix("salvage:") {
                let id = String(a.id.split(separator: ":")[1])
                if lootUI {
                    // Show what's here and let the player pick.
                    openLoot = id
                    if let pr = world.prop(id) { emit(.bite(at: V2(pr.pos.x, pr.pos.y - 1), kind: .side, carved: false, face: max.face)) }
                    emit(.openSheet(.loot))
                } else {
                    takeFrom(propID: id)
                }
            }
        }
    }

    /// Take one stack (or everything, when `only` is nil) from a locker, crate, wreck or pile.
    public func takeFrom(propID: String, only: ItemID? = nil) {
        guard let i = world.propIndex(propID) else { return }
        var left: [ItemStack] = []
        var got: [String] = []
        for s in world.props[i].stock {
            if let only, s.id != only { left.append(s); continue }
            let n = inv.add(s.id, s.count)
            if n > 0 { got.append(n > 1 ? "\(s.id.name) ×\(n)" : s.id.name) }
            if n < s.count { left.append(ItemStack(s.id, s.count - n)) }
        }
        world.props[i].stock = left
        clearEmptyPiles()
        if !got.isEmpty { emit(.chime); emit(.pickup(got.joined(separator: ", "))); explainBag() }
        if !left.isEmpty && (only == nil || got.isEmpty) {
            think(got.isEmpty ? "No room in the bag." : "My bag’s full. I’ll leave the rest here and come back.", 3)
            later(3.2) { $0.hint("Put things away in workshop storage to make room.", 5) }
        }
        if got.contains(where: { $0.hasPrefix(ItemID.seedTin.name) }) { think("A seed tin. Some of these might still wake up.", 3) }
        emit(.saveNow)
    }

    func setOutcome(_ q: String, _ text: String) {
        if let i = story.quests.firstIndex(where: { $0.id == q }) { story.quests[i].outcome = text }
    }

    // MARK: crops

    public var cropConditions: String {
        let water = homeWater && !world.props(of: .waterTank).isEmpty
        if !water { return "They’ll need water from a pump and a tank at home." }
        return ""
    }

    func cropMinutes(_ bed: Prop) -> Double? {
        let water = homeWater && !world.props(of: .waterTank).isEmpty
        guard water else { return nil }
        let lit = story.flags.contains("power") || world.props(of: .lamp).contains { $0.pos.dist(bed.pos) < 4.5 }
        guard lit else { return nil }
        var mins = story.flags.contains("power") ? 12.0 : 20.0
        if story.waterTo == "share" { mins *= 1.5 }
        return mins
    }

    public func cropProgress(_ bed: Prop) -> Double {
        guard let t = bed.planted, let mins = cropMinutes(bed) else { return 0 }
        return clampD(clock().timeIntervalSince(t) / (mins * 60), 0, 1)
    }
    func cropReady(_ bed: Prop) -> Bool { cropProgress(bed) >= 1 }
}

extension Game {
    /// An open tile in front of Max's feet that a plank would bridge or cover.
    func plankSpot() -> (c: Int, r: Int)? {
        guard max.ground, max.mode == .walk, !max.swingOn, inv.wood >= Inventory.plankCost else { return nil }
        let r = Int(max.pos.y.rounded())
        guard abs(max.pos.y - Double(r)) < 0.48 else { return nil }
        let c = Int((max.pos.x + Double(max.face) * (Tuning.halfWidth + 0.55)).rounded(.down))
        guard !world.m(c, r).solid, !world.m(c, r - 1).solid, !world.m(c, r - 2).solid else { return nil }
        let under = world.m(c - max.face, r)
        guard under.solid, !under.hard || under == .metal else { return nil }
        return (c, r)
    }
}
