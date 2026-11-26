import Foundation

extension Game {
    /// Big position changes in one frame (stepping off a climb, a snap onto a lip) are smoothed for
    /// the eye: Max's drawing glides the difference away instead of jumping.
    func smoothSnaps(from p: V2) {
        let d = V2(p.x - max.pos.x, p.y - max.pos.y)
        let dt = 1.0 / 60
        // Anything moved further than its own speed explains is a snap.
        let snapX = abs(d.x) > abs(max.vx) * dt * 1.5 + 0.08
        let snapY = abs(d.y) > abs(max.vy) * dt * 1.5 + abs(max.vyG) * dt * 1.5 + 0.06
        if (snapX || snapY) && abs(d.x) + abs(d.y) < 4 && activeJob == nil {
            max.visOff = V2(max.visOff.x + d.x, max.visOff.y + d.y)
        }
    }

    /// The flashlight goes on and off; with it off, Max's candle lantern comes out of the bag.
    public func toggleFlashlight() {
        guard inv.has(.flashlight) else { return }
        // "flashOn" is the story beat (it's been switched on once); "lightOff" is just the switch.
        story.flags.insert("flashOn")
        if story.flags.contains("lightOff") { story.flags.remove("lightOff") } else { story.flags.insert("lightOff") }
        emit(.flashOn)
        emit(.saveNow)
    }

    /// The candle lantern hangs off the pack only while the flashlight is off (or not yet working).
    public var lanternOut: Bool { !flashlightLit }
    /// The beam is on right now.
    public var flashlightLit: Bool { inv.has(.flashlight) && story.flags.contains("flashOn") && !story.flags.contains("lightOff") }
}
