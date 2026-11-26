import Foundation

// Build 2 · Meet Mara and let someone use the route.
// Mara makes her own deliveries. A traveler, Wren, uses the route Max opened (the lift, or his rope
// up the chimney) and walks somewhere real: Odi's grow room across the cavern. The signal lamp on
// the transit platform gets an answer from there.

extension Landmarks {
    /// Odi's grow room on the far floor of the cavern.
    public static let odiRoom = (x0: 146, x1: 156, top: 35, floor: 41)
    public static let odiLamp = V2(147.3, 41)
    public static let odiHome = V2(151.2, 41)
    /// Where Mara leaves full cans for travelers on the transit platform.
    public static let transitDrop = V2(90.5, 3)
    /// The next water when Mara's own tap is dry: a seep on the warm-pipe line.
    public static let seep = V2(52.5, 9)
    public static let chimneyTop = V2(71.0, 3)
}

extension Quest {
    public static var answered: Quest { Quests.get("answer") }
}

extension Game {

    // MARK: state

    public var signalLit: Bool { story.flags.contains("signalLit") }
    public var odiBedsLit: Int { world.props.filter { $0.id.hasPrefix("odi.bed") && $0.flags.contains("lit") }.count }
    var inOdiRoom: Bool {
        let r = Landmarks.odiRoom
        return max.pos.x > Double(r.x0) && max.pos.x < Double(r.x1) + 1 && max.pos.y > Double(r.top) && max.pos.y <= Double(r.floor) + 0.2
    }
    /// The answering lamp is blinking right now (during the answer, or when Max flashes again).
    public var odiLampBlink: Bool {
        guard let c = cine, c.kind == "answer" else { return world.prop("odi.signal")?.flags.contains("lit") ?? false }
        let t = c.t - 2.4
        return t > 0 && t < 3.2 && Int(t / 0.4) % 2 == 0
    }
    /// The lift cage: 0 at the outpost, 1 up at transit. Animated when someone else rides it.
    public var liftCar: Double { story.counters["liftCar"].map { Double($0) / 100 } ?? 0 }

    // MARK: the per-frame campaign

    func campaignTick(_ dt: Double) {
        castTick(dt)
        maraHaulTick(dt)
        wrenTick(dt)
        answerTick()
        odiRoomTick(dt)
        hotelTick(dt)
        galleryTick(dt)
    }

    // MARK: Mara's deliveries

    /// Mara's own schedule: every few minutes she takes cans somewhere. With water and a way up, full cans
    /// go to the transit drop for travelers. Dry, she carries empties to the seep on the warm line and back.
    func maraHaulTick(_ dt: Double) {
        guard story.chapter >= 3, maraMet, talk?.graph != "mara" else { return }
        if story.maraRoute.isEmpty {
            // Not while she's working on a job for Max, or before her first-visit beats settle.
            guard activeJobID(for: "mara") == nil else { return }
            let next = Double(story.counters["haul.next"] ?? 0)
            if next == 0 { story.counters["haul.next"] = Int(time) + 150; return }
            guard time >= next, !nearMara else { return }
            startMaraHaul()
            return
        }
        // Walk the route.
        let wp = story.maraRoute[0]
        if story.counters["haul.wait"].map({ Double($0) / 10 > 0 }) == true {
            let w = Double(story.counters["haul.wait"]!) / 10 - dt
            story.counters["haul.wait"] = Swift.max(0, Int(w * 10))
            mara.walking = false
            return
        }
        if wp.jump {
            mara.pos = V2(wp.x, wp.y)
        } else {
            let dx = wp.x - mara.pos.x, dy = wp.y - mara.pos.y
            if abs(dx) > 0.12 {
                mara.face = dx > 0 ? 1 : -1
                mara.pos.x += mara.face == 1 ? Swift.min(dx, 1.45 * dt) : Swift.max(dx, -1.45 * dt)
                mara.walking = true
                return
            } else if abs(dy) > 0.05 {
                mara.pos.y += dy > 0 ? Swift.min(dy, 1.6 * dt) : Swift.max(dy, -1.6 * dt)
                mara.walking = true
                return
            }
        }
        mara.pos = V2(wp.x, wp.y)
        mara.walking = false
        story.maraRoute.removeFirst()
        if wp.wait > 0 { story.counters["haul.wait"] = Int(wp.wait * 10) }
        if let tag = wp.tag { maraArrived(tag) }
    }

