import Foundation

// Build 4 · Give the climb consequences and finish the game.
//
// The upper gallery sits above the hotel, between the lower homes and the surface approach. Max reaches
// it by the exit stair (a save is made at the landing). Opening it brings trade: Sela comes down from
// above with a regulator the lower pumps need, for nothing. Then a toll crew sets up at the shared crossing
// and starts taking a share of deliveries, and Max watches Wren pay. Bram, who keeps the old emergency
// station, shows on the worn map how the empty gallery could be closed off on its own. Then the choice:
//   Stay      take a shift keeping the passage open; help a traveler bring a delivery through.
//   Detonate  warn everyone out, then (only when Max commits) collapse the gallery; walk back through.
//   Outside   pack, say goodbye if he wants, open the surface door and walk out under his own control.
// The ending is written once. The pre-ending save at the landing stays available.

public struct EndingRecord: Codable, Equatable, Sendable {
    public var id: String
    public var at: Date
    public var gained: String
    public var gaveUp: String
}

/// Max's walk outside: a stretch of ground, wind that changes direction, a horizon.
public struct OutsideWalk: Codable, Equatable, Sendable {
    public var x = 0.0
    public var face = 1
    public var walking = false
    public var wind = 0.6          // −1…1: which way and how hard
    public var windTarget = 0.6
    public var nextGust = 6.0
    public var walked = 0.0
    public var t = 0.0
}

extension Landmarks {
    public static let landing = (x0: 228, x1: 251)
    public static let stationPos = V2(237.6, 12)
    public static let stationMapPos = V2(240.4, 12)
    public static let crossing = (x0: 271, x1: 275)
    public static let tollPos = V2(267.6, 12)
    public static let doorPos = V2(324.4, 12)
    public static let landingCache = V2(233.4, 12)
}

extension Quest {
    public static var gallery: Quest { Quests.get("gallery") }
}

extension WorldGen {
    static func galleryProps() -> [Prop] {
        let f = Double(Landmarks.gallery.floor)
        return [
            Prop(id: "gallery.map", kind: .thing, pos: Landmarks.stationMapPos, look: "stationMap"),
            Prop(id: "gallery.station", kind: .thing, pos: Landmarks.stationPos, look: "station"),
            Prop(id: "gallery.toll", kind: .thing, pos: Landmarks.tollPos, look: "tollpost"),
            Prop(id: "gallery.door", kind: .thing, pos: Landmarks.doorPos, look: "surfaceDoor"),
            Prop(id: "gallery.cache", kind: .thing, pos: Landmarks.landingCache, look: "regulatorCrate"),
            Prop(id: "gallery.crossing", kind: .thing, pos: V2(Double(Landmarks.crossing.x0 + Landmarks.crossing.x1) / 2 + 0.5, f), look: "crossing"),
        ]
    }

    /// The crossing: a gap in the gallery floor with old planks laid over it.
    static func buildCrossing(_ w: World) {
        let C = Landmarks.crossing, f = Landmarks.gallery.floor
        for c in C.x0...C.x1 { for r in f...(f + 6) { w.set(c, r, .air, back: .gallery) } }
        for c in C.x0...C.x1 { w.set(c, f, .plank) }
    }
}

extension Game {

    public var inGallery: Bool { max.pos.x >= Double(Landmarks.gallery.x0) && max.pos.y <= Double(Landmarks.gallery.floor) + 0.2 && max.pos.y > 3 }
    var atLanding: Bool { inGallery && max.pos.x < Double(Landmarks.landing.x1) }
    public var galleryClosed: Bool { story.flags.contains("gallery.closed") }
    public var endingChosen: String? { story.ending?.id }
    /// The text shown once an ending is reached, until the player closes it.
    public var epilogue: [String]? { story.ending != nil && !story.flags.contains("epilogue.seen") && story.flags.contains("epilogue.due") ? epilogueLines : nil }

    // MARK: per frame

