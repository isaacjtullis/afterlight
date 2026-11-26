import Foundation

// The three hotel missions. Each has: who, where, what they want, what happens if Max helps,
// what happens if he walks away (it moves on with "outings"), and what a later visit shows.

/// A short struggle over something two people both think is theirs. Not saved: closing the app
/// pauses the confrontation, and it can be picked up again.
public struct Struggle: Sendable {
    public var meter = 0.5
    public var t = 0.0
    public var over: String
}

extension Game {

    // MARK: Odi's cart

    /// 0 stuck at the top · 1 Max at the low end · 2–3 easing it down · 4 down in the lobby · 5 home, intact
    /// 10 Odi stripping the wheels for a smaller cart · 11 the handcart, home
    public var cartState: Int { story.counters["cart.state"] ?? 0 }
    func setCart(_ s: Int) { story.counters["cart.state"] = s }
    var cartHelping: Bool { (1...3).contains(cartState) }

    func cartTick(_ dt: Double) {
        if story.flags.contains("odi.out") && abs(odi.pos.x - max.pos.x) < 7 && abs(odi.pos.y - max.pos.y) < 1.5 {
            if !story.flags.contains("cart.seen") {
                story.flags.insert("cart.seen")
                story.addQuest(.cart)
                think("Odi, wrestling a cart at the top of the stair.", 2.6)
            }
        }
        // Odi faces her work.
        if story.flags.contains("odi.out") { odi.walking = false; odi.face = cartState == 10 ? 1 : (max.pos.x < odi.pos.x ? -1 : 1) }
    }

    func cartContext() -> ContextAction? {
        guard story.flags.contains("hotel.seen") else { return nil }
        let p = max.pos
        if cartHelping && inLobby && abs(p.x - Landmarks.luggageX) < 1.6 {
            let label = cartState == 1 ? "Take the low end" : (cartState == 2 ? "Ease it down" : "Bring it to the floor")
            return ContextAction(id: "cart.step", label: label, anchor: V2(Landmarks.luggageX, 52 - 3.2), prominent: true)
        }
        if story.flags.contains("odi.out") && abs(odi.pos.x - p.x) < 1.8 && abs(odi.pos.y - p.y) < 1.3 {
            return ContextAction(id: "panel:odi", label: "Talk to Odi", anchor: V2(odi.pos.x, odi.pos.y - 2.4), prominent: true)
        }
        if let c = world.prop("hotel.cart"), near(c, 1.3), !c.stock.isEmpty, cartState == 5 {
            return ContextAction(id: "search:hotel.cart", label: "Take your things off the cart", anchor: V2(c.pos.x, c.pos.y - 2), prominent: false)
        }
        return nil
    }

    func performCart(_ id: String) -> Bool {
        guard id == "cart.step", cartHelping, let ci = world.propIndex("hotel.cart") else { return false }
        max.busy = 1.4
        max.face = 1
        let k = cartState
        emit(.clank(at: V2(Landmarks.luggageX, 40 + Double(k) * 4)))
        let y = 40 + Double(k) * 4
        world.props[ci].pos = V2(Landmarks.luggageX, y)
        odi.pos = V2(Landmarks.luggageX - 0.6, Swift.min(52, y - 0.2))
        if k == 1 { banter([("odi", "Got it? I’ll feed it down. Don’t let it run.")]) }
        if k < 3 {
            setCart(k + 1)
        } else {
            setCart(4)
            world.props[ci].pos = V2(196.2, 52)
            odi.pos = V2(195.0, 52)
            story.step("cart", "down")
            remember("odi", "helpedCart")
            addTrust("odi", 2)
            later(0.6) { $0.say("odi", "Down. In one piece. Want to load anything on it for the trip back?", 4) }
        }
        emit(.saveNow)
        return true
    }

