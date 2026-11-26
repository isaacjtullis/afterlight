import XCTest
@testable import AfterlightCore

/// Build 3 · The hotel and the people already busy there.
/// Pass when: play once helping everybody and once declining; revisit and see at least three differences
/// in the world itself; quit while carrying the cart and right after the lift leaves; every item and
/// actor has exactly one location on reload.
final class CampaignBuild3Tests: XCTestCase {

    func place(_ g: Game, _ p: V2) {
        g.max.pos = p
        g.max.ground = true; g.max.vx = 0; g.max.vy = 0; g.max.mode = .walk
        g.max.digFloor = p.y
        sim(g, GameInput(), 0.3)
    }

    /// Chapter 5: Odi met, standing at her service lift.
    func atOdis() -> Game {
        let g = Game()
        g.begin()
        g.story.chapter = 5
        g.story.flags.formUnion(["flashOn", "odiRoomSeen", "answered", "mara.met"])
        g.odi.met = true
        place(g, V2(155.8, 41))
        return g
    }

    func intoHotel(_ g: Game, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(g.context?.id, "ride:hotel", file: file, line: line)
        g.performContext()
        sim(g, GameInput(), 2.5)
        XCTAssertTrue(g.inHotel, "at \(g.max.pos)", file: file, line: line)
        XCTAssertEqual(g.story.chapter, 6, file: file, line: line)
    }

    /// Everywhere an item can be: Max's pack and storage, every prop, everyone's hands, the ball in play.
    func count(_ g: Game, _ id: ItemID) -> Int {
        var n = g.inv.count(id) + g.storage.count(id)
        for p in g.world.props { n += p.stock.filter { $0.id == id }.reduce(0) { $0 + $1.count } }
        for a in g.story.cast.values { n += a.holds(id) }
        if id == .ball && g.ball != nil { n += 1 }
        return n
    }

    func outing(_ g: Game) {
        // Down the back stairs to transit and up again.
        place(g, V2(Landmarks.backstairs.x, 52))
        XCTAssertEqual(g.context?.id, "ride:transit")
        g.performContext(); sim(g, GameInput(), 2.5)
        XCTAssertLessThan(g.max.pos.x, 100)
        place(g, V2(Landmarks.transitDoor.x, 3))
        XCTAssertEqual(g.context?.id, "ride:backstairs")
        g.performContext(); sim(g, GameInput(), 2.5)
        XCTAssertTrue(g.inHotel)
    }

    func talk(_ g: Game, _ graph: String, _ choices: [String], file: StaticString = #filePath, line: UInt = #line) {
        g.startTalk(graph)
        for c in choices {
            XCTAssertTrue(g.talk?.choices.contains { $0.id == c && $0.enabled } ?? false, "\(graph): no \(c) at \(g.talk?.node ?? "-") (\(g.talk?.choices.map(\.id) ?? []))", file: file, line: line)
            g.chooseTalk(c)
        }
    }

    // MARK: getting in and climbing on

    func testBothWaysInAndEveryoneIsAlreadyAtWork() {
        let g = atOdis()
        intoHotel(g)
        XCTAssertTrue(g.story.flags.contains("odi.out"))
        XCTAssertEqual(g.odi.pos.y, 40, accuracy: 0.1, "Odi's up on the guest floor with the cart")
        XCTAssertNotNil(g.actor("ellis"))
        XCTAssertNotNil(g.actor("scav"))
        outing(g)
        XCTAssertEqual(g.outings, 1)
    }