    func galleryTick(_ dt: Double) {
        if inGallery && !story.flags.contains("gallery.seen") { arriveGallery() }
        guard story.flags.contains("gallery.seen") else { return }
        // The toll: after an outing since Sela came down, the crew has set up.
        if !story.flags.contains("toll.up") && story.flags.contains("sela.came") && outings > (story.counters["sela.outing"] ?? 0) { tollGoesUp() }
        if story.flags.contains("toll.up") && !story.flags.contains("toll.seen") && inGallery && abs(max.pos.x - Landmarks.tollPos.x) < 14 { watchWrenPay() }
        if story.counters["ending.phase"] != nil { endingTick(dt) }
    }

    func arriveGallery() {
        story.flags.insert("gallery.seen")
        story.step("hotel", "climb")
        story.addQuest(.gallery)
        story.step("gallery", "landing")      // the landing save: a checkpoint the player can come back to
        emit(.landingSave)
        if story.chapter < 7 { story.chapter = 7; emit(.chapter(7, "The Upper Gallery")) }
        spawn("keeper", at: V2(Landmarks.stationPos.x + 1.2, 12))
        setActor("keeper") { $0.face = 1 }
        // Wren's been waiting for the gallery to open. Two people stop at the landing.
        spawn("wren", at: V2(max.pos.x + 1.6, 12), carrying: [ItemStack(.fullCan)])
        setActor("wren") { $0.face = -1; $0.errand = "landing" }
        later(1.2) { g in g.startTalk("x.landing"); g.emit(.talk) }
        // Someone from above, with a part the lower pumps need.
        later(6) { g in
            g.spawn("upper", at: V2(Landmarks.doorPos.x - 0.8, 12), carrying: [ItemStack(.regulator)], lamp: true)
            g.send("upper", [Waypoint(Double(Landmarks.landing.x1) + 1.5, 12, tag: "selaDown")])
            g.story.flags.insert("sela.came")
            g.story.counters["sela.outing"] = g.outings
            g.think("The surface door. Somebody’s coming through it.", 3)
        }
        emit(.saveNow)
    }

    func galleryArrived(_ id: String, _ tag: String) {
        switch (id, tag) {
        case ("upper", "selaDown"):
            setActor("upper") { $0.face = -1 }
            say("upper", "You’re from below? Then this is for you. Your pumps have been running without one.", 4)
        case ("wren", "paid"):
            setActor("wren") { $0.route = [Waypoint(Landmarks.doorPos.x - 3, 12, tag: "wrenOut")] }
        case ("wren", "wrenOut"):
            setActor("wren") { $0.hidden = true }
        case ("wren", "through"):
            // The stay ending: the delivery made it through.
            if story.counters["ending.phase"] == 10 { finishEnding("stay") }
        case ("toll1", "out"), ("toll2", "out"), ("upper", "out"):
            setActor(id) { $0.hidden = true }
        default: break
        }
    }

    func tollGoesUp() {
        story.flags.insert("toll.up")
        spawn("toll1", at: V2(Landmarks.tollPos.x + 0.9, 12)); setActor("toll1") { $0.face = -1 }
        spawn("toll2", at: V2(Landmarks.tollPos.x + 2.2, 12)); setActor("toll2") { $0.face = -1 }
        if let i = world.propIndex("gallery.toll") { world.props[i].flags.insert("down") }
        story.step("gallery", "trade")
    }

    func watchWrenPay() {
        story.flags.insert("toll.seen")
        spawn("wren", at: V2(Landmarks.tollPos.x - 5, 12), carrying: [ItemStack(.fullCan, 2)])
        send("wren", [Waypoint(Landmarks.tollPos.x - 0.6, 12, wait: 3.5, tag: "paying")])
        later(2.2) { g in
            g.banter([("toll1", "Share for the crossing."),
                      ("wren", "It’s water. For people up top."),
                      ("toll2", "Then it’s worth a share."),
                      ("wren", "…Fine.")]) { g in
                g.setActor("wren") { _ = $0.takeAway(.fullCan, 1) }
                g.setActor("toll1") { $0.give(.fullCan) }
                g.send("wren", [Waypoint(Landmarks.doorPos.x - 3, 12, tag: "wrenOut")])
                g.remember("max", "sawWrenPay")
                g.story.step("gallery", "toll")
                g.later(1) { $0.think("Wren paid. A can, to cross a bridge nobody built.", 3.4) }
                g.emit(.saveNow)
            }
        }
    }

    // MARK: contexts