    func cartDo(_ what: String) {
        switch what {
        case "cart.help":
            setCart(1)
            say("odi", "Go down and take the low end. I’ll feed it to you.", 3.6)
        case "cart.load":
            guard let si = inv.slots.firstIndex(where: { $0?.id.bulky == true }), let s = inv.slots[si], let ci = world.propIndex("hotel.cart") else { return }
            inv.slots[si] = nil
            world.props[ci].stock.append(s)
            remember("odi", "loadedCart")
            cartGoHome()
        case "cart.home": cartGoHome()
        case "cart.finishSmall":
            remember("odi", "helpedHandcart")
            addTrust("odi", 1)
            hammer(at: V2(odi.pos.x + 0.8, 51.5), for: 1.4)
            handcartDone()
        default: break
        }
    }

    /// Odi wheels whichever cart she ended up with down to her room, and goes home.
    func cartGoHome() {
        guard let ci = world.propIndex("hotel.cart") else { return }
        setCart(5)
        world.props[ci].pos = V2(153.6, 41)
        story.flags.remove("odi.out")
        odi.pos = Landmarks.odiHome
        story.step("cart", "home")
        setOutcome("cart", "Helped Odi bring the hotel cart down. Brass rail and all.")
        emit(.saveNow)
    }

    func handcartDone() {
        setCart(11)
        if let hi = world.propIndex("hotel.handcart") { world.props[hi].pos = V2(153.6, 41); world.props[hi].look = "handcart" }
        story.flags.remove("odi.out")
        odi.pos = Landmarks.odiHome
        story.step("cart", "home")
        setOutcome("cart", "Odi built a narrow handcart from the hotel cart’s wheels.")
        emit(.saveNow)
    }

    func cartOuting() {
        guard story.flags.contains("cart.seen") else { return }
        switch cartState {
        case 0:
            // She gives up on the stair and takes the wheels off instead.
            setCart(10)
            if let ci = world.propIndex("hotel.cart") { world.props[ci].look = "cartStripped" }
            if world.propIndex("hotel.handcart") == nil { world.props.append(Prop(id: "hotel.handcart", kind: .thing, pos: V2(190.4, 52), look: "handcartFrame")) }
            odi.pos = V2(189.2, 52)
        case 10: handcartDone()
        case 4: cartGoHome()
        default: break
        }
    }

    // MARK: Ellis and the loading floor

    /// 0 clearing benches · 1 playing · 2 played · 3 cleared one end himself, kids with coats for goalposts
    public var ellisState: Int { story.counters["ellis.state"] ?? 0 }
    func setEllis(_ s: Int) { story.counters["ellis.state"] = s }

    func ellisTick(_ dt: Double) {
        guard let e = actor("ellis"), !e.hidden else { return }
        if onLoadingFloor && !story.flags.contains("ellis.seen") {
            story.flags.insert("ellis.seen")
            story.addQuest(.kick)
        }
        if ellisState == 0 && e.route.isEmpty && talk?.graph != "ellis" {
            // Shoving at the last bench, then stepping back to look at his pitch.
            let b = world.prop("bench3")?.pos.x ?? 229
            let target = Int(time / 6) % 2 == 0 ? b + 1.0 : b + 4.0
            send("ellis", [Waypoint(target, 52, wait: 1.5)])
        }
        if ellisState == 1 || ellisState == 3 { ellisPlayTick(dt) }
    }

    func ellisContext() -> ContextAction? {
        guard story.flags.contains("ellis.seen") else { return nil }
        if ellisState == 0 && !story.flags.contains("ellis.bench"), let b = world.prop("bench3"), near(b, 1.4), nearActor("ellis", 6) {
            return ContextAction(id: "ellis.bench", label: "Take the other end", anchor: V2(b.pos.x, b.pos.y - 1.8), prominent: true)
        }
        if ellisState == 3, nearActor("kid1", 3) || nearActor("kid2", 3) {
            return ContextAction(id: "ellis.join", label: "Join the game", anchor: V2(max.pos.x, max.pos.y - 2.4), prominent: true)
        }
        if ellisState == 2 && inv.count(.ellisLamp) > 0 && nearActor("ellis") {
            return ContextAction(id: "ellis.lampBack", label: "Give Ellis his lamp back", anchor: V2(max.pos.x, max.pos.y - 2.4), prominent: true)
        }
        return nil
    }

