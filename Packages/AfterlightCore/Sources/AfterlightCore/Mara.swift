import Foundation

// Chapter 3: Dry Taps. Mara keeps the outpost at the end of the warm pipe. Her pump has run dry and her
// lift has stalled. Max can help with the water, pay for the lift, or climb the old chimney on his own.

public enum MaraDeal {
    public static let water = "deal.water"
    public static let lift = "deal.lift"
    public static let waterJob = "job.water"
    public static let liftJob = "job.lift"
    /// What the lift repair costs when Max pays instead of helping.
    public static let price: [ItemStack] = [ItemStack(.pipe, 1), ItemStack(.wire, 2), ItemStack(.fasteners, 4)]
    public static let chimneyCost: [ItemStack] = [ItemStack(.rope, 2), ItemStack(.fasteners, 2)]
    public static let installSeconds = 120.0
    public static let liftSeconds = 150.0
}

extension Quest {
    public static var dryTaps: Quest { Quests.get("outpost") }
    public static var outpostWater: Quest { Quests.get("water") }
}

extension Game {

    // MARK: state

    public var waterOn: Bool { story.coop.water.outpostPumpRunning }
    public var liftRepaired: Bool { world.prop("mara.lift")?.flags.contains("repaired") ?? false }
    public var hatchOpen: Bool { world.prop("sump.hatch")?.flags.contains("open") ?? true }
    public var maraMet: Bool { story.flags.contains("mara.met") }
    var inOutpost: Bool { max.pos.x > 73.4 && max.pos.x < 87 && max.pos.y > 4.5 && max.pos.y < 9.6 }
    var inSump: Bool { max.pos.x > 79.5 && max.pos.x < 87 && max.pos.y > 9.6 && max.pos.y < 14.6 }
    var maraInSump: Bool { mara.pos.y > 9.6 }
    public var nearMara: Bool { story.chapter >= 3 && abs(mara.pos.x - max.pos.x) < 1.6 && abs(mara.pos.y - max.pos.y) < 1.2 }
    /// Mara notices what happens in the room she's in.
    var maraSeesMax: Bool { (inOutpost && !maraInSump) || (inSump && maraInSump) }
    /// Home gets water from its own pump, or from the outpost line when Max routes it there.
    public var homeWater: Bool { story.flags.contains("pumpFixed") || story.coop.water.homeFromOutpost > 0 }

    public func say(_ who: String, _ text: String, _ d: Double = 4) { speechWho = who; speechText = text; speechT = d }

    // MARK: hooks used by the shared-job engine

    func routeBlocker(_ j: SharedJob) -> String? {
        if j.siteID == "sump.intake" && !hatchOpen { return "The sump hatch is barred shut. Mara can’t get down to the intake." }
        return nil
    }

    func standingBlocker(_ j: SharedJob) -> String? {
        if j.id == MaraDeal.liftJob && waterOn && story.coop.water.route != .outpost {
            return "Mara won’t finish your lift while her tap’s dry."
        }
        return nil
    }

    func applyEffect(_ effect: String, job: SharedJob) {
        switch effect {
        case "waterOn":
            story.coop.water.outpostPumpRunning = true
            story.coop.water.route = .outpost
            if let i = world.propIndex("mara.pump") { world.props[i].flags.insert("running") }
            if let aid = job.agreementID { keepTerm(aid, "t.install") }
            story.step("water", "run")
            addTrust("mara", 2)
            emit(.pour(at: V2(75.8, 8)))
            say("mara", "Hear that? Pressure. Thank you.")
            if agreement(MaraDeal.water)?.owedToMax.contains(where: { $0.contains("trail meals") }) == true {
                let added = inv.add(.trailMeal, 2)
                if added < 2 { storage.add(.trailMeal, 2 - added) }
                emit(.pickup("Trail meal ×2"))
                keepTerm(MaraDeal.water, "t.thanks")
            }
        case "liftOn":
            if let i = world.propIndex("mara.lift") { world.props[i].flags.insert("repaired") }
            if let i = world.propIndex("transit.lift") { world.props[i].flags.insert("repaired") }
            if let aid = job.agreementID { keepTerm(aid, "t.lift") }
            emit(.chime)
            say("mara", "Lift’s yours. It goes as far as the old transit platform.")
        default: break
        }
    }