    func galleryContext() -> ContextAction? {
        guard story.flags.contains("gallery.seen") else { return nil }
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        if story.ending != nil && story.flags.contains("ended") { return nil }
        if story.counters["ending.phase"] == 20 {
            for a in visibleCast where a.pos.x > Double(Landmarks.landing.x1) - 1 && abs(a.pos.x - max.pos.x) < 2 && abs(a.pos.y - max.pos.y) < 1.4 && !remembers(a.id, "warnedByMax") {
                return act("warn:\(a.id)", "Warn \(Cast.name(a.id))", V2(a.pos.x, a.pos.y - 2.4), true)
            }
        }
        for pr in world.props where near(pr, 1.3) {
            switch pr.id {
            case "gallery.map": return act("panel:gallery.map", "Station map", V2(pr.pos.x, pr.pos.y - 3.2), !story.flags.contains("map.read"))
            case "gallery.station": if story.flags.contains("toll.seen") && !galleryClosed { return act("panel:gallery.station", "Emergency station", V2(pr.pos.x, pr.pos.y - 2.6), story.counters["ending.phase"] == 20) }
            case "gallery.door": if !galleryClosed { return act("panel:gallery.door", "Surface door", V2(pr.pos.x, pr.pos.y - 3.2), story.flags.contains("toll.seen")) }
            case "gallery.cache": if !pr.stock.isEmpty { return act("search:gallery.cache", "Supplies someone brought up", V2(pr.pos.x, pr.pos.y - 1.6)) }
            default: break
            }
        }
        if let s = actor("upper"), !s.hidden, s.holds(.regulator) > 0, nearActor("upper") {
            return act("sela.take", "Take the regulator", V2(s.pos.x, s.pos.y - 2.4), true)
        }
        if inv.count(.regulator) > 0 && nearMara { return act("regulator.give", "Give Mara the regulator", V2(mara.pos.x, mara.pos.y - 2.4), true) }
        return nil
    }

    func performGallery(_ id: String) -> Bool {
        switch id {
        case "sela.take":
            setActor("upper") { _ = $0.takeAway(.regulator) }
            if inv.add(.regulator, 1) < 1 { storage.add(.regulator, 1) }
            remember("upper", "gaveRegulator")
            say("upper", "No charge. Somebody did the same for us once.", 3.4)
            send("upper", [Waypoint(Landmarks.doorPos.x - 0.6, 12, tag: "out")])
            story.step("gallery", "trade")
            emit(.saveNow)
        case "regulator.give":
            consume(.regulator, 1)
            remember("mara", "gotRegulator")
            addTrust("mara", 2)
            story.flags.insert("regulator.in")
            say("mara", "From above? Somebody up there knows pumps. …Huh.", 3.4)
            emit(.saveNow)
        default:
            if id.hasPrefix("warn:") { warn(String(id.dropFirst(5))); return true }
            return false
        }
        return true
    }

    // MARK: panels: the map, the station, the door

    func galleryPanel(_ id: String) -> Panel? {
        let at = world.prop(id)?.pos ?? max.pos
        switch id {
        case "gallery.map":
            story.flags.insert("map.read")
            story.step("gallery", "map")
            return Panel(id: id, title: "Station map", lines: [
                "A worn enamel map. The gallery is a band across the top, marked in red: EMERGENCY CLOSURE · SECTION G.",
                "Below it, separately: the hotel, transit, the outposts, the homes. Their own section, their own air.",
                galleryClosed ? "The red band is all that’s left of the gallery now." : "Close section G, and the gallery comes down. Nothing below it does.",
            ], anchor: V2(at.x, at.y - 3.2), rows: [PanelRow(id: "map.ok", label: "Okay", style: .info)])
        case "gallery.station":
            return Panel(id: id, title: "Emergency station", lines: stationLines(), anchor: V2(at.x, at.y - 2.6), rows: stationRows())
        case "gallery.door":
            var rows = [PanelRow(id: "door.pack", label: inv.count(.trailMeal) > 0 || inv.count(.fullCan) > 0 ? "Packed" : "Pack a meal and water first",
                                 detail: "Whatever’s in your bag goes with you.", enabled: false, style: .info)]
            if story.flags.contains("toll.seen") {
                rows.append(PanelRow(id: "door.open", label: "Take hold of the door", detail: "Open it and walk out. You don’t come back down.", confirm: "Open the surface door and go outside?", style: .primary))
            } else {
                rows.append(PanelRow(id: "door.wait", label: "Not yet", detail: "There’s more to see down here first.", enabled: false, style: .info))
            }
            return Panel(id: id, title: "Surface door", lines: ["Steel, cold, a wheel to turn. Light comes under it, grey and thin.",
                                                              "Whatever’s out there, it isn’t a story anymore."], anchor: V2(at.x, at.y - 3.2), rows: rows)
        default: return nil
        }
    }