    func performEllis(_ id: String) -> Bool {
        switch id {
        case "ellis.bench":
            guard let i = world.propIndex("bench3") else { return true }
            max.busy = 1.4
            hammer(at: world.props[i].pos, for: 0.6)
            later(1.2) { g in
                if let i = g.world.propIndex("bench3") { g.world.props[i].pos = V2(219.4, 52) }
                g.story.flags.insert("ellis.bench")
                g.remember("ellis", "movedBench")
                g.story.step("kick", "pitch")
                g.say("ellis", g.available(.ball) > 0 ? "That’s the pitch. And you’ve got the ball? Go on, then." : "That’s the last one. Now if I hadn’t kicked the ball into the kitchen…", 4)
                g.emit(.saveNow)
            }
        case "ellis.join":
            remember("ellis", "joinedKids")
            startKickabout(withKids: true)
        case "ellis.lampBack":
            inv.remove(.ellisLamp, 1)
            remember("ellis", "returnedLamp")
            addTrust("ellis", 2)
            say("ellis", "Thanks. Come back and play. I mean it.", 3)
            story.step("kick", "lamp")
            emit(.saveNow)
        default: return false
        }
        return true
    }

    func ellisDo(_ what: String) {
        switch what {
        case "ellis.ball":
            guard available(.ball) > 0 else { return }
            consume(.ball, 1)
            remember("ellis", "foundBall")
            if !story.flags.contains("ellis.bench"), let i = world.propIndex("bench3") {
                world.props[i].pos = V2(219.4, 52); story.flags.insert("ellis.bench")
            }
            story.step("kick", "pitch")
            startKickabout(withKids: false)
        case "ellis.lampBack": _ = performEllis("ellis.lampBack")
        default: break
        }
    }

    func ellisOuting() {
        guard story.flags.contains("ellis.seen") else { return }
        if ellisState == 0 {
            // He clears one end himself. Two kids turn up with coats for goalposts.
            setEllis(3)
            if let i = world.propIndex("bench3") { world.props[i].pos = V2(219.4, 52) }
            story.flags.insert("ellis.bench")
            spawn("kid1", at: V2(236, 52)); spawn("kid2", at: V2(241, 52))
            if world.propIndex("coats") == nil { world.props.append(Prop(id: "coats", kind: .thing, pos: V2(244.2, 52), look: "coats")) }
            if let i = world.propIndex("kitchen.cupboard"), world.props[i].stock.contains(where: { $0.id == .ball }) {
                world.props[i].stock.removeAll { $0.id == .ball }   // they found it themselves
            }
            setOutcome("kick", "Ellis cleared one end himself. Two kids play with coats for goalposts.")
        }
        if ellisState == 2 && inv.count(.ellisLamp) > 0 && !remembers("ellis", "returnedLamp") { remember("ellis", "keptLamp") }
    }

    // MARK: the kickabout

    public var ball: (pos: V2, vel: V2)? {
        guard let x = story.counters["ball.x"], let y = story.counters["ball.y"] else { return nil }
        return (V2(Double(x) / 100, Double(y) / 100), V2(Double(story.counters["ball.vx"] ?? 0) / 100, Double(story.counters["ball.vy"] ?? 0) / 100))
    }
    func setBall(_ p: V2, _ v: V2) {
        story.counters["ball.x"] = Int(p.x * 100); story.counters["ball.y"] = Int(p.y * 100)
        story.counters["ball.vx"] = Int(v.x * 100); story.counters["ball.vy"] = Int(v.y * 100)
    }
    func clearBall() { for k in ["ball.x", "ball.y", "ball.vx", "ball.vy"] { story.counters[k] = nil } }
    public var kickScore: (max: Int, them: Int) { (story.counters["kick.max"] ?? 0, story.counters["kick.them"] ?? 0) }

