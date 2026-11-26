import XCTest
@testable import AfterlightCore

/// Build 4 · Give the climb consequences and finish the game.
/// Pass when: three endings from the landing, each with its own interaction and a playable aftermath,
/// written once; the landing save can be revisited; all three work with starter relationships,
/// after losing the battery.
final class CampaignBuild4Tests: XCTestCase {

    func place(_ g: Game, _ p: V2) {
        g.max.pos = p
        g.max.ground = true; g.max.vx = 0; g.max.vy = 0; g.max.mode = .walk
        g.max.digFloor = p.y
        sim(g, GameInput(), 0.3)
    }

    func events(_ g: Game, _ s: Double) -> [GameEvent] {
        var out: [GameEvent] = []
        var k = 0.0
        while k < s { g.update(dt: 1 / 60, input: GameInput()); out += g.drainEvents(); k += 1 / 60 }
        return out
    }

    /// In the hotel, at the top of the exit stair, nobody befriended.
    func hotelTop() -> Game {
        let g = Game()
        g.begin()
        g.story.chapter = 6
        g.story.flags.formUnion(["flashOn", "hotel.seen", "hotel.inside", "answered"])
        place(g, V2(244.6, 28))
        return g
    }

    func arrive(_ g: Game) -> [GameEvent] {
        let b = Bot(g)
        b.hold(GameInput(up: true), until: { g.max.pos.y < 12.4 && g.max.mode == .walk }, timeout: 40, "up to the gallery")
        XCTAssertTrue(g.inGallery, b.trail)
        return g.drainEvents() + events(g, 0.5)
    }

    /// Up to the point where the choice is open: Sela's been, an outing's passed, Wren has paid the toll.
    func choiceOpen() -> Game {
        let g = hotelTop()
        _ = arrive(g)
        if g.talk != nil { g.endTalk() }
        sim(g, GameInput(), 8)
        g.passOuting()
        sim(g, GameInput(), 0.5)
        XCTAssertTrue(g.story.flags.contains("toll.up"))
        place(g, V2(Landmarks.tollPos.x - 8, 12))
        sim(g, GameInput(), 24)
        XCTAssertTrue(g.story.flags.contains("toll.seen"))
        XCTAssertTrue(g.remembers("max", "sawWrenPay"))
        XCTAssertTrue(g.story.isDone("gallery", "toll"))
        return g
    }

    // MARK: arriving

    func testArrivalSavesAtTheLandingAndTheGalleryComesAlive() {
        let g = hotelTop()
        let ev = arrive(g)
        XCTAssertTrue(ev.contains(.landingSave), "a pinned save at the landing")
        XCTAssertEqual(g.story.chapter, 7)
        sim(g, GameInput(), 1.5)
        // Two people stop at the landing.
        XCTAssertEqual(g.talk?.graph, "x.landing")
        g.chooseTalk("far"); g.chooseTalk("me")
        XCTAssertTrue(g.remembers("wren", "maxWantsMountain"))
        // Someone from above with a part the lower pumps need, freely given.
        sim(g, GameInput(), 30)
        let s = g.actor("upper")
        XCTAssertNotNil(s)
        XCTAssertEqual(s?.holds(.regulator), 1)
        place(g, V2(s!.pos.x - 0.8, 12))
        XCTAssertEqual(g.context?.id, "sela.take")
        g.performContext()
        XCTAssertEqual(g.inv.count(.regulator), 1)
    }

