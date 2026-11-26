import Foundation

extension Game {
    private func owned(_ id: ItemID) -> Int { inv.count(id) + storage.count(id) }

    /// Where the current main objective is, so the screen can point at it. Nil when nothing needs pointing at.
    public var guide: V2? {
        guard started, cine == nil else { return nil }
        let f = story.flags
        if f.contains("flashOn") && !f.contains("shelterLit") && story.chapter <= 2, let gen = world.prop("generator") {
            if f.contains("genFreed") && available(.batteryCell) == 0, let car = world.prop("liftcar"), car.stock.contains(where: { $0.id == .batteryCell }) {
                return V2(car.pos.x, car.pos.y - 1.5)
            }
            return V2(gen.pos.x, gen.pos.y - 1.5)
        }
        if story.chapter == 2, let g = chapterTwoGuide() { return g }
        return questGuide()
    }

    /// Points at wherever the main quest's next step happens.
    private func questGuide() -> V2? {
        guard let q = story.quests.first(where: { !$0.side && !$0.done }), let st = q.nextStep else { return nil }
        func at(_ id: String, _ up: Double = 1.5) -> V2? { world.prop(id).map { V2($0.pos.x, $0.pos.y - up) } }
        switch (q.id, st.id) {
        case ("homeLight", "pack"): return packedFood ? nil : at("pantry")
        case ("homeLight", _): return at("generator")
        case ("ascent", "maint"): return V2(26, 13.5)
        case ("home", "pipe"): return V2(48, 8.5)
        case ("home", "meet"): return V2(Landmarks.maraHome.x, 7.5)
        case ("home", "pump"), ("home", "water"): return at("pump")
        case ("home", "light"): return V2(55, 8.5)
        case ("far", "east"): return V2(Double(Landmarks.transit.x1) + 1, 1.5)
        case ("far", "cavern"): return V2(Double(Landmarks.loadingShaft.c0) + 1, 2.5)
        case ("far", "cell"): return at("signal")
        default: return nil
        }
    }

    private func chapterTwoGuide() -> V2? {
        let f = story.flags
        if story.isDone("ascent", "maint") || story.flags.contains("seam") && world.climbs.contains(where: { $0.id == "ladder.shaft" }) && max.pos.y < 12 { return nil }
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