    func onDelivered(_ part: ItemStack, job id: String) {
        if id == MaraDeal.waterJob && part.id == .pressureValve {
            // If the only valve Max could have brought is Mara's own spare, she knows it on sight.
            let sumpValveStillThere = world.prop("sump.valve")?.stock.contains { $0.id == .pressureValve } ?? false
            if holding("mara", .pressureValve) > 0 && sumpValveStillThere {
                settleHolding("mara", .pressureValve, 1)
                addEvidence(Evidence(id: "spare.inPump", heldBy: "mara", against: "max", text: "She knows her own spare valve. It came off her shelf."))
                addTrust("mara", -1)
                say("mara", "That’s my spare. I scratched that mark in it myself. …It’s going in the right pump, at least.")
            }
            keepTerm(MaraDeal.water, "t.valve")
            story.step("water", "valve")
        }
        if id == MaraDeal.liftJob, let j = job(id), j.prerequisites.allSatisfy(\.done) {
            keepTerm(MaraDeal.lift, "t.pay")
        }
    }

    // MARK: Mara herself

    /// Where Mara wants to be: at whichever job she's working, waiting at a blocked route, or at home.
    func maraTarget() -> V2 {
        if let id = activeJobID(for: "mara"), let j = job(id) {
            if j.status == .working { return j.site }
            if j.status == .paused && j.siteID == "sump.intake" && !hatchOpen { return V2(Double(Landmarks.hatch.c) - 0.6, 9) }
        }
        // Before they've met, with the water off: she's at her dead tap, holding a can under it.
        if !maraMet && !waterOn { return Self.maraTapSpot }
        return Landmarks.maraHome
    }

    static let maraTapSpot = V2(76.5, 9)
    /// Mara standing at the dry tap with a can, waiting for water that doesn't come.
    public var maraAtTap: Bool { !maraMet && !waterOn && mara.pos.dist(Self.maraTapSpot) < 0.3 }

    func maraTick(_ dt: Double) {
        guard story.chapter >= 3 else { return }
        let target = maraTarget()
        let hatchX = Double(Landmarks.hatch.c) + 0.5
        // Changing level goes by the sump rungs.
        let goalX = abs(target.y - mara.pos.y) > 0.5 ? hatchX : target.x
        let dx = goalX - mara.pos.x
        if abs(dx) > 0.15 {
            mara.face = dx > 0 ? 1 : -1
            mara.pos.x += mara.face == 1 ? Swift.min(dx, 1.5 * dt) : Swift.max(dx, -1.5 * dt)
            mara.walking = true
        } else {
            mara.walking = false
            if abs(target.y - mara.pos.y) > 0.5 {
                let dy = target.y - mara.pos.y
                mara.pos.y += dy > 0 ? Swift.min(dy, 2.2 * dt) : Swift.max(dy, -2.2 * dt)
            } else {
                mara.pos.y = target.y
                if !mara.walking && target == Landmarks.maraHome { mara.face = max.pos.x < mara.pos.x ? -1 : 1 }
                if !mara.walking && target == Self.maraTapSpot { mara.face = -1 }
            }
        }
    }

    // MARK: story beats

    func maraBeats() {
        let p = max.pos
        func once(_ k: String, _ body: () -> Void) {
            if !story.flags.contains("said." + k) { story.flags.insert("said." + k); body() }
        }
        if p.x > 36 && p.x < 73 && p.y < 10.5 && p.y > 5 { story.step("outpost", "pipe") }
        // First the sound: the pump dry-running, knocking down the line.
        if !waterOn && p.y < 10.5 && p.y > 5 && p.x > 50 && p.x < 87 {
            let beat = Int(time / 6)
            if story.counters["knock"] != beat {
                story.counters["knock"] = beat
                emit(.knock)
                once("knock") { think("Knocking. Not a person. A pump, running dry.", 3.4) }
            }
        }
        // Then the dry tap, then the stalled lift.
        if inOutpost {
            story.step("outpost", "knock")
            if !waterOn && p.x > 74.5 {
                once("tap") {
                    if maraAtTap {
                        // Max believed he was the last one. He isn't.
                        think("…Someone. A person. Holding a can under a dry tap.", 3.6)
                        later(3.8) { $0.say("mara", "…Hello? Who’s there?", 3) }
                    } else {
                        think("A tap. Bone dry.", 2.8)
                    }
                }
            }
            if p.x > 81.5 && story.flags.contains("said.tap") && !liftRepaired { once("lift") { think("And a lift. Stalled. That goes up.", 3) } }
            if !maraMet && !maraAtTap && p.x > 76.5 { once("maraHi") { say("mara", "Careful by the hatch. Who sent you down my line?") } }
        }
        if (abs(p.x - (Double(Landmarks.chimney) + 1.0)) < 2.5 && p.y < 9.5 && p.y > 6) {
            if !story.flags.contains("sawChimney") { story.flags.insert("sawChimney"); think("An old maintenance chimney. Rungs rusted off. Rope could do it.", 3.6) }
        }
        // Up: either way counts.
        if story.chapter == 3 && p.y < 4.0 && p.x > Double(Landmarks.transit.x0) && p.x < Double(Landmarks.transit.x1) && max.mode == .walk {
            finishChapter3()
        }
    }

