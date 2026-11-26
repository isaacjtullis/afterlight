import Foundation

// Build 3 · The hotel and the people already busy there.
//
// The hotel sits east of the lower world, sealed off by rock. Two ways in: Odi's service lift (from her
// grow room to the lobby) and the back stairs (from the transit platform). Inside, three people are already
// at work: Odi trying to get a housekeeping cart down the luggage stair, Ellis clearing the loading floor
// for a corner kick, and Corvin, a scavenger who wants the hotel's battery. Each mission has an actor,
// a place, a thing, and a rule for helping, walking past or interrupting. "Outings" (leaving the hotel
// and coming back, or resting) move the errands on.

extension Landmarks {
    public static let lobby = (x0: 170, x1: 199, top: 45, floor: 52)
    public static let kitchen = (x0: 200, x1: 213, top: 46, floor: 52)
    public static let loadingFloor = (x0: 214, x1: 246, top: 41, floor: 52)
    public static let guestFloor = (x0: 170, x1: 212, top: 34, floor: 40)
    public static let upper = (x0: 170, x1: 248, top: 23, floor: 28)
    public static let exitWell = (x0: 247, x1: 248)
    public static let luggageX = 199.0
    public static let fireHatch = (c0: 172, c1: 173, r: 28)
    public static let galleryWell = (x0: 244, x1: 245)
    public static let gallery = (x0: 228, x1: 326, top: 5, floor: 12)
    public static let hotelLift = V2(171.6, 52)
    public static let backstairs = V2(175.2, 52)
    public static let transitDoor = V2(63.2, 3)
    public static let freightTop = V2(241.8, 28)
    public static let freightBottom = V2(241.8, 52)
}

extension Quest {
    public static var hotel: Quest { Quests.get("hotel") }
    public static var cart: Quest { Quests.get("cart") }
    public static var kick: Quest { Quests.get("kick") }
    public static var battery: Quest { Quests.get("battery") }
}

extension WorldGen {
    static func buildHotel(_ w: World) {
        func box(_ x0: Int, _ x1: Int, _ top: Int, _ floor: Int, _ b: Backdrop) {
            for c in (x0 - 1)...(x1 + 1) { w.set(c, top - 1, .metal); w.set(c, floor, .metal) }
            for r in top..<floor { for c in x0...x1 { w.set(c, r, .air, back: b) } }
        }
        // Everything solid first, so nothing natural leaks into the rooms.
        for r in 2..<58 { for c in 168...328 where w.m(c, r) == .air { w.set(c, r, .dirt, back: .earth) } }
        let L = Landmarks.lobby, K = Landmarks.kitchen, F = Landmarks.loadingFloor, G = Landmarks.guestFloor, U = Landmarks.upper
        box(L.x0, L.x1, L.top, L.floor, .hotel)
        box(K.x0, K.x1, K.top, K.floor, .hotel)
        box(F.x0, F.x1, F.top, F.floor, .hotel)
        box(G.x0, G.x1, G.top, G.floor, .hotel)
        box(U.x0, U.x1, U.top, U.floor, .hotel)
        // Doorways between the ground-floor rooms.
        for r in (L.floor - 2)..<L.floor { w.set(K.x0 - 1, r, .air, back: .hotel); w.set(F.x0 - 1, r, .air, back: .hotel); w.set(K.x0, r, .air, back: .hotel) }
        for r in K.top...(K.floor - 3) { w.set(K.x0, r, .metal) }
        for r in F.top...(F.floor - 3) { w.set(F.x0, r, .metal) }
        // Guest room partitions, doors at the floor.
        for x in [180, 190] { for r in G.top...(G.floor - 3) { w.set(x, r, .metal) } }
        // The luggage stair: a well from the guest floor down to the lobby.
        for c in 198...199 { for r in (G.floor)...(L.top - 1) { w.set(c, r, .air, back: .shaft) } }
        // The fire hatch at the top of the upper stair: barred steel until Max opens it from above.
        let H = Landmarks.fireHatch
        for c in H.c0...H.c1 { for r in (H.r + 1)..<G.top { w.set(c, r, .air, back: .shaft) }; w.set(c, G.top - 1, .air, back: .shaft); w.set(c, H.r, .metal) }
        // The exit stair: from the loading floor up to the plant-room landing.
        let E = Landmarks.exitWell
        for c in E.x0...E.x1 { for r in (U.floor + 1)..<F.floor { w.set(c, r, .air, back: .shaft) } }
        for c in (F.x1 + 1)...E.x1 { for r in F.top..<F.floor { w.set(c, r, .air, back: .shaft) } }
        for c in E.x0...E.x1 { w.set(c, U.floor, .air, back: .shaft) }
        // The gallery stair: up through the plant-room ceiling.
        let GW = Landmarks.galleryWell, GA = Landmarks.gallery
        for c in GW.x0...GW.x1 { for r in (GA.floor)..<U.top { w.set(c, r, .air, back: .shaft) } }
        // The upper gallery: a long cut-stone hall under the surface approach.
        for c in (GA.x0 - 1)...(GA.x1 + 1) { w.set(c, GA.top - 1, .rock); w.set(c, GA.floor, .rock) }
        for r in GA.top..<GA.floor { for c in GA.x0...GA.x1 { w.set(c, r, .air, back: .gallery) } }
        for c in GW.x0...GW.x1 { w.set(c, GA.floor, .air, back: .shaft) }
        // The surface door at the gallery's east end opens onto a short climb to daylight.
        for r in 2..<GA.top { for c in (GA.x1 - 3)...(GA.x1) { w.set(c, r, .air, back: .gallery) } }
    }

