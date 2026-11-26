import Foundation

// Build 3 · The hotel and the people already busy there.

extension Game {
    func hotelTick(_ dt: Double) {}
    func hotelArrived(_ id: String, _ tag: String) {}
    func hotelContext() -> ContextAction? { nil }
    func performHotel(_ id: String) -> Bool { false }
    func hotelPanel(_ id: String) -> Panel? { nil }
    func hotelRow(_ panel: String, _ row: String) -> Bool { false }
    func hotelCan(_ what: String) -> Bool { false }
    func hotelDo(_ what: String) {}
    func hotelVars() -> [String: String] { [:] }
}

extension Game {
    var hotelLights: [(pos: V2, radius: Double)] { [] }
}