    func finishChapter3() {
        guard story.chapter == 3 else { return }
        story.step("outpost", "up")
        story.flags.insert(liftRepaired && abs(max.pos.x - Landmarks.liftX) < 2 ? "up.lift" : "up.chimney")
        story.chapter = 4
        emit(.chapter(4, "The Transit Level"))
        later(2.5) { $0.think("A platform. Tracks, going both ways into the dark.", 3.6) }
        story.addQuest(.farEdge)
        story.flags.insert("sawPlatform")
        emit(.saveNow)
    }

    // MARK: contexts

    func maraContext() -> ContextAction? {
        guard story.chapter >= 3 else { return nil }
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        if nearMara { return act("panel:mara", maraMet ? "Talk to Mara" : "Say hello", V2(mara.pos.x, mara.pos.y - 2.4), !maraMet) }
        if let pr = world.prop("sump.intake"), near(pr, 1.4), pr.flags.contains("clogged") {
            return act("clearIntake", "Clear the intake", V2(pr.pos.x, pr.pos.y - 1.8), true)
        }
        // From the sump floor the hatch can always be opened: nobody gets shut in.
        if inSump && abs(max.pos.x - (Double(Landmarks.hatch.c) + 0.5)) < 1.3 {
            return act("panel:sump.hatch", hatchOpen ? "Hatch" : "Open the hatch", V2(Double(Landmarks.hatch.c) + 0.5, max.pos.y - 2.2), !hatchOpen)
        }
        let panels: [(String, String)] = [("mara.pump", "Pump"), ("mara.lift", "Lift"), ("mara.tap", "Tap"), ("mara.shelf", "Mara’s shelf"),
                                          ("sump.hatch", "Hatch"), ("chimney", "Old chimney"), ("transit.lift", "Lift")]
        for (id, label) in panels {
            if let pr = world.prop(id), near(pr, id == "chimney" ? 1.3 : 1.1) {
                return act("panel:\(id)", label, V2(pr.pos.x, pr.pos.y - 2.2), id == "mara.lift" && liftRepaired)
            }
        }
        return nil
    }

    func clearIntake() {
        guard let i = world.propIndex("sump.intake"), world.props[i].flags.contains("clogged") else { return }
        max.busy = 1.8
        max.stamina = Swift.max(0, max.stamina - 12)
        for k in 0..<5 { later(Double(k) * 0.3) { $0.emit(.bite(at: V2(81.2, 13.4), kind: .down, carved: true, face: $0.max.face)) } }
        later(1.8) { g in
            g.world.props[i].flags.remove("clogged")
            g.completeTask("intakeClear")
            g.keepTerm(MaraDeal.water, "t.intake")
            g.story.step("water", "intake")
            g.think("Silt and old roots. It’ll draw now.", 2.6)
            g.emit(.saveNow)
        }
    }

    // MARK: panels

    public func panel(_ id: String) -> Panel? {
        switch id {
        case "mara": return maraPanel()
        case "mara.pump": return pumpPanel()
        case "mara.lift": return liftPanel()
        case "transit.lift":
            let at = world.prop(id)?.pos ?? max.pos
            return Panel(id: id, title: "Lift", lines: [liftRepaired ? "Mara’s lift. It runs back down to the outpost." : "The cage is down at the outpost. Nothing up here to call it with."],
                         anchor: V2(at.x, at.y - 2.2), rows: liftRepaired ? [PanelRow(id: "ride.down", label: "Ride down", style: .primary)] : [])
        case "mara.tap": return tapPanel()
        case "mara.shelf": return shelfPanel()
        case "sump.hatch": return hatchPanel()
        case "chimney": return chimneyPanel()
        default: return nil
        }
    }

    func waterEffects(_ r: WaterRoute) -> String {
        switch r {
        case .outpost: return "Mara’s tap and beds: running · Your home: nothing from this line"
        case .home: return "Mara’s tap and beds: dry · Your home tank: filling"
        case .split: return "Mara’s tap: half flow · Your home tank: half flow"
        }
    }