    func testTheStationMapShowsTheGalleryAsItsOwnSection() {
        let g = choiceOpen()
        place(g, Landmarks.stationMapPos)
        XCTAssertEqual(g.context?.id, "panel:gallery.map")
        let p = g.panel("gallery.map")
        XCTAssertTrue(p?.lines.joined().contains("SECTION G") ?? false)
        XCTAssertTrue(p?.lines.joined().contains("Nothing below it does") ?? false)
        g.startTalk("keeper"); g.chooseTalk("how"); g.chooseTalk("hub")
        XCTAssertTrue(g.talk?.choices.contains { $0.id == "views" } ?? false, "residents disagree, and Max can hear them out")
        // And the material result shows before anything is committed.
        place(g, Landmarks.stationPos)
        let rows = g.panel("gallery.station")?.rows ?? []
        XCTAssertTrue(rows.contains { $0.id == "end.stay" && ($0.detail ?? "").contains("toll stays") })
        XCTAssertTrue(rows.contains { $0.id == "end.close" && ($0.detail ?? "").contains("walk away") })
    }

    // MARK: stay

    func testStayTakeAShiftAndWalkADeliveryThrough() throws {
        let g = choiceOpen()
        place(g, Landmarks.stationPos)
        g.choosePanel("gallery.station", "end.stay")
        let b = Bot(g)
        // Walk with Wren to the far side of the crossing.
        var k = 0
        while g.story.ending == nil && k < 120 {
            let w = g.actor("wren")!
            b.go(Swift.min(w.pos.x + 0.6, Landmarks.tollPos.x + 8), timeout: 6)
            sim(g, GameInput(), 1)
            k += 1
        }
        XCTAssertEqual(g.story.ending?.id, "stay", b.trail)
        XCTAssertFalse(g.galleryClosed, "the gallery stays open, toll and all")
        XCTAssertNotNil(g.epilogue)
        XCTAssertTrue(g.epilogue?.contains { $0.hasPrefix("You gained") } ?? false)
        XCTAssertTrue(g.epilogue?.contains { $0.hasPrefix("You gave up") } ?? false)
        g.closeEpilogue()
        XCTAssertNil(g.epilogue)
        // Playable aftermath: he can keep walking the gallery.
        XCTAssertTrue(b.go(250, timeout: 60), b.trail)
    }

    // MARK: detonate

    func testCloseTheGalleryAfterWarningEveryoneOut() throws {
        let g = choiceOpen()
        place(g, Landmarks.stationPos)
        g.choosePanel("gallery.station", "end.close")
        XCTAssertFalse(g.panel("gallery.station")?.rows.first { $0.id == "end.commit" }?.enabled ?? true, "nothing closes with people inside")
        // Warn everyone in the gallery.
        for _ in 0..<6 {
            guard let id = g.galleryPeople.first else { break }
            let a = g.actor(id)!
            place(g, V2(a.pos.x - 0.8, 12))
            XCTAssertEqual(g.context?.id, "warn:\(id)")
            g.performContext()
            sim(g, GameInput(), 70)
        }
        XCTAssertEqual(g.galleryPeople, [])
        // Walking away is still possible until the lever.
        place(g, Landmarks.stationPos)
        XCTAssertNotNil(g.panel("gallery.station")?.rows.first { $0.id == "end.walk" })
        XCTAssertTrue(g.panel("gallery.station")?.rows.first { $0.id == "end.commit" }?.enabled ?? false)
        XCTAssertNotNil(g.panel("gallery.station")?.rows.first { $0.id == "end.commit" }?.confirm, "asks before it can't be undone")
        g.choosePanel("gallery.station", "end.commit")
        sim(g, GameInput(), 9)
        XCTAssertTrue(g.galleryClosed)
        XCTAssertTrue(g.world.solid(290, 9), "the gallery is rock now")
        XCTAssertNil(g.world.prop("gallery.door"))
        XCTAssertNil(g.story.ending, "not until he walks back through the changed landing")
        // The short return: down the gallery stair.
        place(g, V2(244.6, 12))
        let b = Bot(g)
        b.hold(GameInput(climbDown: true), until: { g.max.pos.y > 27.5 }, timeout: 30, "down from the landing")
        sim(g, GameInput(), 0.5)
        XCTAssertEqual(g.story.ending?.id, "detonate", b.trail)
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertTrue(back.galleryClosed)
        XCTAssertTrue(back.world.solid(290, 9))
    }

