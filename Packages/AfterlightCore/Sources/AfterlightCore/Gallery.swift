import Foundation

// Build 4 · The upper gallery, the toll, and the door.

public struct EndingRecord: Codable, Equatable, Sendable {
    public var id: String
    public var at: Date
    public var gained: String
    public var gaveUp: String
}

extension Game {
    func galleryTick(_ dt: Double) {}
}

extension Game {
    func galleryContext() -> ContextAction? { nil }
    func performGallery(_ id: String) -> Bool { false }
    func galleryPanel(_ id: String) -> Panel? { nil }
    func galleryRow(_ panel: String, _ row: String) -> Bool { false }
    func galleryCan(_ what: String) -> Bool { false }
    func galleryDo(_ what: String) {}
    func galleryCineTick(_ dt: Double, kind: String) -> Int { cine = nil; return 0 }
}

extension WorldGen {
    static func galleryProps() -> [Prop] { [] }
}
extension Game {
    var galleryLights: [(pos: V2, radius: Double)] { [] }
}