    func termLine(_ t: Term) -> String {
        let mark = t.state == .kept ? "✓" : (t.state == .broken ? "✗" : "•")
        let who = t.by == "max" ? "You" : name(t.by)
        return "\(mark) \(who): \(t.text)" + (t.note.map { " — \($0)" } ?? "")
    }

    func maraPanel() -> Panel {
        let at = V2(mara.pos.x, mara.pos.y - 2.4)
        var lines: [String] = []
        var rows: [PanelRow] = []
        let priceText = MaraDeal.price.map { "\($0.id.name) ×\($0.count)" }.joined(separator: ", ")
        let chimneyText = MaraDeal.chimneyCost.map { "\($0.id.name) ×\($0.count)" }.joined(separator: ", ")
        let water = job(MaraDeal.waterJob), lift = job(MaraDeal.liftJob)

        if story.coop.evidence.contains(where: { $0.id == "saw.spare" }) && holding("mara", .pressureValve) > 0 {
            lines = ["I watched you take my spare valve off that shelf. Put it back, or bring me another."]
        } else if story.flags.contains("mara.missingSpare") && holding("mara", .pressureValve) > 0 {
            lines = ["My spare valve’s gone from the shelf. I’m not saying it was you. I’m saying it’s gone."]
        } else if !maraMet {
            lines = ["You followed the knocking. That’s my pump, running dry.",
                     "I’m Mara. The valve blew a week back and the intake’s choked with silt. No water, and no lift: I won’t run that drive dry."]
        } else if waterOn && story.coop.water.route != .outpost {
            lines = ["My tap’s dry again and the line valve’s turned toward your place. I can see it from here."]
        } else if let w = water, w.status == .working || w.status == .paused {
            lines = [w.blocker.map { "I’m stuck. \($0)" } ?? "Fitting your valve. Give me a couple of minutes."]
        } else if let l = lift, !l.finished, l.status == .working {
            lines = ["Working on your lift. The drive’s seized, but it’s coming."]
        } else if waterOn {
            lines = ["Water’s running. First time in a week the beds have had a drink."]
        } else {
            lines = ["Still dry out here."]
        }

        if water == nil {
            rows.append(PanelRow(id: "offer.collab", label: "Help with the water",
                                 detail: lift == nil
                                    ? "You: bring up the valve from the sump, clear the intake. Mara: fits the valve, then repairs your lift."
                                    : "You: bring up the valve, clear the intake. Mara: fits the valve, and gives you two trail meals.",
                                 style: .primary))
        }
        if lift == nil && !liftRepaired {
            rows.append(PanelRow(id: "offer.trade", label: "Pay for the lift", detail: "Price: \(priceText). The lift works; her pump stays dry."))
        }
        if water == nil && lift == nil && !story.flags.contains("declinedDeal") {
            rows.append(PanelRow(id: "offer.decline", label: "I’ll find my own way up", detail: "The old chimney back along the line. Costs \(chimneyText)."))
        }
        if holding("mara", .pressureValve) > 0 {
            rows.append(PanelRow(id: "return.spare", label: "Give her a valve back",
                                 detail: inv.count(.pressureValve) > 0 ? "Returns what you took." : "You need a valve to give back.",
                                 enabled: inv.count(.pressureValve) > 0))
        }
        for a in story.coop.agreements where a.with == "mara" {
            rows.append(.info("a.\(a.id)", "\(a.title) — \(a.state == .fulfilled ? "kept" : a.state.rawValue)", done: a.state == .fulfilled))
            for t in a.terms { rows.append(.info("t.\(a.id).\(t.id)", termLine(t), done: t.state == .kept)) }
            for o in a.owedToMax { rows.append(.info("o.\(a.id).\(o)", "Owed to you: \(o)")) }
        }
        return Panel(id: "mara", title: "Mara", speaker: "Mara", lines: lines, anchor: at, rows: rows)
    }

    func jobRows(_ j: SharedJob) -> [PanelRow] {
        var rows: [PanelRow] = []
        for c in j.prerequisites {
            let who = c.by == "max" ? "You" : name(c.by)
            rows.append(.info("pre.\(c.id)", "\(c.done ? "✓" : "•") \(who): \(c.text)", done: c.done))
        }
        switch j.status {
        case .working:
            rows.append(.info("status", "\(name(j.worker)) is working — about \(Int(j.secondsLeft.rounded(.up)))s left"))
        case .paused, .open:
            if let b = j.blocker { rows.append(.info("status", "Paused: \(b)")) }
        case .done:
            rows.append(.info("status", "Done", done: true))
        case .canceled:
            rows.append(.info("status", "Called off"))
        }
        return rows
    }