    func stationLines() -> [String] {
        let p = story.counters["ending.phase"] ?? 0
        if p == 20 {
            let left = galleryPeople
            return left.isEmpty
                ? ["The gallery is empty. The red lever is armed.", "What it does: section G collapses. The hotel and everything below stand. The toll crew loses its way in. So does everyone else: trade, visitors, the only known way up."]
                : ["Still in the gallery: \(left.map(Cast.name).joined(separator: ", ")).", "Warn them first. Nothing closes with people inside."]
        }
        return ["Bram keeps this. A lever under glass, a map, a logbook nobody wrote in for years.",
                "Close the gallery: the toll stops, and so does the trade, and the only known way to the surface."]
    }

    func stationRows() -> [PanelRow] {
        let p = story.counters["ending.phase"] ?? 0
        var rows: [PanelRow] = []
        if p == 0 {
            rows.append(PanelRow(id: "end.stay", label: "Stay: take a shift on the passage", detail: "Keep the gallery open for residents. Help a traveler bring a delivery through. The toll stays.", style: .primary))
            rows.append(PanelRow(id: "end.close", label: "Close the gallery", detail: "Warn everyone out, then decide at the lever. You can still walk away until you pull it."))
        }
        if p == 20 {
            rows.append(PanelRow(id: "end.commit", label: "Pull the lever", detail: "The gallery comes down. This can’t be undone.", enabled: galleryPeople.isEmpty,
                                 confirm: "Collapse the upper gallery? The toll and the trade both end here.", style: .primary))
            rows.append(PanelRow(id: "end.walk", label: "Walk away", detail: "Leave it armed and open. Nothing happens."))
        }
        return rows
    }

    /// Anyone besides Max still standing in the part of the gallery that would come down.
    var galleryPeople: [String] {
        story.cast.values.filter { !$0.hidden && $0.pos.y <= 12.2 && $0.pos.y > 3 && $0.pos.x >= Double(Landmarks.landing.x1) }.map(\.id).sorted()
    }

    func galleryRow(_ panel: String, _ row: String) -> Bool {
        switch row {
        case "map.ok": return true
        case "end.stay": beginStay()
        case "end.close": beginClose()
        case "end.walk":
            story.counters["ending.phase"] = nil
            think("Not today.", 2)
        case "end.commit": commitClosure()
        case "door.open": openTheDoor()
        default: return false
        }
        emit(.saveNow)
        return true
    }

    func galleryCan(_ what: String) -> Bool {
        switch what {
        case "toll.seen": return story.flags.contains("toll.seen")
        case "friend.load": return ["mara", "odi", "ellis", "wren"].contains { trust($0) >= 2 }
        default: return false
        }
    }

    func galleryDo(_ what: String) {
        switch what {
        case "landing.mountain": remember("wren", "maxWantsMountain"); story.flags.insert("wants.mountain")
        case "landing.roof": remember("wren", "maxWantsRoof"); story.flags.insert("wants.roof")
        case "friend.load":
            // Someone he's worked with brings a load up for the climb.
            if let i = world.propIndex("gallery.cache") { world.props[i].stock = [ItemStack(.trailMeal, 2), ItemStack(.fullCan)] }
            remember("max", "askedForLoad")
        default: break
        }
    }

    // MARK: endings

    func beginStay() {
        story.counters["ending.phase"] = 10
        // A shift on the passage: walk Wren and her delivery through, past the toll.
        spawn("wren", at: V2(Double(Landmarks.landing.x1) - 1, 12), carrying: [ItemStack(.fullCan, 2), ItemStack(.growTray)])
        setActor("wren") { $0.face = 1; $0.speed = 1.2 }
        say("wren", "Walk with me? It goes easier with two.", 3)
        story.flags.insert("stay.walk")
    }