    public var maraHauling: Bool { !story.maraRoute.isEmpty }
    public var maraCans: Int { story.counters["mara.cans"] ?? 0 }
    public var maraCansFull: Bool { story.flags.contains("mara.cansFull") }
    /// Which way she's going on her delivery: "transit", "seep" or "beds".
    public var maraHaulKind: String { story.flags.contains("haul.transit") ? "transit" : story.flags.contains("haul.seep") ? "seep" : "beds" }

    func startMaraHaul() {
        let y = 9.0
        let tap = Game.maraTapSpot
        story.flags.subtract(["haul.transit", "haul.seep", "haul.beds"])
        story.counters["mara.cans"] = 2
        let runs = waterOn && story.coop.water.outpostTapFlow > 0
        let liftUp = liftRepaired, rope = world.climbs.contains { $0.id == "rope.chimney" }
        var r: [Waypoint] = []
        if runs && (liftUp || rope) {
            story.flags.insert("haul.transit")
            story.flags.remove("mara.cansFull")
            r.append(Waypoint(tap.x, y, wait: 3, tag: "fill"))
            if liftUp {
                r += [Waypoint(Landmarks.liftX, y, tag: "liftGo"), Waypoint(Landmarks.liftX, 3, jump: true, wait: 1.2, tag: "liftTop")]
            } else {
                r += [Waypoint(Double(Landmarks.chimney) + 1, y), Waypoint(Double(Landmarks.chimney) + 1, 3, wait: 0.6)]
            }
            r.append(Waypoint(Landmarks.transitDrop.x, 3, wait: 2.5, tag: "drop"))
            if liftUp {
                r += [Waypoint(Landmarks.liftX, 3), Waypoint(Landmarks.liftX, y, jump: true, wait: 1, tag: "liftDown")]
            } else {
                r += [Waypoint(Double(Landmarks.chimney) + 1, 3), Waypoint(Double(Landmarks.chimney) + 1, y)]
            }
            r.append(Waypoint(Landmarks.maraHome.x, y, tag: "home"))
        } else if runs {
            story.flags.insert("haul.beds")
            story.flags.remove("mara.cansFull")
            r = [Waypoint(tap.x, y, wait: 3, tag: "fill"), Waypoint(Game.maraBeds.x, y, wait: 3, tag: "water.beds"), Waypoint(Landmarks.maraHome.x, y, tag: "home")]
        } else {
            // Dry: empties west to the seep on the warm line, then back.
            story.flags.insert("haul.seep")
            story.flags.remove("mara.cansFull")
            r = [Waypoint(Double(Landmarks.outpost.door) + 0.6, y), Waypoint(Landmarks.seep.x, y, wait: 7, tag: "fill"),
                 Waypoint(Double(Landmarks.outpost.door) + 0.6, y), Waypoint(Game.maraBeds.x, y, wait: 2.5, tag: "water.beds"), Waypoint(Landmarks.maraHome.x, y, tag: "home")]
        }
        story.maraRoute = r
        story.counters["haul.trips", default: 0] += 1
    }

    func maraArrived(_ tag: String) {
        switch tag {
        case "fill":
            story.flags.insert("mara.cansFull")
        case "liftGo":
            story.counters["liftCar"] = 100
        case "liftDown":
            story.counters["liftCar"] = 0
        case "drop":
            let n = maraCans
            if n > 0, let i = world.propIndex("mara.drop") { world.props[i].stock = mergeStock(world.props[i].stock, ItemStack(.fullCan, n)) }
            story.counters["mara.cans"] = 0
            story.flags.insert("mara.dropped")
            if abs(max.pos.y - 3) < 1.5 && abs(max.pos.x - Landmarks.transitDrop.x) < 9 { say("mara", "Two for whoever comes through thirsty.", 3) }
        case "water.beds":
            story.counters["mara.cans"] = 0
        case "home":
            story.flags.subtract(["mara.cansFull", "haul.transit", "haul.seep", "haul.beds"])
            story.counters["mara.cans"] = 0
            story.counters["haul.next"] = Int(time) + 240
        default: break
        }
    }

    func mergeStock(_ s: [ItemStack], _ add: ItemStack) -> [ItemStack] {
        var s = s
        if let i = s.firstIndex(where: { $0.id == add.id }) { s[i].count = Swift.min(6, s[i].count + add.count) } else { s.append(add) }
        return s
    }