    static let hotelPropIDs: Set<String> = ["hotel.lift", "backstairs", "transit.door", "hotel.desk", "hotel.diagram", "kitchen.cupboard",
                                            "bench1", "bench2", "bench3", "hotel.cart", "guest.shower", "guest.bed1", "guest.bed2",
                                            "fire.hatch", "hotel.battery", "hotel.trolley", "freight.top", "freight.bottom", "exit.sign",
                                            "gallery.map", "gallery.station", "gallery.door", "gallery.crossing", "gallery.toll"]

    static func hotelProps() -> [Prop] {
        let lf = 52.0, gf = 40.0, uf = 28.0
        var hatch = Prop(id: "fire.hatch", kind: .thing, pos: V2(172.9, uf), look: "hatch"); hatch.flags = ["barred"]
        var lift = Prop(id: "hotel.lift", kind: .serviceLift, pos: Landmarks.hotelLift)
        lift.flags = []
        return [
            lift,
            Prop(id: "backstairs", kind: .thing, pos: Landmarks.backstairs, look: "door"),
            Prop(id: "transit.door", kind: .thing, pos: Landmarks.transitDoor, look: "door"),
            Prop(id: "hotel.desk", kind: .thing, pos: V2(182.5, lf), stock: [ItemStack(.breakfastCard)], look: "desk"),
            Prop(id: "hotel.diagram", kind: .thing, pos: V2(188.6, lf), look: "diagram"),
            Prop(id: "kitchen.cupboard", kind: .thing, pos: V2(208.4, lf), stock: [ItemStack(.ball)], look: "cupboard"),
            Prop(id: "bench1", kind: .thing, pos: V2(216.0, lf), look: "bench"),
            Prop(id: "bench2", kind: .thing, pos: V2(217.6, lf), look: "bench"),
            Prop(id: "bench3", kind: .thing, pos: V2(229.0, lf), look: "bench"),
            Prop(id: "hotel.cart", kind: .thing, pos: V2(196.8, gf), look: "cart"),
            Prop(id: "guest.shower", kind: .thing, pos: V2(187.4, gf), look: "shower"),
            Prop(id: "guest.bed1", kind: .thing, pos: V2(174.5, gf), look: "hotelBed"),
            Prop(id: "guest.bed2", kind: .thing, pos: V2(193.2, gf), look: "hotelBed"),
            hatch,
            Prop(id: "hotel.battery", kind: .thing, pos: V2(231.0, uf), stock: [ItemStack(.hotelBattery)], look: "battery"),
            Prop(id: "hotel.trolley", kind: .thing, pos: V2(235.5, uf), stock: [ItemStack(.inspectionLamp)], look: "trolley"),
            Prop(id: "freight.top", kind: .serviceLift, pos: Landmarks.freightTop),
            Prop(id: "freight.bottom", kind: .serviceLift, pos: Landmarks.freightBottom),
            Prop(id: "exit.sign", kind: .thing, pos: V2(245.6, lf), look: "exitSign"),
        ] + galleryProps()
    }
}

extension Game {

    // MARK: where Max is

    public var inHotel: Bool { max.pos.x >= 168 && max.pos.y > Double(Landmarks.gallery.floor) + 0.5 }
    var inLobby: Bool { inHotel && abs(max.pos.y - 52) < 1.2 && max.pos.x < 214 }
    var onGuestFloor: Bool { inHotel && abs(max.pos.y - 40) < 1.2 && max.pos.x < 213 }
    var onLoadingFloor: Bool { inHotel && abs(max.pos.y - 52) < 1.2 && max.pos.x >= 214 }
    var onUpperFloor: Bool { inHotel && abs(max.pos.y - 28) < 1.2 }
    public var outings: Int { story.counters["outings"] ?? 0 }