    func pumpPanel() -> Panel {
        let at = (world.prop("mara.pump")?.pos ?? max.pos)
        var rows: [PanelRow] = []
        var lines: [String] = []
        if waterOn {
            let r = story.coop.water.route
            lines = ["Running. The line valve sends it " + (r == .outpost ? "to Mara’s tap." : r == .home ? "down the warm line to your home." : "both ways, half each.")]
            let breaks = agreement(MaraDeal.water)?.terms.contains { $0.id == "t.water" && $0.state != .broken } ?? false
            for (route, label) in [(WaterRoute.outpost, "Run it to Mara’s tap"), (.home, "Send it home along the warm line"), (.split, "Split the flow")] {
                if route == r {
                    rows.append(PanelRow(id: "route.\(route.rawValue)", label: label + " (now)", detail: waterEffects(route), enabled: false, style: .done))
                } else {
                    let confirm = route == .outpost ? nil
                        : "This turns Mara’s water toward your home. \(waterEffects(route))." + (breaks ? " It breaks your deal with Mara, and that stays on record." : "")
                    rows.append(PanelRow(id: "route.\(route.rawValue)", label: label, detail: waterEffects(route), confirm: confirm, style: route == .outpost ? .primary : .action))
                }
            }
        } else {
            lines = ["Knocking, dry. The valve’s blown off and the intake’s full of silt."]
        }
        if let j = job(MaraDeal.waterJob), j.status != .done {
            rows += jobRows(j)
            for c in j.prerequisites where !c.done {
                if let part = c.part {
                    rows.append(PanelRow(id: "deliver.\(j.id).\(c.id)", label: "Hand over \(part.id.name)",
                                         detail: available(part.id) >= part.count ? nil : "You don’t have one yet.", enabled: available(part.id) >= part.count, style: .primary))
                }
            }
        }
        return Panel(id: "mara.pump", title: "Mara’s pump", lines: lines, anchor: V2(at.x, at.y - 2.2), rows: rows)
    }

    func liftPanel() -> Panel {
        let at = world.prop("mara.lift")?.pos ?? max.pos
        var rows: [PanelRow] = []
        var lines: [String] = []
        if liftRepaired {
            lines = ["The drive hums. It goes up to the old transit platform."]
            rows.append(PanelRow(id: "ride.up", label: "Ride up", style: .primary))
        } else if let j = job(MaraDeal.liftJob) {
            lines = [j.status == .canceled ? "The repair’s off. Anything you handed over is still by the cage." : "Mara’s repairing the drive."]
            rows += jobRows(j)
            if !j.finished {
                for c in j.prerequisites where !c.done {
                    if let part = c.part {
                        let ok = available(part.id) >= part.count
                        rows.append(PanelRow(id: "deliver.\(j.id).\(c.id)", label: "Hand over \(part.id.name) ×\(part.count)",
                                             detail: ok ? nil : "You have \(available(part.id)).", enabled: ok))
                    }
                }
                if j.agreementID == MaraDeal.lift {
                    rows.append(PanelRow(id: "cancel.lift", label: "Call off the deal",
                                         detail: j.reserved.isEmpty ? nil : "Parts you handed over stay by the cage until you take them back.",
                                         confirm: "Calling it off breaks your deal with Mara, and that stays on record."))
                }
            }
            if !j.reclaimable.isEmpty {
                let what = j.reclaimable.map { "\($0.id.name) ×\($0.count)" }.joined(separator: ", ")
                rows.append(PanelRow(id: "reclaim.lift", label: "Take back your parts", detail: what, style: .primary))
            }
        } else {
            lines = ["Stalled. The drive’s seized solid. Mara could get it moving."]
        }
        return Panel(id: "mara.lift", title: "Lift", lines: lines, anchor: V2(at.x, at.y - 2.6), rows: rows)
    }

    func tapPanel() -> Panel {
        let at = world.prop("mara.tap")?.pos ?? max.pos
        let f = story.coop.water.outpostTapFlow
        let line = f >= 1 ? "Running clear. Mara’s beds are drinking." : f > 0 ? "A thin trickle. Half the line goes elsewhere." : (waterOn ? "Dry. The water’s going somewhere else." : "Dry. Not a drop.")
        var lines = [line]
        if waterOn { lines.append(waterEffects(story.coop.water.route)) }
        return Panel(id: "mara.tap", title: "Tap", lines: lines, anchor: V2(at.x, at.y - 2.0), rows: [])
    }