    func startKickabout(withKids: Bool) {
        setEllis(1)
        if withKids { story.flags.insert("kick.kids") }
        story.counters["kick.max"] = 0; story.counters["kick.them"] = 0
        story.counters["kick.t"] = Int(time)
        setBall(V2(230, 51.6), V2(0, 0))
        if inv.add(.ellisLamp, 1) > 0 { say("ellis", "Take my lamp, you’ll want to see it coming. Bring it back after.", 4) }
        if world.propIndex("coats") == nil { world.props.append(Prop(id: "coats", kind: .thing, pos: V2(244.2, 52), look: "coats")) }
        hint("Run into the ball to kick it. DIG for a big one. Score at the coats.", 6)
        story.step("kick", "play")
        emit(.saveNow)
    }

    func ballTick(_ dt: Double) {
        guard var b = ball else { return }
        if story.counters["ball.hold"].map({ Double($0) > time }) == true { return }
        let F = Landmarks.loadingFloor
        b.vel.y += 16 * dt
        b.pos = b.pos + b.vel * dt
        let floorY = Double(F.floor) - 0.35, ceilY = Double(F.top) + 0.35
        if b.pos.y > floorY { b.pos.y = floorY; b.vel.y = -abs(b.vel.y) * 0.45; b.vel.x *= 0.96 }
        if b.pos.y < ceilY {
            b.pos.y = ceilY; b.vel.y = abs(b.vel.y) * 0.5
            emit(.clank(at: b.pos))
            if !story.flags.contains("x.ceiling") {
                // The exchange: the ball rests while they argue, then play goes on.
                story.flags.insert("x.ceiling")
                story.counters["ball.hold"] = Int(time) + 13
                banter([("ellis", "Ceiling. Always the ceiling."),
                        ("ellis", "How hard do you think you could kick it outside? With nothing over you?"),
                        (story.flags.contains("kick.kids") ? "kid1" : "max", "And how far would you have to walk to get it back?"),
                        ("ellis", "…Kick off.")])
            }
        }
        b.vel.x *= (1 - 0.6 * dt)
        // Goals: the coats at the east end are Max's target; the west wall is theirs.
        if b.pos.x > Double(F.x1) - 0.8 {
            story.counters["kick.max", default: 0] += 1
            say("ellis", ["Oh, come on.", "Fine. Fine!", "Lucky."][Swift.min(2, kickScore.max - 1)], 2.4)
            b = (V2(230, 51.6), V2(0, 0))
        } else if b.pos.x < Double(F.x0) + 0.8 {
            story.counters["kick.them", default: 0] += 1
            say(story.flags.contains("kick.kids") ? "kid2" : "ellis", "Corner! That was a corner!", 2.4)
            b = (V2(230, 51.6), V2(0, 0))
        }
        // Max kicks by running into it; DIG puts his boot through it.
        if abs(b.pos.x - max.pos.x) < 0.6 && b.pos.y > max.pos.y - 1.4 {
            let dir = Double(max.face)
            let big = max.swingOn
            b.vel = V2(dir * (big ? 11 : 6.5) + max.vx * 0.4, big ? -10 : -4.5)
            b.pos.x = max.pos.x + dir * 0.65
        }
        // Ellis (and the kids) chase it and send it back west.
        for id in ["ellis", "kid1", "kid2"] {
            guard let a = actor(id), !a.hidden else { continue }
            if abs(b.pos.x - a.pos.x) < 0.6 && b.pos.y > a.pos.y - 1.4 {
                b.vel = V2(-(6 + Double(id.count % 3)), -5 - Double(Int(time * 3) % 3))
                b.pos.x = a.pos.x - 0.65
            }
        }
        setBall(b.pos, b.vel)
        // Full time: three goals either way, or a couple of minutes.
        let started = Double(story.counters["kick.t"] ?? Int(time))
        if ellisState == 1 && (kickScore.max >= 3 || kickScore.them >= 3 || time - started > 150) { endKickabout() }
    }