    /// Max takes one of Mara's cans for the walk. She remembers that.
    func carryMarasCan() {
        guard maraHauling, maraCans > 0, inv.room(for: .fullCan) > 0 else { return }
        story.counters["mara.cans"] = maraCans - 1
        inv.add(.fullCan, 1)
        if !maraCansFull { story.flags.insert("max.canIsEmpty") }
        remember("mara", "carriedCan")
        addTrust("mara", 1)
        say("mara", maraCansFull ? "Share of the haul’s yours when we get there." : "It’s empty now. It won’t be on the way back.", 3.4)
        emit(.saveNow)
    }

    /// Setting the carried can down where it's going: the drop, her beds, or back in her hands.
    func setCanDown() {
        guard inv.count(.fullCan) > 0 else { return }
        inv.remove(.fullCan, 1)
        let wasEmpty = story.flags.contains("max.canIsEmpty")
        story.flags.remove("max.canIsEmpty")
        if abs(max.pos.y - 3) < 1.5 && abs(max.pos.x - Landmarks.transitDrop.x) < 2.5, let i = world.propIndex("mara.drop") {
            world.props[i].stock = mergeStock(world.props[i].stock, ItemStack(.fullCan, 1))
        } else if maraHauling {
            story.counters["mara.cans"] = maraCans + 1
        }
        if !wasEmpty {
            hydration = 100
            quarters.clean = Swift.min(Game.drumCap, quarters.clean + 1)
            say("mara", "Your share. Drink it, and there’s a cup for your drum.", 3.4)
        } else {
            say("mara", "Thanks. Saved me a trip.", 2.6)
        }
        emit(.pour(at: max.pos))
        emit(.saveNow)
    }

    // MARK: Wren uses the route

    func wrenTick(_ dt: Double) {
        guard story.chapter >= 4 else { return }
        let f = story.flags
        let p = max.pos
        if f.contains("wren.seen") { return }
        // The lift moves without him: once he's ridden it up, the cage drops away and comes back with someone.
        if liftRepaired && f.contains("rodeLift") && !f.contains("wren.lift") && p.y < 4 && abs(p.x - Landmarks.liftX) < 9 && abs(p.x - Landmarks.liftX) > 2.2 && max.mode == .walk {
            story.flags.insert("wren.lift")
            emit(.clank(at: V2(Landmarks.liftX, 3)))
            think("The cage. It’s going down. I didn’t touch it.", 3)
            story.counters["liftCar"] = 0
            later(5.5) { g in
                g.story.counters["liftCar"] = 100
                g.emit(.clank(at: V2(Landmarks.liftX, 3)))
                g.spawn("wren", at: V2(Landmarks.liftX, 3), carrying: [ItemStack(.growTray), ItemStack(.fullCan)], lamp: true)
                g.wrenGoesToOdi()
                g.later(0.8) { $0.say("wren", "Oh! You’re the one who got this running. Mara said. Mind the gap.", 4) }
            }
            return
        }
        // The chimney: the lift's still broken, and someone is climbing his rope up behind him.
        if !liftRepaired && f.contains("chimneyRigged") && !f.contains("wren.chimney") && p.y < 4 && abs(p.x - Landmarks.chimneyTop.x) < 8 && abs(p.x - Landmarks.chimneyTop.x) > 2.5 && max.mode == .walk && story.counters["chimney.away"] != nil {
            story.flags.insert("wren.chimney")
            spawn("wren", at: V2(Landmarks.chimneyTop.x, 8.6), carrying: [ItemStack(.growTray)], lamp: true)
            send("wren", [Waypoint(Landmarks.chimneyTop.x, 3.0, wait: 0.6, tag: "chimneyTop")])
            setActor("wren") { $0.speed = 0.9 }
            for k in 0..<6 { later(Double(k) * 0.7) { $0.emit(.climbStep) } }
            think("Someone’s on my rope. A lamp, coming up the chimney.", 3.4)
            return
        }
        if p.y < 4 && abs(p.x - Landmarks.chimneyTop.x) > 4 { story.counters["chimney.away"] = 1 }
    }