    func shelfPanel() -> Panel {
        let at = world.prop("mara.shelf")?.pos ?? max.pos
        var rows: [PanelRow] = []
        let has = world.prop("mara.shelf")?.stock.contains { $0.id == .pressureValve } ?? false
        if has {
            rows.append(PanelRow(id: "take.spare", label: "Take the spare valve", detail: "This belongs to Mara. It isn’t salvage.",
                                 enabled: inv.room(for: .pressureValve) > 0,
                                 confirm: "This is Mara’s spare valve. Take it anyway?"))
        }
        if holding("mara", .pressureValve) > 0 {
            rows.append(PanelRow(id: "return.spare", label: "Put a valve back", enabled: inv.count(.pressureValve) > 0, style: .primary))
        }
        return Panel(id: "mara.shelf", title: "Mara’s shelf", lines: [has ? "Her tools, a coil of wire, and a spare pressure valve with a scratched mark." : "Her tools and a coil of wire."],
                     anchor: V2(at.x, at.y - 2.0), rows: rows)
    }

    func hatchPanel() -> Panel {
        let at = world.prop("sump.hatch")?.pos ?? max.pos
        var rows: [PanelRow] = []
        if hatchOpen {
            let someoneBelow = maraInSump
            rows.append(PanelRow(id: "hatch.bar", label: "Bar the hatch shut", detail: someoneBelow ? "Mara’s down there." : "Blocks the way down to the sump.", enabled: !someoneBelow))
        } else {
            rows.append(PanelRow(id: "hatch.open", label: "Open the hatch", style: .primary))
        }
        return Panel(id: "sump.hatch", title: "Sump hatch", lines: [hatchOpen ? "Open. Rungs go down into cold water." : "Barred shut. It opens from either side."],
                     anchor: V2(at.x, at.y - 1.8), rows: rows)
    }

    func chimneyPanel() -> Panel {
        let at = world.prop("chimney")?.pos ?? max.pos
        let rigged = world.climbs.contains { $0.id == "rope.chimney" }
        var rows: [PanelRow] = []
        var lines = ["An old maintenance chimney. Twenty feet straight up to the transit platform. The rungs rusted off long ago."]
        if rigged {
            lines.append("Your rope’s rigged. Push the wheel up to climb.")
        } else {
            let have = MaraDeal.chimneyCost.map { "\($0.id.name) \(available($0.id))/\($0.count)" }.joined(separator: ", ")
            let ok = MaraDeal.chimneyCost.allSatisfy { available($0.id) >= $0.count }
            rows.append(PanelRow(id: "chimney.rig", label: "Rig a rope and climb",
                                 detail: "Uses \(MaraDeal.chimneyCost.map { "\($0.id.name) ×\($0.count)" }.joined(separator: ", ")). You have: \(have).",
                                 enabled: ok, style: .primary))
        }
        return Panel(id: "chimney", title: "Old chimney", lines: lines, anchor: V2(at.x, at.y - 2.4), rows: rows)
    }

    // MARK: choices

    public func choosePanel(_ panelID: String, _ row: String) {
        switch row {
        case "offer.collab": offerCollab()
        case "offer.trade": offerTrade()
        case "offer.decline":
            story.flags.formUnion(["declinedDeal", "sawChimney", "mara.met"])
            story.step("outpost", "meet")
            say("mara", "Suit yourself. The old chimney’s back along the line. You’ll want two good ropes and something to anchor them.", 5)
        case "return.spare": returnSpare()
        case "take.spare": takeSpare()
        case "route.outpost": routeWater(.outpost)
        case "route.home": routeWater(.home)
        case "route.split": routeWater(.split)
        case "cancel.lift": cancelJob(MaraDeal.liftJob, by: "max")
        case "reclaim.lift": reclaim(job: MaraDeal.liftJob)
        case "ride.up": rideLift(up: true)
        case "ride.down": rideLift(up: false)
        case "hatch.bar": setHatch(open: false)
        case "hatch.open": setHatch(open: true)
        case "chimney.rig": rigChimney()
        default:
            if row.hasPrefix("deliver.") {
                let parts = row.split(separator: ".").map(String.init)   // deliver.job.<name>.c.<name>
                if parts.count >= 5 { deliver(job: parts[1] + "." + parts[2], contribution: parts[3...].joined(separator: ".")) }
            }
        }
        emit(.saveNow)
    }

    /// Closing Mara's first panel counts as meeting her.
    public func panelClosed(_ id: String) {
        if id == "mara" { meetMara() }
    }