    // MARK: per frame

    func hotelTick(_ dt: Double) {
        // Coming back into the hotel after being away counts as an outing: errands move on.
        if max.pos.x < 160 && story.flags.contains("hotel.inside") { story.flags.remove("hotel.inside") }
        if inHotel && !story.flags.contains("hotel.inside") {
            story.flags.insert("hotel.inside")
            if story.flags.contains("hotel.seen") { passOuting() } else { firstHotelVisit() }
        }
        guard story.flags.contains("hotel.seen") else { return }
        if inLobby { story.step("hotel", "lobby") }
        cartTick(dt)
        ellisTick(dt)
        scavTick(dt)
        ballTick(dt)
        struggleTick(dt)
        maraVisitTick(dt)
        hotelRemarks()
    }

    func firstHotelVisit() {
        story.flags.insert("hotel.seen")
        if story.chapter < 6 { story.chapter = 6; emit(.chapter(6, "The Hotel")) }
        story.addQuest(.hotel)
        // Everybody is already at work.
        story.flags.insert("odi.out")
        odi.pos = V2(195.6, 40); odi.face = 1
        spawn("ellis", at: V2(226.0, 52))
        spawn("scav", at: V2(196.4, 52))
        setActor("scav") { $0.face = 1; $0.errand = "waiting" }
        story.counters["cart.since"] = outings
        story.counters["ellis.since"] = outings
        story.counters["scav.since"] = outings
        if maraMet && !story.flags.contains("mara.visited") {
            // Mara came up the back stairs to see it for herself.
            story.flags.insert("mara.visiting")
            story.maraRoute = []
            mara.pos = V2(184.2, 52); mara.face = -1
        }
        if story.flags.contains("wren.seen") {
            spawn("wren", at: V2(184.0, 40), carrying: [ItemStack(.fullCan, 2)])
            setActor("wren") { $0.face = 1; $0.errand = "hotel" }
        }
        later(1.5) { $0.think("A hotel. People paid to sleep here, once.", 3) }
        emit(.saveNow)
    }

    /// Leaving the hotel and coming back, or sleeping: unfinished errands go on without Max.
    func passOuting() {
        story.counters["outings", default: 0] += 1
        cartOuting()
        ellisOuting()
        scavOuting()
        if story.flags.contains("mara.visiting") { endMaraVisit() }
        emit(.saveNow)
    }

    func travel(to p: V2, _ text: String? = nil) {
        max.busy = 1.8; max.vx = 0
        emit(.swell)
        if let text { think(text, 2) }
        later(1.6) { g in
            g.max.pos = p
            g.max.ground = true; g.max.vy = 0; g.max.vyG = 0; g.max.mode = .walk
            g.max.digFloor = p.y
            g.emit(.land(speed: 2))
        }
    }

    // MARK: contexts

    func hotelContext() -> ContextAction? {
        let p = max.pos
        func act(_ id: String, _ label: String, _ at: V2, _ big: Bool = false) -> ContextAction { ContextAction(id: id, label: label, anchor: at, prominent: big) }
        if struggle != nil { return act("struggle", "Pull!", V2(p.x, p.y - 2.4), true) }
        if let c = cartContext() { return c }
        if let c = ellisContext() { return c }
        if let c = scavContext() { return c }
        for pr in world.props where near(pr, 1.2) {
            switch pr.id {
            case "odi.lift": if story.chapter >= 5 { return act("ride:hotel", "Ride up to the hotel", V2(pr.pos.x, pr.pos.y - 3.4), !story.flags.contains("hotel.seen")) }
            case "hotel.lift": return act("ride:odi", "Ride down to Odi’s", V2(pr.pos.x, pr.pos.y - 3.4))
            case "backstairs": return act("ride:transit", "Back stairs ▾ transit", V2(pr.pos.x, pr.pos.y - 2.6))
            case "transit.door": if story.chapter >= 5 { return act("ride:backstairs", "Stairs ▴ hotel", V2(pr.pos.x, pr.pos.y - 2.6)) }
            case "freight.bottom": if story.flags.contains("freight.down") { return act("ride:freightUp", "Freight lift ▴", V2(pr.pos.x, pr.pos.y - 3.4)) }
            case "freight.top": if story.flags.contains("freight.down") || scavState == "done" || scavState == "declined" { return act("ride:freightDown", "Freight lift ▾", V2(pr.pos.x, pr.pos.y - 3.4)) }
            case "hotel.desk": return act("x:desk", pr.stock.isEmpty ? "Front desk" : "Look at the front desk", V2(pr.pos.x, pr.pos.y - 2.2))
            case "hotel.diagram": return act("x:diagram", "Exit diagram", V2(pr.pos.x, pr.pos.y - 2.6), !story.isDone("hotel", "diagram"))
            case "kitchen.cupboard": if !pr.stock.isEmpty { return act("search:kitchen.cupboard", "Open the cupboard", V2(pr.pos.x, pr.pos.y - 2.2)) }
            case "guest.shower": return act("x:shower", "Shower", V2(pr.pos.x, pr.pos.y - 2.6))
            case "guest.bed1", "guest.bed2": return act("x:hotelBed", "A hotel bed", V2(pr.pos.x, pr.pos.y - 1.6))
            case "fire.hatch":
                if pr.flags.contains("barred") && onUpperFloor { return act("unbar", "Unbar the fire hatch", V2(pr.pos.x, pr.pos.y - 2.2), true) }
            case "hotel.battery": if !pr.stock.isEmpty && scavState != "toLift" { return act("search:hotel.battery", "Hotel battery", V2(pr.pos.x, pr.pos.y - 2.2)) }
            case "hotel.trolley": if !pr.stock.isEmpty { return act("search:hotel.trolley", "Service trolley", V2(pr.pos.x, pr.pos.y - 2.2)) }
            case "exit.sign": return act("x:exit", "EXIT ▴ GALLERY", V2(pr.pos.x, pr.pos.y - 2.6))
            default: break
            }
        }
        return nil
    }