    func beginClose() {
        story.counters["ending.phase"] = 20
        story.flags.insert("close.started")
        // Warning travelers: they leave when Max tells them.
        think("Nobody can be in there. I have to tell them.", 3)
    }

    func warn(_ id: String) {
        guard story.counters["ending.phase"] == 20 else { return }
        remember(id, "warnedByMax")
        let out = id == "toll1" || id == "toll2" || id == "upper"
        send(id, [Waypoint(out ? Landmarks.doorPos.x - 0.4 : Double(Landmarks.landing.x0) + 2, 12, tag: out ? "out" : "safe")])
        say(id, out ? "Your gallery, your funeral. We’ll go round." : "Okay. Okay, I’m going.", 3)
    }

    func commitClosure() {
        guard story.counters["ending.phase"] == 20, galleryPeople.isEmpty else { return }
        story.counters["ending.phase"] = 21
        if let i = world.propIndex("gallery.station") { world.props[i].flags.formUnion(["armed", "fired"]) }
        cine = Cinematic(kind: "collapse")
        emit(.swell)
    }

    func collapseGallery() {
        let G = Landmarks.gallery
        for c in (Landmarks.landing.x1 + 1)...G.x1 { for r in 2...(G.floor + 7) where !world.isFrame(c, r) && r <= G.floor + 6 { world.set(c, r, .rock) } }
        world.rebuildDensity()
        world.markAllDirty()
        world.props.removeAll { ["gallery.toll", "gallery.door", "gallery.crossing"].contains($0.id) }
        world.props.append(Prop(id: "gallery.rubble", kind: .thing, pos: V2(Double(Landmarks.landing.x1) + 2.5, 12), look: "rubble"))
        story.flags.insert("gallery.closed")
        for (id, a) in story.cast where a.pos.x > Double(Landmarks.landing.x1) && a.pos.y <= 12.2 { story.cast[id]?.hidden = true }
        if let i = world.propIndex("gallery.map") { world.props[i].flags.insert("closed") }
    }

    func galleryCineTick(_ dt: Double, kind: String) -> Int {
        guard var c = cine, kind == "collapse" else { cine = nil; return 0 }
        c.t += dt
        let t = c.t
        c.focus = V2(285, 9); c.focusWeight = smoothstepD(0.2, 1.4, t) * (1 - smoothstepD(6.0, 7.2, t))
        if Int(t * 6) != Int((t - dt) * 6) && t < 5 { emit(.clank(at: V2(260 + t * 12, 8))) }
        if t > 2.2 && c.beat == 0 { c.beat = 1; collapseGallery() }
        cine = c
        if t > 7.6 {
            cine = nil
            story.counters["ending.phase"] = 22
            think("Dust. Then quiet. The landing’s still here.", 3.4)
            // A short return through the changed landing: walk back to the stair.
        }
        return 0
    }

    func openTheDoor() {
        guard !galleryClosed, story.flags.contains("toll.seen") else { return }
        if let i = world.propIndex("gallery.door") { world.props[i].flags.insert("open") }
        for id in ["mara", "odi", "ellis", "wren"] where remembers(id, "met") || (id == "mara" && maraMet) || (id == "odi" && odi.met) {
            if trust(id) >= 2 { remember(id, "saidGoodbye") }
        }
        emit(.swell)
        story.counters["ending.phase"] = 30
        later(1.4) { g in
            g.outside = OutsideWalk()
            g.story.flags.insert("outside")
            g.emit(.saveNow)
        }
    }

    func endingTick(_ dt: Double) {
        let p = story.counters["ending.phase"] ?? 0
        if p == 10, let w = actor("wren"), w.route.isEmpty {
            // Wren walks with Max: she goes when he's near and stops when he lags.
            if abs(w.pos.x - max.pos.x) < 3 && abs(w.pos.y - max.pos.y) < 1.4 {
                send("wren", [Waypoint(Swift.min(w.pos.x + 2, Landmarks.tollPos.x + 8), 12, tag: w.pos.x + 2 >= Landmarks.tollPos.x + 8 ? "through" : nil)])
                if abs(w.pos.x - Landmarks.tollPos.x) < 3 && !story.flags.contains("stay.toll") {
                    story.flags.insert("stay.toll")
                    banter([("toll1", "Share."), ("max", "She lives down there. I’m on shift. We’ll talk about your share."), ("toll2", "…Go on, then. This once.")])
                }
            }
        }
        if p == 22 && max.pos.x < Double(Landmarks.galleryWell.x1) + 1 && max.pos.y > 13 { finishEnding("detonate") }
    }

