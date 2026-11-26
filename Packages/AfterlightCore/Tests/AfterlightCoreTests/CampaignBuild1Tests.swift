import XCTest
@testable import AfterlightCore

/// Build 1 · A shelter and somewhere to go.
final class CampaignBuild1Tests: XCTestCase {

    func fetchReady() -> (Game, JobPlan) {
        let g = Game()
        g.story.flags.formUnion(["firstCup", "foundStore", "walkedStore"])
        let plan = g.availableJobs().first { $0.title.contains("water can") }
        XCTAssertNotNil(plan, "the fetch job is on offer once Max has walked the route")
        return (g, plan!)
    }

    func locations(_ g: Game, _ id: ItemID) -> Int {
        g.inv.count(id) + g.storage.count(id) + g.world.props.reduce(0) { $0 + $1.stock.filter { $0.id == id }.reduce(0) { $0 + $1.count } }
    }

    func testFetchJobNotOfferedBeforeTheRouteIsWalked() {
        let g = Game()
        g.story.flags.insert("firstCup")
        XCTAssertNil(g.availableJobs().first { $0.title.contains("water can") })
    }

    func testCalledBackMidwayMaxHasTheCanAtTheStore() throws {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let (g, plan) = fetchReady()
        g.clock = { now }
        g.startJob(plan, startedAt: now)
        now = now.addingTimeInterval(470)   // there, and the can is off the shelf
        let r = g.resolveLocally(recalled: true)
        XCTAssertEqual(r?.completed, 2)
        XCTAssertEqual(g.inv.count(.waterCan), 1)
        XCTAssertFalse(g.world.prop("store.shelf")!.stock.contains { $0.id == .waterCan })
        XCTAssertGreaterThan(g.max.pos.y, 40, "he's down at the store")
        XCTAssertEqual(locations(g, .waterCan), 1)
        // And it survives a reload in exactly one place.
        let back = Game.load(try Game.decodeSave(try g.encodeSave()))
        XCTAssertEqual(locations(back, .waterCan), 1)
        XCTAssertEqual(back.inv.count(.waterCan), 1)
        XCTAssertNil(back.availableJobs().first { $0.title.contains("water can") }, "nothing to fetch twice")
    }

    func testTheWholeFetchBringsItHome() {
        var now = Date(timeIntervalSince1970: 1_000_000)
        let (g, plan) = fetchReady()
        g.clock = { now }
        g.startJob(plan, startedAt: now)
        now = now.addingTimeInterval(2000)
        let r = g.resolveLocally(recalled: false)
        XCTAssertEqual(r?.completed, 4)
        XCTAssertEqual(g.storage.count(.waterCan), 1)
        XCTAssertEqual(g.inv.count(.waterCan), 0)
        XCTAssertEqual(locations(g, .waterCan), 1)
        XCTAssertTrue(g.atHome)
    }

    func testOldGeneratorSaveKeepsLightsInventoryAndAreas() throws {
        let g = Game()
        // An old save: past the generator, before the water mission existed.
        g.story.quests.removeAll { $0.id == "drum" }
        g.story.flags.formUnion(["shelterLit", "flashOn", "ch2Done"])
        g.story.chapter = 3
        g.story.flags.subtract(["storeB1", "tape1"])
        g.inv.add(.copperOre, 3)
        g.storage.add(.wire, 4)
        var save = g.makeSave()
        save.quarters = nil
        save.hydration = nil
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let back = Game.load(try Game.decodeSave(try e.encode(save)))
        XCTAssertTrue(back.story.flags.contains("shelterLit"))
        XCTAssertEqual(back.story.chapter, 3)
        XCTAssertEqual(back.inv.count(.copperOre), 3)
        XCTAssertEqual(back.storage.count(.wire), 4)
        XCTAssertTrue(back.quarters.drumSealed && back.quarters.filterFitted, "old homes already had water")
        XCTAssertFalse(back.waterQuestActive)
    }
}
