import XCTest
@testable import AfterlightCore

/// Conversations come from data: they must load, be sound, and drive the same deals as before.
final class DialogueTests: XCTestCase {

    func testEveryGraphLoadsAndIsSound() {
        XCTAssertNotNil(Dialogue.graphs["mara"], "Mara's conversation ships with the game")
        for (id, g) in Dialogue.graphs {
            XCTAssertEqual(Dialogue.validate(g), [], "graph \(id)")
        }
    }

    func outpost() -> Game {
        let g = MaraTests().outpost(FixedClock())
        MaraTests().place(g, V2(79.6, 9))
        return g
    }

    /// First meeting: the shock, then the problem, then terms before any agreement.
    func testFirstMeetingShowsTermsBeforeAgreeing() throws {
        let g = outpost()
        XCTAssertEqual(g.context?.id, "panel:mara")
        g.performContext()
        let t = try XCTUnwrap(g.talk)
        XCTAssertEqual(t.node, "first")
        XCTAssertTrue(t.lines.first?.contains("real") ?? false)
        g.chooseTalk("alive")
        g.chooseTalk("tap")
        XCTAssertEqual(g.talk?.node, "problem")
        XCTAssertEqual(Set(g.talk?.choices.map(\.id) ?? []), ["help", "lift", "other", "think"])
        g.chooseTalk("help")
        XCTAssertEqual(g.talk?.node, "terms.water")
        XCTAssertNil(g.agreement(MaraDeal.water), "nothing is agreed by reading the terms")
        XCTAssertTrue(g.talk?.choices.first { $0.id == "agree" }?.detail?.contains("repairs your lift") ?? false)
        g.chooseTalk("agree")
        XCTAssertNotNil(g.agreement(MaraDeal.water))
        XCTAssertEqual(g.talk?.node, "agreed.water")
        g.chooseTalk("ok")
        XCTAssertNil(g.talk, "the talk ends and Max is free to move")
        XCTAssertTrue(g.maraMet)
    }

    /// Decline, walk away, come back: she remembers meeting, and the offers are still there.
    func testDeclineThenComeBack() {
        let g = outpost()
        g.performContext()
        g.chooseTalk("who"); g.chooseTalk("tap")
        g.chooseTalk("think")
        XCTAssertNil(g.talk)
        XCTAssertTrue(g.maraMet)
        XCTAssertNil(g.agreement(MaraDeal.water))
        g.startTalk("mara")
        XCTAssertEqual(g.talk?.node, "hub")
        XCTAssertTrue(g.talk?.choices.contains { $0.id == "help" } ?? false)
        XCTAssertTrue(g.talk?.choices.contains { $0.id == "lift" } ?? false)
    }

    /// Taking her spare: she brings it up, and handing it back is a choice only when Max has a valve.
    func testSpareValveConfrontation() {
        let g = outpost()
        g.story.flags.insert("mara.met")
        g.takeSpare()
        g.inv.remove(.pressureValve, 1)
        g.startTalk("mara")
        XCTAssertTrue(["spare.seen", "spare.missing"].contains(g.talk?.node ?? ""))
        let give = g.talk?.choices.first { $0.id == "give" }
        XCTAssertEqual(give?.enabled, false, "can't give back what you don't have")
        XCTAssertNotNil(give?.detail)
        g.inv.add(.pressureValve)
        g.startTalk("mara")
        g.chooseTalk("give")
        XCTAssertEqual(g.holding("mara", .pressureValve), 0)
        XCTAssertEqual(g.talk?.node, "returned")
    }
}