    func wrenGoesToOdi() {
        let r = Landmarks.odiRoom
        send("wren", [
            Waypoint(Landmarks.liftX + 1.5, 3, wait: 2.2),
            Waypoint(104.2, 3), Waypoint(105.0, 3), Waypoint(105.0, 30.0),
            Waypoint(108.5, 30.0), Waypoint(126.5, 40.0), Waypoint(Double(r.x0) - 1, 41),
            Waypoint(Landmarks.odiHome.x - 1.4, 41, tag: "atOdi"),
        ])
        story.flags.insert("wren.seen")
        remember("max", "sawWren")
        story.step("answer", "traveler")
    }

    func errandArrived(_ id: String, _ tag: String) {
        switch (id, tag) {
        case ("wren", "chimneyTop"):
            setActor("wren") { $0.speed = 1.6 }
            say("wren", "Didn’t mean to scare you. That your rope? Saved me the long way round.", 4)
            remember("wren", "metAtChimney")
            wrenGoesToOdi()
        case ("wren", "atOdi"):
            // The trays are for Odi's beds.
            setActor("wren") { a in a.takeAway(.growTray); a.lamp = false }
            if let i = world.propIndex("odi.shelf") { world.props[i].stock = mergeStock(world.props[i].stock, ItemStack(.growTray, 1)) }
            story.flags.insert("wren.atOdi")
        default:
            hotelArrived(id, tag)
        }
    }

    // MARK: the signal answered

    func answerTick() {
        guard signalLit, !story.flags.contains("answered"), cine == nil, max.mode == .walk else { return }
        // Right after it's lit, or the next time Max is on the platform near it (older saves).
        if abs(max.pos.y - 3) < 1.2 && abs(max.pos.x - Landmarks.signalLampX) < 6 && max.busy <= 0 { startAnswer() }
    }

    func startAnswer() {
        guard cine == nil else { return }
        max.vx = 0
        cine = Cinematic(kind: "answer")
        emit(.swell)
    }

    /// Camera to the far side of the cavern, three blinks back, camera home.
    func answerCineTick(_ dt: Double) -> Int {
        guard var c = cine else { return 0 }
        c.t += dt
        let t = c.t
        let k = smoothstepD(0.6, 2.2, t) * (1 - smoothstepD(6.2, 7.6, t))
        c.focus = V2(Landmarks.odiLamp.x, Landmarks.odiLamp.y - 2); c.focusWeight = k
        if t > 2.4 && c.beat == 0 { c.beat = 1; emit(.chime) }
        if t > 3.6 && c.beat == 1 { c.beat = 2; think("Someone answered.", 2.6) }
        if t > 6.4 && c.beat == 2 { c.beat = 3; think("Way out across the cavern. Past the drill rig.", 3) }
        cine = c
        if t > 8 {
            cine = nil
            if !story.flags.contains("answered") {
                story.flags.insert("answered")
                story.addQuest(.answered)
                story.step("answer", "seen")
                emit(.saveNow)
            }
        }
        return 0
    }

    // MARK: Odi's grow room

    func odiRoomTick(_ dt: Double) {
        guard story.chapter >= 4 else { return }
        if inOdiRoom {
            story.step("answer", "reach")
            if story.chapter == 4 {
                story.chapter = 5
                emit(.chapter(5, "The Grow Room"))
                story.flags.insert("odiRoomSeen")
                if !story.flags.contains("answered") { story.flags.insert("answered"); story.addQuest(.answered); story.step("answer", "seen"); story.step("answer", "reach") }
                emit(.saveNow)
            }
        }
        // Odi tends her beds: bed to bed, a pause at each.
        if story.chapter >= 5 {
            if odi.pos.x < Double(Landmarks.odiRoom.x0) || odi.pos.y < 30 {
                if !story.flags.contains("odi.out") { odi.pos = Landmarks.odiHome }
            }
            guard !story.flags.contains("odi.out"), talk?.graph != "odi" else { odi.walking = false; return }
            let beds = [148.4, 150.6, 152.8, 155.0]
            let slot = Int(time / 9) % (beds.count + 1)
            let target = slot < beds.count ? beds[slot] : Landmarks.odiHome.x
            let dx = target - odi.pos.x
            if abs(dx) > 0.15 && !nearOdiNow {
                odi.face = dx > 0 ? 1 : -1
                odi.pos.x += odi.face == 1 ? Swift.min(dx, 1.2 * dt) : Swift.max(dx, -1.2 * dt)
                odi.walking = true
            } else {
                odi.walking = false
                if nearOdiNow { odi.face = max.pos.x < odi.pos.x ? -1 : 1 }
            }
            odi.pos.y = Double(Landmarks.odiRoom.floor)
            // What grew: lit beds come up after a while (a rest or an outing).
            if let at = story.counters["odi.choiceAt"], Int(time) - at > 300 {
                for i in world.props.indices where world.props[i].id.hasPrefix("odi.bed") && world.props[i].flags.contains("lit") {
                    world.props[i].flags.insert("grown")
                }
            }
        }
    }