    func meetMara() {
        if !maraMet { story.flags.insert("mara.met"); story.step("outpost", "meet") }
    }

    func offerCollab() {
        guard job(MaraDeal.waterJob) == nil else { return }
        meetMara()
        let liftAlready = job(MaraDeal.liftJob) != nil || liftRepaired
        var terms = [Term(id: "t.valve", by: "max", text: "Bring up the pressure valve from the sump"),
                     Term(id: "t.intake", by: "max", text: "Clear the pump’s intake"),
                     Term(id: "t.install", by: "mara", text: "Fit the valve and get the water running"),
                     Term(id: "t.water", by: "max", text: "The outpost’s water stays at the outpost")]
        var owed = ["A working lift up to the transit level"]
        if liftAlready {
            terms.append(Term(id: "t.thanks", by: "mara", text: "Two trail meals when the water runs"))
            owed = ["Two trail meals"]
        } else {
            terms.append(Term(id: "t.lift", by: "mara", text: "Repair Max’s lift"))
        }
        addAgreement(Agreement(id: MaraDeal.water, with: "mara", title: liftAlready ? "Water, with thanks" : "Water for a lift", terms: terms, owedToMax: owed))
        keepTerm(MaraDeal.water, "t.water")   // a standing promise: kept unless Max turns the water away
        // Things Max already did still count.
        if story.flags.contains("intakeClear") { keepTerm(MaraDeal.water, "t.intake") }
        story.addQuest(.outpostWater)
        addJob(SharedJob(id: MaraDeal.waterJob, title: "Restore the water", siteID: "sump.intake",
                         site: V2(81.6, Double(Landmarks.sump.floor)), worker: "mara",
                         contributions: [
                            Contribution(id: "c.valve", by: "max", text: "Hand over a pressure valve", kind: .deliver(ItemStack(.pressureValve))),
                            Contribution(id: "c.intake", by: "max", text: "Clear the intake in the sump", kind: .task("intakeClear")),
                            Contribution(id: "c.install", by: "mara", text: "Fit the valve", kind: .work(MaraDeal.installSeconds)),
                         ], effect: "waterOn", agreementID: MaraDeal.water))
        if !liftAlready {
            addJob(SharedJob(id: MaraDeal.liftJob, title: "Repair the lift", siteID: "mara.lift", site: V2(Landmarks.liftX - 0.9, 9), worker: "mara",
                             contributions: [Contribution(id: "c.fix", by: "mara", text: "Free the seized drive", kind: .work(MaraDeal.liftSeconds))],
                             effect: "liftOn", agreementID: MaraDeal.water))
        }
        addTrust("mara", 1)
        say("mara", liftAlready ? "Valve’s in the sump, by the intake. Bring it up and I’ll fit it." : "Deal. Valve’s down in the sump. Water first, then your lift.", 5)
    }

    func offerTrade() {
        guard job(MaraDeal.liftJob) == nil, !liftRepaired else { return }
        meetMara()
        let priceText = MaraDeal.price.map { "\($0.id.name) ×\($0.count)" }.joined(separator: ", ")
        addAgreement(Agreement(id: MaraDeal.lift, with: "mara", title: "Salvage for a lift",
                               terms: [Term(id: "t.pay", by: "max", text: "Pay \(priceText)"),
                                       Term(id: "t.lift", by: "mara", text: "Repair Max’s lift")],
                               owedToMax: ["A working lift up to the transit level"]))
        addJob(SharedJob(id: MaraDeal.liftJob, title: "Repair the lift", siteID: "mara.lift", site: V2(Landmarks.liftX - 0.9, 9), worker: "mara",
                         contributions: MaraDeal.price.enumerated().map { i, s in
                            Contribution(id: "c.pay\(i)", by: "max", text: "Hand over \(s.id.name) ×\(s.count)", kind: .deliver(s))
                         } + [Contribution(id: "c.fix", by: "mara", text: "Free the seized drive", kind: .work(MaraDeal.liftSeconds))],
                         effect: "liftOn", agreementID: MaraDeal.lift))
        say("mara", "Bring the parts to the cage. I start when they’re all there.", 4)
    }

