import Foundation

// The glue between the campaign (Builds 2–4) and the game's existing systems: context actions,
// panels, dialogue hooks (do:, can:, {vars}) and cinematics.

extension Game {

    // MARK: context actions

    func campaignContext() -> ContextAction? {
        let p = max.pos
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        // Mara's cans.
        if inv.count(.fullCan) > 0 {
            if (abs(p.y - 3) < 1.5 && abs(p.x - Landmarks.transitDrop.x) < 2.5) || (nearMara && !maraHauling) {
                return act("can.down", "Set the can down", V2(p.x, p.y - 2.4), true)
            }
        }
        if nearMara && maraHauling && maraCans > 0 && inv.room(for: .fullCan) > 0 {
            return act("can.carry", "Carry a can", V2(mara.pos.x, mara.pos.y - 2.4), true)
        }
        if let d = world.prop("mara.drop"), near(d, 1.3), d.stock.contains(where: { $0.id == .fullCan }) {
            return act("panel:mara.drop", "Water cans", V2(d.pos.x, d.pos.y - 1.8))
        }
        // People with something to say.
        for a in visibleCast where hasTalk(a.id) && abs(a.pos.x - p.x) < 1.7 && abs(a.pos.y - p.y) < 1.4 {
            let met = remembers(a.id, "met")
            return act("panel:\(a.id)", met ? "Talk to \(Cast.name(a.id))" : "Say hello", V2(a.pos.x, a.pos.y - 2.4), !met)
        }
        if let c = hotelContext() { return c }
        if let c = galleryContext() { return c }
        return nil
    }

    func performCampaign(_ id: String) -> Bool {
        switch id {
        case "can.carry": carryMarasCan()
        case "can.down": setCanDown()
        case "flash.signal":
            if world.prop("odi.signal") != nil && !story.flags.contains("odi.out") { startAnswer() } else { think("Nobody answers this time.", 2) }
        default:
            if performHotel(id) { return true }
            if performGallery(id) { return true }
            return false
        }
        return true
    }

    // MARK: panels

    func campaignPanel(_ id: String) -> Panel? {
        switch id {
        case "mara.drop":
            let at = world.prop(id)?.pos ?? max.pos
            let n = world.prop(id)?.stock.first { $0.id == .fullCan }?.count ?? 0
            return Panel(id: id, title: "Mara’s drop", lines: ["\(n) full can\(n == 1 ? "" : "s"), left for whoever comes through thirsty."], anchor: V2(at.x, at.y - 2),
                         rows: [PanelRow(id: "drop.drink", label: "Drink from one", detail: "A cup, and the can stays for the next person.", enabled: n > 0, style: .primary)])
        default:
            return hotelPanel(id) ?? galleryPanel(id)
        }
    }

    func campaignRow(_ panel: String, _ row: String) -> Bool {
        switch row {
        case "drop.drink":
            hydration = 100
            emit(.pour(at: max.pos))
            think("Somebody hauled this up here for strangers.", 2.6)
            remember("max", "drankAtDrop")
            return true
        default:
            return hotelRow(panel, row) || galleryRow(panel, row)
        }
    }

    // MARK: dialogue hooks

    func campaignCan(_ what: String) -> Bool {
        switch what {
        case "odi.lend": return canLendLamp
        case "odi.cable": return canRunCable
        default: return hotelCan(what) || galleryCan(what)
        }
    }

    func campaignDo(_ what: String) {
        switch what {
        case "odi.lend": odiChoice("lend")
        case "odi.cable": odiChoice("cable")
        case "odi.keep": odiChoice("keep")
        case "odi.return": odiReturnLamp()
        case "odi.meet":
            odi.met = true
            remember("odi", "met")
            story.step("answer", "meet")
        default:
            if let r = what.split(separator: ".").first, r == "met" { return }
            hotelDo(what); galleryDo(what)
        }
    }

    func campaignVars() -> [String: String] {
        var v: [String: String] = [:]
        v["bedsLit"] = "\(odiBedsLit)"
        for (k, x) in hotelVars() { v[k] = x }
        return v
    }

    func talkEnded(_ graph: String) {
        if story.cast[graph] != nil { remember(graph, "met") }
        if graph == "odi" { odi.met = true; remember("odi", "met") }
    }

    // MARK: cinematics

    func campaignCineTick(_ dt: Double, kind: String) -> Int {
        switch kind {
        case "answer": return answerCineTick(dt)
        default: return galleryCineTick(dt, kind: kind)
        }
    }
}

extension Game {
    /// Light sources the campaign adds: lit grow beds, the answering lamp, travelers' lamps.
    public var campaignLights: [(pos: V2, radius: Double)] {
        var out: [(V2, Double)] = []
        let near = { (p: V2) in abs(p.x - self.max.pos.x) < 40 || (self.cine?.focus.map { abs($0.x - p.x) < 30 } ?? false) }
        for pr in world.props where pr.kind == .growBed && pr.flags.contains("lit") && near(pr.pos) { out.append((V2(pr.pos.x, pr.pos.y - 2.4), 4.2)) }
        if let s = world.prop("odi.signal"), odiLampBlink, near(s.pos) { out.append((V2(s.pos.x, s.pos.y - 3.2), 6)) }
        for a in visibleCast where a.lamp && near(a.pos) { out.append((V2(a.pos.x + Double(a.face) * 0.3, a.pos.y - 0.6), 3.6)) }
        out.append(contentsOf: hotelLights)
        return out
    }
}