    func ellisPlayTick(_ dt: Double) {
        guard let b = ball else {
            // The kids kick it about on their own while Max isn't playing.
            if ellisState == 3 {
                for (i, id) in ["kid1", "kid2"].enumerated() where actor(id)?.route.isEmpty ?? false {
                    send(id, [Waypoint(232 + Double(i) * 6 + Double(Int(time / 3 + Double(i)) % 3), 52, wait: 1)])
                }
            }
            return
        }
        for id in ["ellis", "kid1", "kid2"] {
            guard let a = actor(id), !a.hidden else { continue }
            let home = id == "ellis" ? 236.0 : (id == "kid1" ? 226.0 : 240.0)
            let target = abs(b.pos.x - home) < 9 ? b.pos.x + 0.4 : home
            setActor(id) { $0.route = [Waypoint(Swift.min(245, Swift.max(215, target)), 52)]; $0.speed = 2.6 }
        }
    }

    func endKickabout() {
        let s = kickScore
        clearBall()
        setEllis(2)
        story.flags.remove("kick.kids")
        remember("ellis", "playedBall")
        addTrust("ellis", 1)
        say("ellis", s.max > s.them ? "You’ve got a boot on you. Same time next outing?" : "Good afternoon, that. Proper good.", 4)
        setOutcome("kick", "Played a kickabout on the loading floor with Ellis (\(s.max)–\(s.them)).")
        story.step("kick", "play")
        emit(.saveNow)
    }

    // MARK: Corvin and the battery

    /// "waiting" · "deal" · "climbing" · "toLift" · "atLift" · "done" (honest or careful) · "stole" · "declined" · "stall" · "nobattery"
    public var scavState: String { actor("scav")?.errand ?? "" }
    static let stallPos = V2(191.6, 52)

    func scavTick(_ dt: Double) {
        guard let s = actor("scav"), !s.hidden else { return }
        if inLobby && abs(s.pos.x - max.pos.x) < 8 && !story.flags.contains("scav.seen") {
            story.flags.insert("scav.seen")
            story.addQuest(.battery)
        }
        // Once the hatch is open he goes up for it.
        if s.errand == "deal" && hotelHatchOpen && s.route.isEmpty { scavGoUp() }
    }

    func scavGoUp() {
        setActor("scav") { $0.errand = "climbing" }
        send("scav", [Waypoint(Landmarks.luggageX, 52), Waypoint(Landmarks.luggageX, 40), Waypoint(Double(Landmarks.fireHatch.c1), 40),
                      Waypoint(Double(Landmarks.fireHatch.c1), 28), Waypoint(232.2, 28, wait: 1.5, tag: "battery")])
    }

    func scavArrived(_ id: String, _ tag: String) {
        guard id == "scav" else { return }
        switch tag {
        case "battery":
            if let bi = world.propIndex("hotel.battery"), world.props[bi].stock.contains(where: { $0.id == .hotelBattery }), let ti = world.propIndex("hotel.trolley") {
                // He can reach it: battery onto the trolley, trolley to the freight lift.
                world.props[bi].stock.removeAll { $0.id == .hotelBattery }
                world.props[ti].stock.append(ItemStack(.hotelBattery))
                setActor("scav") { $0.errand = "toLift" }
                send("scav", [Waypoint(Landmarks.freightTop.x + 1.0, 28, tag: "atLift")])
                if let ti = world.propIndex("hotel.trolley") { world.props[ti].pos = V2(Landmarks.freightTop.x + 1.6, 28) }
                say("scav", "Got it on the trolley. Meet me at the freight cage.", 3.4)
            } else {
                setActor("scav") { $0.errand = "nobattery" }
                say("scav", "Gone. Somebody beat me to it.", 3)
                send("scav", [Waypoint(Double(Landmarks.fireHatch.c1), 28), Waypoint(Double(Landmarks.fireHatch.c1), 40), Waypoint(Landmarks.luggageX, 40),
                              Waypoint(Landmarks.luggageX, 52), Waypoint(196.4, 52)])
            }
        case "atLift":
            setActor("scav") { $0.errand = "atLift"; $0.face = 1 }
        case "stall":
            setActor("scav") { $0.errand = "stall"; $0.face = 1 }
        default: break
        }
    }

    func scavContext() -> ContextAction? { nil }
    func performScav(_ id: String) -> Bool { false }