    func takeSpare() {
        guard let i = world.propIndex("mara.shelf"), let k = world.props[i].stock.firstIndex(where: { $0.id == .pressureValve }),
              inv.room(for: .pressureValve) > 0 else { return }
        world.props[i].stock.remove(at: k)
        inv.add(.pressureValve)
        addHolding("mara", .pressureValve, 1, how: "Taken from Mara’s shelf")
        if maraSeesMax {
            addEvidence(Evidence(id: "saw.spare", heldBy: "mara", against: "max", text: "Mara watched you take her spare valve."))
            addTrust("mara", -2)
            say("mara", "That’s mine. I saw you.", 3)
        } else {
            story.flags.insert("mara.missingSpare")
        }
        emit(.pickup(ItemID.pressureValve.name))
    }

    func returnSpare() {
        guard holding("mara", .pressureValve) > 0, inv.count(.pressureValve) > 0, let i = world.propIndex("mara.shelf") else { return }
        inv.remove(.pressureValve, 1)
        world.props[i].stock.append(ItemStack(.pressureValve))
        settleHolding("mara", .pressureValve, 1)
        story.flags.remove("mara.missingSpare")
        addTrust("mara", 1)
        say("mara", evidence(heldBy: "mara").contains { $0.id == "saw.spare" } ? "Thank you for bringing it back." : "Oh — there it is. Thanks.", 3)
    }

    /// Changes where the outpost's water goes. Turning it away from the outpost breaks the water deal, and that stays recorded.
    public func routeWater(_ r: WaterRoute) {
        guard waterOn, story.coop.water.route != r else { return }
        advanceSharedJobs(to: clock())   // credit work done up to this moment first
        let before = story.coop.water.route
        story.coop.water.route = r
        let hasDeal = agreement(MaraDeal.water) != nil
        if r != .outpost {
            if hasDeal {
                let alreadyBroken = agreement(MaraDeal.water)?.terms.first { $0.id == "t.water" }?.state == .broken
                breakAgreement(MaraDeal.water, by: "max", term: "t.water",
                               note: r == .home ? "Max turned the outpost’s water toward his home." : "Max split the outpost’s water toward his home.")
                if !alreadyBroken { addTrust("mara", -3) }
            }
            addEvidence(Evidence(id: "water.diverted", heldBy: "mara", against: "max", text: "The line valve is in her own room. She watched her tap go dry."))
            think(r == .home ? "The tap coughs and goes quiet." : "The tap thins to a trickle.", 2.6)
            later(1.2) { $0.say("mara", r == .home ? "My tap’s dry. You turned the line valve." : "Half my water. You turned the line valve.", 4) }
        } else if before != .outpost {
            editAgreement(MaraDeal.water) { a in
                a.log.append("Max turned the water back to the outpost.")
                if let i = a.terms.firstIndex(where: { $0.id == "t.water" }), a.terms[i].state == .broken {
                    a.terms[i].note = (a.terms[i].note ?? "Broken") + " Later restored."
                }
            }
            addTrust("mara", 1)
            think("Back to her tap.", 2)
            later(1.0) { $0.say("mara", "It’s back. I won’t forget it went, though.", 4) }
        }
        advanceSharedJobs(to: clock())
    }

    func setHatch(open: Bool) {
        guard let i = world.propIndex("sump.hatch") else { return }
        if !open && maraInSump { return }
        advanceSharedJobs(to: clock())
        if open { world.props[i].flags.insert("open") } else { world.props[i].flags.remove("open") }
        world.setHatch(Landmarks.hatch.c, Landmarks.hatch.r, open: open)
        emit(.clank(at: V2(Double(Landmarks.hatch.c) + 0.5, 9)))
        advanceSharedJobs(to: clock())
    }

    func rideLift(up: Bool) {
        guard liftRepaired else { return }
        max.busy = 2.2
        max.vx = 0
        emit(.swell)
        let y = up ? Double(Landmarks.transit.floor) : 9.0
        later(1.8) { g in
            g.max.pos = V2(Landmarks.liftX, y)
            g.max.ground = true; g.max.vy = 0; g.max.vyG = 0; g.max.mode = .walk
            g.max.digFloor = y
            g.emit(.land(speed: 2))
        }
    }

    func rigChimney() {
        guard !world.climbs.contains(where: { $0.id == "rope.chimney" }),
              MaraDeal.chimneyCost.allSatisfy({ available($0.id) >= $0.count }) else { return }
        for c in MaraDeal.chimneyCost { consume(c.id, c.count) }
        world.climbs.append(Climb(id: "rope.chimney", x: Double(Landmarks.chimney) + 1.0, top: Double(Landmarks.transit.floor),
                                  bottom: 9.0, kind: .rope))
        story.flags.insert("chimneyRigged")
        max.busy = 1.2
        emit(.placed("rope"))
        hint("Push the wheel up to climb", 5)
    }
}