    var nearOdiNow: Bool { abs(odi.pos.x - max.pos.x) < 1.8 && abs(odi.pos.y - max.pos.y) < 1.3 }

    /// Lighting the beds, Odi's way or Max's.
    func odiChoice(_ c: String) {
        guard !story.flags.contains("odi.chose") else { return }
        story.flags.insert("odi.chose")
        story.counters["odi.choiceAt"] = Int(time)
        switch c {
        case "lend":
            guard inv.count(.lamp) > 0 || storage.count(.lamp) > 0 || world.props.contains(where: { $0.kind == .lamp }) else { return }
            if inv.count(.lamp) > 0 { inv.remove(.lamp, 1) } else if storage.count(.lamp) > 0 { storage.remove(.lamp, 1) } else if let i = world.props.firstIndex(where: { $0.kind == .lamp }) { world.props.remove(at: i) }
            lightBeds(2)
            story.flags.insert("odi.lent")
            remember("odi", "lentLamp")
            addTrust("odi", 2)
            setOutcome("answer", "Lent Odi a lamp. Two beds lit.")
        case "cable":
            for c in Game.cableCost { consume(c.id, c.count) }
            lightBeds(4)
            story.flags.insert("odi.cabled")
            remember("odi", "ranCable")
            addTrust("odi", 3)
            hammer(at: V2(Landmarks.odiLamp.x + 1, 37), for: 2)
            setOutcome("answer", "Ran cable from the signal battery. Every bed lit.")
        default:
            lightBeds(1)
            story.flags.insert("odi.kept")
            remember("odi", "keptGear")
            setOutcome("answer", "Kept the gear for the climb. One bed lit.")
        }
        story.step("answer", "beds")
        emit(.saveNow)
    }

    static let cableCost = [ItemStack(.wire, 4), ItemStack(.fasteners, 2)]
    var canRunCable: Bool { Game.cableCost.allSatisfy { available($0.id) >= $0.count } }
    var canLendLamp: Bool { inv.count(.lamp) > 0 || storage.count(.lamp) > 0 || world.props.contains { $0.kind == .lamp } }

    func lightBeds(_ n: Int) {
        let beds = world.props.indices.filter { world.props[$0].id.hasPrefix("odi.bed") }.sorted { world.props[$0].id < world.props[$1].id }
        for (k, i) in beds.enumerated() where k < n { world.props[i].flags.insert("lit") }
    }

    /// The lamp comes back when Max asks. The bed it lit goes dark again.
    func odiReturnLamp() {
        guard story.flags.contains("odi.lent"), !story.flags.contains("odi.lampBack") else { return }
        story.flags.insert("odi.lampBack")
        if inv.add(.lamp, 1) < 1 { storage.add(.lamp, 1) }
        let beds = world.props.indices.filter { world.props[$0].id.hasPrefix("odi.bed") && world.props[$0].flags.contains("lit") }.sorted { world.props[$0].id < world.props[$1].id }
        if let last = beds.last, beds.count > 1 { world.props[last].flags.remove("lit") }
        remember("odi", "tookLampBack")
        emit(.saveNow)
    }

    var odiStatusLine: String {
        let lit = odiBedsLit
        let grown = world.props.filter { $0.id.hasPrefix("odi.bed") && $0.flags.contains("grown") }.count
        if grown >= 4 { return "Look at them. Beans on every bed, and the chard’s up past my knee." }
        if grown >= 2 { return "Two beds coming on. Beans and chard. The dark ones are still just dirt." }
        if grown == 1 { return "One bed. It’s enough to keep me in greens, not enough to share." }
        if lit >= 2 { return "They’re up. Give it a while and you’ll see what light does." }
        return "Same as ever: the lit bed grows, the dark ones wait."
    }
}