    func outsideTick(_ dt: Double, input: GameInput) {
        guard var o = outside else { return }
        o.t += dt
        o.walking = input.dx != 0
        if input.dx != 0 {
            o.face = input.dx
            let against = Double(input.dx) * o.wind < 0
            let v = (input.run ? 3.2 : 2.0) * (against ? 1 - 0.35 * abs(o.wind) : 1)
            o.x += Double(input.dx) * v * dt
            o.walked += v * dt
        }
        o.nextGust -= dt
        if o.nextGust <= 0 { o.windTarget = (o.windTarget > 0 ? -1 : 1) * Double.random(in: 0.3...1); o.nextGust = Double.random(in: 6...11) }
        o.wind += (o.windTarget - o.wind) * Swift.min(1, dt * 0.6)
        outside = o
        if o.walked > 40 && story.ending == nil { finishEnding("outside") }
    }

    /// Writes the ending exactly once, and queues the epilogue.
    func finishEnding(_ id: String) {
        guard story.ending == nil else { return }
        let (gained, gave) = endingStakes(id)
        story.ending = EndingRecord(id: id, at: clock(), gained: gained, gaveUp: gave)
        story.flags.formUnion(["ended", "epilogue.due"])
        story.step("gallery", "choice")
        emit(.ending(id))
        emit(.saveNow)
    }

    func endingStakes(_ id: String) -> (String, String) {
        let friends = ["mara", "odi", "ellis", "wren"].filter { trust($0) >= 2 }.map(Cast.name)
        switch id {
        case "stay":
            return (friends.isEmpty ? "A first commitment: a shift on the passage, and the people who use it." : "People to work with: \(friends.joined(separator: ", ")).",
                    "The surface, for now. And the toll is still there.")
        case "detonate":
            return ("No toll. The homes below are theirs again.", "Trade, visitors, and the only known way up.")
        default:
            return ("The surface: ground, wind, a horizon.", friends.isEmpty ? "The shelter, and the water he got running." : "\(friends.joined(separator: ", ")), and the water he got running.")
        }
    }

    var epilogueLines: [String] {
        guard let e = story.ending else { return [] }
        var lines: [String]
        switch e.id {
        case "stay":
            lines = ["Max takes the early shift on the passage. Wren brings the cans through; the toll crew grumbles and lets residents by.",
                     story.flags.contains("regulator.in") ? "Mara’s pump runs smoother with the regulator from above." : "Mara keeps her pump going the old way.",
                     "The gallery stays open, and so does the trouble it brings."]
        case "detonate":
            lines = ["Section G came down. The hotel stands; the homes below stand; the toll crew’s way in is gone.",
                     "So is the trade. Wren carries for the lower levels now, and nobody comes down from above.",
                     "Some nights Max goes up to the landing and looks at the rubble."]
        default:
            lines = ["The wind changes its mind every few minutes. The ground goes on past where the light stops.",
                     "Whether a person could live out here, Max doesn’t know yet.",
                     "Below, the others keep making their own choices."]
        }
        return lines + ["You gained: " + e.gained, "You gave up: " + e.gaveUp]
    }

    public func closeEpilogue() { story.flags.insert("epilogue.seen"); emit(.saveNow) }

    var galleryLights: [(pos: V2, radius: Double)] {
        guard max.pos.x > 220 && max.pos.y < 30 else { return [] }
        var out: [(V2, Double)] = [(V2(238, 9), 6)]
        if !galleryClosed {
            out += [(V2(258, 9), 6), (V2(282, 9), 6), (V2(306, 9), 6)]
            if world.prop("gallery.door")?.flags.contains("open") == true { out.append((V2(324.5, 7), 12)) }
            out.append((V2(324.5, 3), 5))
        }
        return out
    }
}