    func performHotel(_ id: String) -> Bool {
        switch id {
        case "ride:hotel": travel(to: Landmarks.hotelLift, nil); emit(.clank(at: max.pos))
        case "ride:odi": travel(to: V2(155.6, 41), nil); emit(.clank(at: max.pos))
        case "ride:transit": travel(to: V2(Landmarks.transitDoor.x + 0.8, 3), "Down and down and down.")
        case "ride:backstairs": travel(to: V2(Landmarks.backstairs.x + 0.8, 52), "Up the back stairs.")
        case "ride:freightUp": travel(to: V2(Landmarks.freightTop.x - 1.2, 28)); emit(.clank(at: max.pos))
        case "ride:freightDown": travel(to: V2(Landmarks.freightBottom.x - 1.2, 52)); emit(.clank(at: max.pos))
        case "unbar": unbarHatch()
        case "struggle": struggleTug()
        default:
            if id.hasPrefix("x:") { examine(String(id.dropFirst(2))); return true }
            if performCart(id) || performEllis(id) || performScav(id) { return true }
            return false
        }
        return true
    }

    func examine(_ what: String) {
        switch what {
        case "desk":
            if let i = world.propIndex("hotel.desk"), !world.props[i].stock.isEmpty {
                world.props[i].stock.removeAll()
                if inv.add(.breakfastCard, 1) < 1 { storage.add(.breakfastCard, 1) }
                if story.flags.contains("mara.visiting") && abs(mara.pos.x - max.pos.x) < 4 && abs(mara.pos.y - max.pos.y) < 1.5 {
                    startTalk("x.breakfast"); emit(.talk)
                } else {
                    think("A breakfast card. You hung it on your door and somebody brought you eggs.", 3.6)
                }
            } else { think("A bell with no ringer. A pen on a chain, no pen.", 2.6) }
        case "diagram":
            story.step("hotel", "diagram")
            think("“YOU ARE HERE.” Exit stair from the loading floor, up past the plant room…", 3.6)
            later(3.8) { $0.think("…to the UPPER GALLERY. Then a door marked SURFACE APPROACH.", 3.6) }
            emit(.saveNow)
        case "shower":
            if let w = actor("wren"), !w.hidden, abs(w.pos.x - max.pos.x) < 6, abs(w.pos.y - max.pos.y) < 1.5, !story.flags.contains("x.shower") {
                story.flags.insert("x.shower")
                banter([("max", "Dad said you’d let clean water run out of this while you waited for it to get warm."),
                        ("wren", "Run. Onto the floor. Down a drain."),
                        ("wren", "I just carried two cans up four flights for Odi’s seedlings."),
                        ("max", "He said it felt nice."),
                        ("wren", "I bet it did.")])
                remember("wren", "showerTalk")
            } else {
                think("A shower. Dad used to let the water run while he waited for it to get warm. On purpose.", 3.8)
            }
        case "hotelBed": think("Somebody’s bed for one night, then somebody else’s.", 2.8)
        case "exit":
            think("The stair goes up past the plant room. There’s light way up there.", 3)
            story.step("hotel", "diagram")
        default: break
        }
    }

