import Foundation

extension Game {
    private func owned(_ id: ItemID) -> Int { inv.count(id) + storage.count(id) }

    /// Where the current main objective is, so the screen can point at it. Nil when nothing needs pointing at.
    public var guide: V2? {
        guard started, cine == nil, story.chapter == 2 else { return nil }
        let f = story.flags
        let ladderIn = world.climbs.contains { $0.id == "ladder.shaft" }
        let hasPick = inv.has(.shortPick)
        if !hasPick && owned(.liftTooth) == 0 {
            guard let car = world.prop("liftcar"), !car.stock.isEmpty else { return nil }
            if !f.contains("broke") { return V2(Double(Landmarks.caveStart) - 0.5, 29) }
            return V2(car.pos.x, car.pos.y - 1.5)
        }
        if !hasPick && owned(.spareGrip) == 0, let locker = world.prop("locker.ws"), locker.stock.contains(where: { $0.id == .spareGrip }) {
            return V2(locker.pos.x, locker.pos.y - 1.5)
        }
        if !hasPick || (!ladderIn && owned(.ladderSection) == 0) { return V2(Landmarks.bench.x, 28.5) }
        if !ladderIn { return V2(26, 28.5) }
        return V2(26, 13.5)
    }
}
