import XCTest
@testable import AfterlightCore

/// Validation loops over the whole world and its content: things are where they're supposed to be,
/// everything a recipe needs can be found, and every guide arrow points somewhere Max can stand.
final class WorldValidationTests: XCTestCase {

    /// Items the story hands out rather than the world holding them.
    static let storySources: Set<ItemID> = [.greens, .trailMeal, .ration, .flashlight, .campCrate, .workbenchKit, .cotKit, .woodLadder, .torch, .lamp]

    func testEveryPropStandsOnTheFloorInOpenAir() {
        let w = WorldGen.make()
        // Things that hang, sit in walls, or are drawn over the floor on purpose.
        let skip: Set<PropKind> = [.shelterLight, .warmPipe, .lanternClue]
        for p in w.props where !skip.contains(p.kind) {
            XCTAssertFalse(w.solid(p.pos.x, p.pos.y - 0.6), "\(p.id) is buried at \(p.pos)")
            XCTAssertTrue(w.solid(p.pos.x, p.pos.y + 0.25) || w.m(Int(p.pos.x), Int(p.pos.y)) == .plank, "\(p.id) floats at \(p.pos)")
        }
    }

    func testEveryBuriedFindIsInDiggableGroundInsideTheWorld() {
        let w = WorldGen.make()
        for b in w.buried {
            let c = Int(b.pos.x), r = Int(b.pos.y)
            XCTAssertTrue(c > 0 && c < w.w - 1 && r > 0 && r < w.h - 1, "\(b.id) out of the world")
            XCTAssertFalse(w.m(c, r) == .rock || w.m(c, r) == .metal, "\(b.id) is sealed in \(w.m(c, r)) at \(b.pos)")
        }
    }

    func testEverythingARecipeNeedsCanBeFound() {
        let w = WorldGen.make()
        var found = Self.storySources
        for p in w.props { for s in p.stock { found.insert(s.id) } }
        for b in w.buried { found.insert(b.item.id) }
        // Outputs of recipes whose own inputs are all findable (repeat until nothing new).
        var changed = true
        while changed {
            changed = false
            for r in Recipes.all where r.inputs.allSatisfy({ found.contains($0.id) }) {
                if case .item(let it, _) = r.output, !found.contains(it) { found.insert(it); changed = true }
            }
        }
        for r in Recipes.all {
            for s in r.inputs { XCTAssertTrue(found.contains(s.id), "recipe \(r.id) needs \(s.id.name), which nothing in the world provides") }
        }
        // And there's enough of the scarce things for the main line: the Mara price and the chimney.
        let total: (ItemID) -> Int = { id in w.props.reduce(0) { $0 + $1.stock.filter { $0.id == id }.reduce(0) { $0 + $1.count } } + w.buried.filter { $0.item.id == id }.count }
        XCTAssertGreaterThanOrEqual(total(.rope), MaraDeal.chimneyCost.first { $0.id == .rope }!.count, "enough rope in the world to rig the chimney")
        for s in MaraDeal.price { XCTAssertGreaterThanOrEqual(total(s.id), s.count, "enough \(s.id.name) to pay Mara") }
    }

    func testEveryClimbHasOpenSpaceAlongIt() {
        let g = Game()
        g.begin()
        let w = g.world
        for c in w.climbs {
            var y = c.top + 0.4
            while y < c.bottom - 0.4 {
                // The seam over the shaft is opened in play; skip those rows.
                if c.id == Landmarks.shaftRungsID && Landmarks.hatchRows.contains(Int(y)) { y += 0.5; continue }
                XCTAssertFalse(w.solid(c.x, y), "\(c.id) runs through solid at y \(y)")
                y += 0.5
            }
        }
    }

    /// Wherever the story is, the guide arrow never points into rock.
    func testGuideArrowsPointAtOpenGround() {
        let g = Game()
        g.begin()
        g.story.flags.formUnion(["flashOn", "sawShaft"])
        g.inv.belt.append(.flashlight)
        for q in [Quest.blackout] { g.story.addQuest(q) }
        var checked = 0
        for q in g.story.quests where !q.side {
            for s in q.steps {
                if let p = g.guide {
                    XCTAssertFalse(g.world.solid(p.x, p.y), "guide for \(q.id).\(s.id) points into solid at \(p)")
                    checked += 1
                }
                g.story.step(q.id, s.id)
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