    // MARK: Mara's visit (the breakfast card)

    func maraVisitTick(_ dt: Double) {
        guard story.flags.contains("mara.visiting") else { return }
        mara.walking = false
        mara.face = max.pos.x < mara.pos.x ? -1 : 1
    }

    func endMaraVisit() {
        story.flags.remove("mara.visiting")
        story.flags.insert("mara.visited")
        mara.pos = Landmarks.maraHome
    }

    // MARK: the fire hatch

    func unbarHatch() {
        guard let i = world.propIndex("fire.hatch"), world.props[i].flags.contains("barred") else { return }
        world.props[i].flags.remove("barred")
        let H = Landmarks.fireHatch
        for c in H.c0...H.c1 { world.setHatch(c, H.r, open: true) }
        if !world.climbs.contains(where: { $0.id == "stairs.upper" }) {
            world.climbs.append(Climb(id: "stairs.upper", x: Double(H.c1), top: Double(H.r), bottom: 40, kind: .rungs))
        }
        emit(.clank(at: V2(Double(H.c1), Double(H.r))))
        think("The bar slides. The stair below is open now, both ways.", 3)
        story.flags.insert("hatchOpenHotel")
        story.step("battery", "hatch")
        emit(.saveNow)
    }

    public var hotelHatchOpen: Bool { story.flags.contains("hatchOpenHotel") }

    // MARK: remarks while there's time to listen

    func hotelRemarks() {
        // Odi sorting seed packets in her room, back home.
        if inOdiRoom && !story.flags.contains("odi.out") && !story.flags.contains("x.seeds") && story.flags.contains("hotel.seen") && nearOdiNow {
            story.flags.insert("x.seeds")
            banter([("odi", "Look at this one. Lawn grass. Somebody’s mother grew grass outside her house."),
                    ("odi", "On purpose. Then cut it every week."),
                    ("odi", "What did she do with the cuttings?"),
                    ("max", "I have no idea."),
                    ("odi", "Me neither. I never asked mine anything.")])
        }
    }

    // MARK: lights for the hotel

    var hotelLights: [(pos: V2, radius: Double)] {
        guard max.pos.x > 150 else { return [] }
        var out: [(V2, Double)] = []
        // A few emergency lights still burn; the rest the player brings.
        out.append((V2(178, 48.5), 6)); out.append((V2(192, 48.5), 6)); out.append((V2(206, 48.5), 5))
        out.append((V2(230, 45), 8)); out.append((V2(186, 37), 5))
        out.append((V2(Double(Landmarks.exitWell.x0) + 1.5, 44), 5))
        if story.flags.contains("scav.stall") { out.append((V2(Self.stallPos.x, 49.5), 6)) }
        out.append(contentsOf: galleryLights)
        return out
    }

    func hotelPanel(_ id: String) -> Panel? { nil }
    func hotelRow(_ panel: String, _ row: String) -> Bool { false }

    func hotelCan(_ what: String) -> Bool {
        switch what {
        case "cart.load": return inv.slots.contains { $0?.id.bulky == true }
        case "cart.stuck": return story.flags.contains("odi.out") && cartState == 0
        case "cart.helping": return story.flags.contains("odi.out") && cartHelping
        case "cart.down": return story.flags.contains("odi.out") && cartState == 4
        case "cart.half": return story.flags.contains("odi.out") && cartState == 10
        case "scav.atLift": return scavState == "atLift"
        case "scav.stall": return scavState.hasPrefix("stall") || scavState == "stole" || scavState == "done"
        case "scav.stole": return stallHasMaxsLamp
        case "scav.dealt": return ["deal", "climbing", "toLift"].contains(scavState)
        case "scav.waiting": return scavState == "waiting" || scavState == "declined" || scavState == "nobattery"
        case "ellis.clearing": return ellisState == 0
        case "ellis.played": return ellisState == 2
        case "ellis.kids": return ellisState == 3
        case "scav.bargain": return available(.coin) >= 2 || available(.fasteners) >= 4
        case "scav.warn": return actor("wren").map { !$0.hidden && abs($0.pos.x - max.pos.x) < 30 } ?? false
        default: return false
        }
    }

    func hotelDo(_ what: String) {
        switch what {
        case "mara.wouldYou": remember("mara", "breakfastTalk")
        default: scavDo(what); ellisDo(what); cartDo(what)
        }
    }

    func hotelVars() -> [String: String] {
        ["stallLine": scavStallLine]
    }

    func hotelArrived(_ id: String, _ tag: String) {
        scavArrived(id, tag)
    }
}
