import XCTest
@testable import AfterlightCore

final class SalvageTests: XCTestCase {
    /// Every salvage wreck must rest on the cavern floor with open air above it, where Max can stand next to it.
    func testWrecksSitOnTheCavernFloorNotInsideTheEarth() {
        let w = WorldGen.make()
        for id in ["liftcar", "drill", "gantry"] {
            guard let pr = w.prop(id) else { return XCTFail("missing \(id)") }
            let c = Int(pr.pos.x), r = Int(pr.pos.y)
            XCTAssertTrue(w.m(c, r).solid, "\(id) should rest on solid ground (row \(r))")
            XCTAssertFalse(w.m(c, r - 1).solid, "\(id) should have open air above it (row \(r - 1))")
            XCTAssertGreaterThan(pr.pos.y, 20, "\(id) should be down in the cavern, not up at y=\(pr.pos.y)")
        }
    }

    /// Standing beside the lift car offers Salvage.
    func testStandingAtTheLiftCarOffersSalvage() {
        let g = Game(world: WorldGen.make())
        g.begin()
        g.story.flags.formUnion(["broke", "needPick"])
        g.story.chapter = 2
        let car = g.world.prop("liftcar")!
        g.max.pos = V2(car.pos.x + 0.6, car.pos.y)
        g.update(dt: 1.0 / 60, input: GameInput())
        XCTAssertEqual(g.context?.id, "salvage:liftcar")
        XCTAssertNotNil(g.guide)
    }
}