    func testWalkingAwayFromTheLeverChangesNothing() {
        let g = choiceOpen()
        place(g, Landmarks.stationPos)
        g.choosePanel("gallery.station", "end.close")
        g.choosePanel("gallery.station", "end.walk")
        XCTAssertNil(g.story.counters["ending.phase"])
        XCTAssertFalse(g.galleryClosed)
        XCTAssertNil(g.story.ending)
    }

    // MARK: outside

    func testOpenTheDoorAndWalkOutUnderYourOwnControl() throws {
        let g = choiceOpen()
        place(g, Landmarks.doorPos)
        XCTAssertEqual(g.context?.id, "panel:gallery.door")
        XCTAssertNotNil(g.panel("gallery.door")?.rows.first { $0.id == "door.open" }?.confirm)
        g.choosePanel("gallery.door", "door.open")
        sim(g, GameInput(), 2)
        XCTAssertNotNil(g.outside)
        // Standing still goes nowhere: he walks it himself.
        sim(g, GameInput(), 3)
        XCTAssertEqual(g.outside?.walked ?? 1, 0, accuracy: 0.01)
        var winds = Set<Int>()
        var k = 0.0
        while g.story.ending == nil && k < 60 { g.update(dt: 1 / 30, input: GameInput(dx: 1)); _ = g.drainEvents(); winds.insert((g.outside?.wind ?? 0) > 0 ? 1 : -1); k += 1 / 30 }
        XCTAssertEqual(g.story.ending?.id, "outside")
        XCTAssertGreaterThan(g.outside?.x ?? 0, 30)
        XCTAssertEqual(winds.count, 2, "the wind changes direction")
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertNotNil(back.outside, "he's still outside after a reload")
        XCTAssertEqual(back.story.ending?.id, "outside")
    }

    // MARK: once, and the landing save

    func testTheEndingIsWrittenOnceAndTheLandingSaveStillOffersAllThree() throws {
        let g = choiceOpen()
        let landing = try g.encodeSave()        // as the app's pinned landing checkpoint would be
        place(g, Landmarks.doorPos)
        g.choosePanel("gallery.door", "door.open")
        sim(g, GameInput(), 2)
        var k = 0.0
        while g.story.ending == nil && k < 60 { g.update(dt: 1 / 30, input: GameInput(dx: 1)); _ = g.drainEvents(); k += 1 / 30 }
        let first = g.story.ending
        g.finishEnding("stay")
        XCTAssertEqual(g.story.ending, first, "written exactly once")
        // Back to the landing: nothing is chosen there, and every way is still open.
        let again = Game.load(try Game.decodeSave(landing))
        XCTAssertNil(again.story.ending)
        XCTAssertNil(again.outside)
        place(again, Landmarks.stationPos)
        XCTAssertNotNil(again.panel("gallery.station")?.rows.first { $0.id == "end.stay" })
        XCTAssertNotNil(again.panel("gallery.station")?.rows.first { $0.id == "end.close" })
    }

    func testAllThreeWithStarterRelationshipsAfterLosingTheBattery() {
        for ending in ["stay", "close", "door"] {
            let g = choiceOpen()
            // Corvin kept everything; nobody below trusts Max much.
            g.remember("scav", "keptBoth")
            g.story.coop.trust = [:]
            switch ending {
            case "stay":
                place(g, Landmarks.stationPos); g.choosePanel("gallery.station", "end.stay")
                XCTAssertEqual(g.story.counters["ending.phase"], 10, ending)
            case "close":
                place(g, Landmarks.stationPos); g.choosePanel("gallery.station", "end.close")
                XCTAssertEqual(g.story.counters["ending.phase"], 20, ending)
            default:
                place(g, Landmarks.doorPos); g.choosePanel("gallery.door", "door.open"); sim(g, GameInput(), 2)
                XCTAssertNotNil(g.outside, ending)
            }
        }
    }
}
