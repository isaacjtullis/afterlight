import Foundation

extension Game {
    /// A hop: about a tile and a third straight up, carrying whatever speed Max had.
    func jump() {
        guard max.ground, max.mode == .walk else { return }
        max.ground = false
        max.vy = -Tuning.jumpSpeed
        max.air = 0
        max.squash = Swift.max(max.squash, 0.1)
        max.crK = 0.08
        emit(.whoosh)
        story.flags.insert("jumped")
    }
}