    func scavDo(_ what: String) {
        switch what {
        case "scav.deal":
            setActor("scav") { $0.errand = "deal" }
            remember("scav", "deal")
            story.step("battery", "deal")
            if hotelHatchOpen { scavGoUp() }
        case "scav.decline":
            setActor("scav") { $0.errand = "declined" }
            remember("scav", "refused")
            setOutcome("battery", "Turned Corvin down.")
        case "scav.ride":
            // Honest: both ride down, each leaves with what was promised.
            freightSplit(maxRides: true, lampFirst: false)
        case "scav.takeLamp":
            freightSplit(maxRides: false, lampFirst: true)
        case "scav.trust":
            freightSplit(maxRides: false, lampFirst: false)
        case "scav.confront":
            struggle = Struggle(over: "inspectionLamp")
            hint("Tap Pull! as fast as you can.", 3)
        case "scav.bargain":
            if available(.coin) >= 2 { consume(.coin, 2) } else { consume(.fasteners, 4) }
            buyBackLamp()
        case "scav.warn":
            remember("wren", "warnedAboutCorvin")
            remember("scav", "maxWarnedWren")
            say("wren", "Noted. I’ll keep my cans away from that stall.", 3)
        default: break
        }
    }

    func freightSplit(maxRides: Bool, lampFirst: Bool) {
        guard let ti = world.propIndex("hotel.trolley") else { return }
        if lampFirst || maxRides {
            world.props[ti].stock.removeAll { $0.id == .inspectionLamp }
            if inv.add(.inspectionLamp, 1) < 1 { storage.add(.inspectionLamp, 1) }
        }
        let stole = !lampFirst && !maxRides
        // The trolley goes down with him; what's on it is his now.
        let load = world.props[ti].stock
        world.props[ti].stock = []
        world.props[ti].pos = V2(Landmarks.freightBottom.x + 1.4, 52)
        setActor("scav") { a in
            a.carrying = load.filter { $0.id != .inspectionLamp }
            a.errand = stole ? "stole" : "done"
            a.pos = V2(Landmarks.freightBottom.x + 0.8, 52)
            a.route = [Waypoint(Self.stallPos.x + 0.9, 52, tag: "stall")]
        }
        story.flags.insert("freight.down")
        story.flags.insert("scav.stall")
        if world.propIndex("scav.stall") == nil { world.props.append(Prop(id: "scav.stall", kind: .thing, pos: Self.stallPos, look: "stall")) }
        if let si = world.propIndex("scav.stall") { world.props[si].stock = load.filter { $0.id == .inspectionLamp } }
        if maxRides {
            travel(to: V2(Landmarks.freightBottom.x - 1.2, 52))
            remember("scav", "keptDeal")
            setOutcome("battery", "Rode down with Corvin. He kept the deal: the lamp is yours.")
        } else if lampFirst {
            remember("scav", "maxTookLampFirst")
            setOutcome("battery", "Took the lamp before he went down. Fair, and nobody had to trust anybody.")
            later(2) { $0.think("The cage hums down. It comes back up empty.", 2.6) }
        } else {
            remember("scav", "keptBoth")
            setOutcome("battery", "Let Corvin take the cage. The lamp went down with him.")
            later(2) { $0.think("The cage hums down… and comes back up empty.", 2.6) }
            later(5) { $0.think("He sent it back empty. My lamp’s on his trolley.", 3) }
        }
        story.step("battery", "split")
        emit(.saveNow)
    }