    func testTheMainRouteNeedsNoSideJob() {
        let g = atOdis()
        intoHotel(g)
        let b = Bot(g)
        XCTAssertTrue(b.go(188.4), b.trail)
        XCTAssertEqual(g.context?.id, "x:diagram")
        g.performContext()
        XCTAssertTrue(g.story.isDone("hotel", "diagram"))
        XCTAssertTrue(b.go(247.6, timeout: 160), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 28.4 && g.max.mode == .walk }, timeout: 40, "up the exit stair")
        XCTAssertLessThan(g.max.pos.y, 28.5, b.trail)
        XCTAssertTrue(b.go(244.6), b.trail)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 12.4 && g.max.mode == .walk }, timeout: 40, "up to the gallery")
        XCTAssertLessThan(g.max.pos.y, 12.5, "in the upper gallery\n\(b.trail)")
    }

    // MARK: helping everybody

    func helpEveryone(_ g: Game) {
        // Odi's cart: offer, go down, take the low end, ease it down.
        place(g, V2(196.4, 40))
        XCTAssertEqual(g.context?.id, "panel:odi")
        talk(g, "odi", ["help"])
        place(g, V2(Landmarks.luggageX - 0.6, 52))
        for _ in 0..<3 {
            XCTAssertEqual(g.context?.id, "cart.step")
            g.performContext(); sim(g, GameInput(), 1.6)
        }
        XCTAssertEqual(g.cartState, 4)
        g.inv.add(.pipe, 1)
        talk(g, "odi", ["load"])
        XCTAssertEqual(g.cartState, 5)
        XCTAssertEqual(g.world.prop("hotel.cart")?.stock.first?.id, .pipe, "the pipe rides home on the cart")

        // Ellis: the ball from the kitchen, then a game.
        place(g, V2(208.4, 52))
        XCTAssertEqual(g.context?.id, "search:kitchen.cupboard")
        g.performContext(); sim(g, GameInput(), 0.5)
        XCTAssertEqual(g.inv.count(.ball), 1)
        place(g, V2(g.actor("ellis")!.pos.x - 0.8, 52))
        talk(g, "ellis", ["ball", "give"])
        XCTAssertEqual(g.ellisState, 1)
        XCTAssertEqual(g.inv.count(.ellisLamp), 1, "he lends his lamp for the game")
        XCTAssertEqual(count(g, .ball), 1)
        // Max scores three: run the ball east.
        for _ in 0..<3 {
            g.setBall(V2(244.6, 51.6), V2(4, 0))
            sim(g, GameInput(), 0.6)
        }
        sim(g, GameInput(), 0.5)
        XCTAssertEqual(g.ellisState, 2)
        XCTAssertNil(g.ball)
        place(g, V2(g.actor("ellis")!.pos.x - 0.8, 52))
        XCTAssertEqual(g.context?.id, "ellis.lampBack")
        g.performContext()
        XCTAssertTrue(g.remembers("ellis", "returnedLamp"))

        // Corvin: the deal, the hatch from above, the battery down together.
        place(g, V2(g.actor("scav")!.pos.x - 0.8, 52))
        talk(g, "scav", ["what", "deal"])
        let b = Bot(g)
        place(g, V2(247.6, 52))
        b.hold(GameInput(up: true), until: { g.max.pos.y < 28.4 && g.max.mode == .walk }, timeout: 40, "up the exit stair")
        XCTAssertTrue(b.go(172.9, timeout: 120), b.trail)
        XCTAssertEqual(g.context?.id, "unbar", b.trail)
        g.performContext()
        XCTAssertTrue(g.hotelHatchOpen)
        // He climbs up and takes the battery to the freight cage.
        var k = 0
        while g.scavState != "atLift" && k < 3000 { sim(g, GameInput(), 0.1); k += 1 }
        XCTAssertEqual(g.scavState, "atLift", "Corvin at \(g.actor("scav")!.pos)")
        XCTAssertEqual(count(g, .hotelBattery), 1)
        place(g, V2(Landmarks.freightTop.x + 0.2, 28))
        talk(g, "scav", ["ride"])
        sim(g, GameInput(), 2.5)
        XCTAssertEqual(g.max.pos.y, 52, accuracy: 0.1, "rode down with him")
        XCTAssertEqual(g.inv.count(.inspectionLamp), 1, "the promised lamp")
        XCTAssertEqual(g.actor("scav")?.holds(.hotelBattery), 1, "his promised battery")
    }

    func testHelpingEverybodyAndWhatALaterVisitShows() throws {
        let g = atOdis()
        intoHotel(g)
        helpEveryone(g)
        for id in [ItemID.hotelBattery, .inspectionLamp, .ball, .ellisLamp, .pipe] { XCTAssertLessThanOrEqual(count(g, id), 1, "\(id)") }
        outing(g)
        sim(g, GameInput(), 20)
        // 1. Odi uses the cart she actually got: the intact one, brass rail and all, in her room.
        XCTAssertEqual(g.world.prop("hotel.cart")?.look, "cart")
        XCTAssertGreaterThan(g.world.prop("hotel.cart")!.pos.x, 146)
        // 2. Corvin's stall is lit by the battery, and he owns up to the deal.
        XCTAssertNotNil(g.world.prop("scav.stall"))
        place(g, V2(Game.stallPos.x + 1.6, 52))
        g.startTalk("scav")
        XCTAssertTrue(g.talk?.lines.first?.contains("deal’s a deal") ?? false, "\(g.talk?.lines ?? [])")
        g.endTalk()
        // 3. Ellis knows him: no kids playing alone, a familiar face.
        XCTAssertNil(g.actor("kid1"))
        XCTAssertTrue(g.remembers("ellis", "playedBall"))
        // Reload: one of everything, everyone in one place.
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        for id in [ItemID.hotelBattery, .inspectionLamp, .pipe] { XCTAssertEqual(count(back, id), count(g, id), "\(id)") }
        XCTAssertEqual(back.story.cast.count, g.story.cast.count)
        for (id, a) in g.story.cast { XCTAssertEqual(back.actor(id)?.pos, a.pos, id) }
    }

    // MARK: walking past everybody

    func testWalkingPastEverybodyAndWhatALaterVisitShows() {
        let g = atOdis()
        intoHotel(g)
        // See each of them once (a first chance at every mission), then do nothing.
        place(g, V2(194.0, 40)); sim(g, GameInput(), 0.3)
        place(g, V2(222.0, 52)); sim(g, GameInput(), 0.3)
        place(g, V2(194.0, 52)); sim(g, GameInput(), 0.3)
        talk(g, "scav", ["no"])
        XCTAssertTrue(g.story.flags.contains("cart.seen") && g.story.flags.contains("ellis.seen") && g.story.flags.contains("scav.seen"))
        // Max opens the hatch for his own reasons on the way to the gallery.
        g.unbarHatch()
        outing(g)
        // 1. Odi has stripped the wheels and is building a smaller cart in the lobby.
        XCTAssertEqual(g.cartState, 10)
        XCTAssertEqual(g.world.prop("hotel.cart")?.look, "cartStripped")
        XCTAssertNotNil(g.world.prop("hotel.handcart"))
        // 2. Ellis cleared one end; two kids with coats for goalposts.
        XCTAssertEqual(g.ellisState, 3)
        XCTAssertNotNil(g.actor("kid1")); XCTAssertNotNil(g.actor("kid2"))
        XCTAssertNotNil(g.world.prop("coats"))
        // 3. Corvin found his own way up: the battery powers his stall.
        XCTAssertEqual(g.world.prop("hotel.battery")?.stock.isEmpty, true)
        XCTAssertEqual(g.actor("scav")?.holds(.hotelBattery), 1)
        XCTAssertNotNil(g.world.prop("scav.stall"))
        XCTAssertEqual(count(g, .hotelBattery), 1)
        // Max can still join the kids.
        place(g, V2(g.actor("kid1")!.pos.x + 0.5, 52))
        XCTAssertEqual(g.context?.id, "ellis.join")
        // And meeting Odi halfway finishes the smaller cart.
        place(g, V2(g.odi.pos.x + 0.8, 52))
        talk(g, "odi", ["finish"])
        XCTAssertEqual(g.cartState, 11)
        XCTAssertEqual(g.world.prop("hotel.handcart")?.look, "handcart")
    }

    // MARK: betrayal, and a fair way to lose

    func corvinAtTheLift() -> Game {
        let g = atOdis()
        intoHotel(g)
        place(g, V2(g.actor("scav")!.pos.x - 0.8, 52))
        talk(g, "scav", ["what", "deal"])
        g.unbarHatch()
        var k = 0
        while g.scavState != "atLift" && k < 3000 { sim(g, GameInput(), 0.1); k += 1 }
        XCTAssertEqual(g.scavState, "atLift")
        place(g, V2(Landmarks.freightTop.x + 0.2, 28))
        return g
    }

    func testTheSplitShowsWhoControlsTheLoad() {
        let g = corvinAtTheLift()
        g.startTalk("scav")
        XCTAssertEqual(g.talk?.node, "split")
        XCTAssertTrue(g.talk?.lines.joined().contains("lever") ?? false, "the player sees who'll be at the lever")
        XCTAssertTrue(g.talk?.choices.first { $0.id == "trust" }?.detail?.contains("controls") ?? false)
    }

    func testQuitRightAfterTheLiftLeavesWithEverything() throws {
        let g = corvinAtTheLift()
        talk(g, "scav", ["trust"])
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(count(back, .inspectionLamp), 1)
        XCTAssertEqual(count(back, .hotelBattery), 1)
        XCTAssertEqual(back.world.prop("scav.stall")?.stock.contains { $0.id == .inspectionLamp }, true, "he took only what was on the trolley he controlled")
        XCTAssertEqual(back.actor("scav")?.pos.y ?? 0, 52, accuracy: 0.1, "he's at the bottom")
        XCTAssertEqual(back.world.prop("hotel.trolley")?.stock.isEmpty, true, "the cage came back empty")
        // Later: the lamp's for sale on his stall.
        place(back, V2(Landmarks.freightTop.x - 1.2, 28))
        back.performContext()
        sim(back, GameInput(), 2.5)
        let b = Bot(back)
        b.go(195.0, timeout: 160)
        outing(back)
        sim(back, GameInput(), 2)
        XCTAssertTrue(back.stallHasMaxsLamp, "the inspection lamp is on sale")
        XCTAssertEqual(count(back, .inspectionLamp), 1)
    }

    func confronting() -> Game {
        let g = corvinAtTheLift()
        talk(g, "scav", ["trust"])
        outing(g)
        place(g, V2(Game.stallPos.x + 1.6, 52))
        g.startTalk("scav")
        XCTAssertEqual(g.talk?.node, "stolen")
        g.chooseTalk("confront")
        XCTAssertNotNil(g.struggle)
        return g
    }

    func testWinningTheStruggleGetsTheLampBack() {
        let g = confronting()
        var k = 0
        while g.struggle != nil && k < 400 {
            g.update(dt: 1 / 60, input: GameInput(dig: k % 6 < 3)); _ = g.drainEvents(); k += 1
        }
        XCTAssertNil(g.struggle)
        XCTAssertEqual(g.inv.count(.inspectionLamp), 1)
        XCTAssertEqual(count(g, .inspectionLamp), 1)
    }

    func testLosingTheStruggleCostsTheLampAndLeavesMaxAtTheLift() {
        let g = confronting()
        sim(g, GameInput(), 8)
        XCTAssertNil(g.struggle)
        sim(g, GameInput(), 2)
        XCTAssertEqual(g.inv.count(.inspectionLamp), 0)
        XCTAssertTrue(g.stallHasMaxsLamp)
        XCTAssertEqual(g.max.pos.x, Landmarks.hotelLift.x, accuracy: 0.2, "a known landing")
        XCTAssertEqual(count(g, .inspectionLamp), 1)
    }

    func testClosingTheAppPausesTheConfrontation() throws {
        let g = confronting()
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertNil(back.struggle, "nothing resolves while the app is closed")
        XCTAssertTrue(back.stallHasMaxsLamp)
    }

    // MARK: quitting mid-carry

    func testQuitWhileCarryingTheCartAndPickItUpAgain() throws {
        let g = atOdis()
        intoHotel(g)
        place(g, V2(196.4, 40))
        talk(g, "odi", ["help"])
        place(g, V2(Landmarks.luggageX - 0.6, 52))
        g.performContext(); sim(g, GameInput(), 1.6)
        XCTAssertEqual(g.cartState, 2)
        let cartAt = g.world.prop("hotel.cart")!.pos, odiAt = g.odi.pos
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(back.cartState, 2)
        XCTAssertEqual(back.world.prop("hotel.cart")?.pos, cartAt, "the cart is where they left it on the stair")
        XCTAssertEqual(back.odi.pos, odiAt)
        XCTAssertEqual(back.world.props.filter { $0.id == "hotel.cart" }.count, 1)
        place(back, V2(Landmarks.luggageX - 0.6, 52))
        XCTAssertEqual(back.context?.id, "cart.step")
        back.performContext(); sim(back, GameInput(), 1.6)
        back.performContext(); sim(back, GameInput(), 1.6)
        XCTAssertEqual(back.cartState, 4)
    }

    func testTheExchangesAreStaged() {
        let g = atOdis()
        intoHotel(g)
        // The breakfast card with Mara.
        XCTAssertTrue(g.story.flags.contains("mara.visiting"))
        place(g, V2(182.6, 52))
        XCTAssertEqual(g.context?.id, "x:desk")
        g.performContext()
        XCTAssertEqual(g.talk?.graph, "x.breakfast")
        talk(g, "x.breakfast", ["pay", "yes", "would", "ok"])
        XCTAssertTrue(g.remembers("mara", "breakfastTalk"))
        XCTAssertEqual(g.inv.count(.breakfastCard), 1)
        // Every graph is sound.
        for (id, gr) in Dialogue.graphs { XCTAssertEqual(Dialogue.validate(gr), [], id) }
    }
}