    func scavOuting() {
        guard story.flags.contains("scav.seen"), let s = actor("scav") else { return }
        // Walked away: he tries the stairs. With the way open and the battery still there, he gets it.
        if ["declined", "waiting", "deal"].contains(s.errand) && hotelHatchOpen,
           let bi = world.propIndex("hotel.battery"), world.props[bi].stock.contains(where: { $0.id == .hotelBattery }) {
            world.props[bi].stock.removeAll { $0.id == .hotelBattery }
            setActor("scav") { a in a.carrying = [ItemStack(.hotelBattery)]; a.errand = "stall"; a.pos = V2(Self.stallPos.x + 0.9, 52); a.route = [] }
            story.flags.insert("scav.stall")
            if world.propIndex("scav.stall") == nil { world.props.append(Prop(id: "scav.stall", kind: .thing, pos: Self.stallPos, look: "stall")) }
            setOutcome("battery", "Corvin found his own way up and took the battery.")
        }
        if s.errand == "atLift" {
            // He doesn't wait forever: down the stairs with the trolley's battery, the lamp left where it was.
            if let ti = world.propIndex("hotel.trolley") {
                let lamp = world.props[ti].stock.filter { $0.id == .inspectionLamp }
                world.props[ti].stock = lamp
            }
            setActor("scav") { a in a.carrying = [ItemStack(.hotelBattery)]; a.errand = "stall"; a.pos = V2(Self.stallPos.x + 0.9, 52); a.route = [] }
            story.flags.insert("scav.stall")
            if world.propIndex("scav.stall") == nil { world.props.append(Prop(id: "scav.stall", kind: .thing, pos: Self.stallPos, look: "stall")) }
        }
        if s.errand == "stole" || s.errand == "done" { setActor("scav") { $0.errand = $0.errand == "stole" ? "stall.stole" : "stall" } }
    }

    var scavStallLine: String {
        guard let s = actor("scav") else { return "" }
        if s.errand.hasSuffix("stole") || remembers("scav", "keptBoth") {
            return world.prop("scav.stall")?.stock.contains { $0.id == .inspectionLamp } == true
                ? "Inspection lamp, good as new. Yours for a price. Everything’s for a price."
                : "Battery keeps the stall bright. That’s all you need to know."
        }
        if remembers("scav", "keptDeal") || remembers("scav", "maxTookLampFirst") { return "A deal’s a deal. That lamp treating you right?" }
        return "Battery keeps the stall bright. Want anything?"
    }

    public var stallHasMaxsLamp: Bool { world.prop("scav.stall")?.stock.contains { $0.id == .inspectionLamp } == true && remembers("scav", "keptBoth") }

    func buyBackLamp() {
        guard let si = world.propIndex("scav.stall") else { return }
        world.props[si].stock.removeAll { $0.id == .inspectionLamp }
        setActor("scav") { _ = $0.takeAway(.inspectionLamp) }
        if inv.add(.inspectionLamp, 1) < 1 { storage.add(.inspectionLamp, 1) }
        remember("scav", "boughtBack")
        story.step("battery", "after")
        emit(.saveNow)
    }

    // MARK: the struggle

    func struggleTick(_ dt: Double) {
        guard var s = struggle else { return }
        s.t += dt
        s.meter -= 0.2 * dt
        if prevDigFresh { s.meter += 0.11 }
        struggle = s
        let bars = Int((s.meter * 10).rounded())
        hint("Pull! " + String(repeating: "▮", count: Swift.max(0, Swift.min(10, bars))) + String(repeating: "▯", count: Swift.max(0, 10 - bars)), 0.5)
        if s.meter >= 1 { endStruggle(won: true) } else if s.meter <= 0 || s.t > 7 { endStruggle(won: s.meter >= 0.75) }
    }

    func struggleTug() {
        guard var s = struggle else { return }
        s.meter += 0.11
        struggle = s
        emit(.hammerHit)
    }

    func endStruggle(won: Bool) {
        struggle = nil
        clearHint()
        remember("scav", "fought")
        if won {
            buyBackLamp()
            remember("scav", "lostTheLamp")
            say("scav", "Fine! Take it. Don’t come back to my stall.", 3)
            setOutcome("battery", "Took the lamp back from Corvin by force.")
        } else {
            // He keeps the lamp; Max comes to by the service lift, where he knows the way.
            say("scav", "Go home, kid.", 2.4)
            max.health = Swift.max(30, max.health - 20)
            travel(to: Landmarks.hotelLift, "…")
            later(2.2) { $0.think("By the lift. My shoulder hurts. The lamp’s still on his table.", 3.4) }
            setOutcome("battery", "Lost a scuffle with Corvin over the lamp.")
        }
        story.step("battery", "after")
        emit(.saveNow)
    }
}
