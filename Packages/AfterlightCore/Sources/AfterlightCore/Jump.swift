import Foundation

/// Jump feel borrowed from the platformers people already know: coyote time, a jump buffer,
/// a short hop for a tap and a full jump for a hold, and one smaller jump in mid-air.
struct JumpState: Sendable {
    var sinceGround = 0.0      // seconds since Max last stood on something
    var buffered = 0.0         // a ▲ tap waiting to become a jump on landing
    var airJumps = 0           // used in this airtime
    var cut = false            // the hold was released: the rise was shortened
    var jumping = false
}

extension Game {
    static let coyoteTime = 0.1
    static let bufferTime = 0.13

    /// Run every walking frame. `tap` is a fresh ▲; `held` is ▲ still down.
    func jumpTick(tap: Bool, held: Bool, blocked: Bool, dt: Double) {
        if max.ground { js.sinceGround = 0; js.airJumps = 0; js.jumping = false; js.cut = false } else { js.sinceGround += dt }
        if tap && !blocked { js.buffered = Game.bufferTime }
        if js.buffered > 0 {
            js.buffered -= dt
            if max.mode == .walk && !max.swingOn && max.oneShot == nil {
                if max.ground || js.sinceGround < Game.coyoteTime {
                    jump(power: 1); js.buffered = 0
                } else if tap && js.airJumps < 1 && js.jumping {
                    js.airJumps += 1
                    jump(power: 0.82); js.buffered = 0
                    emit(.whoosh)
                }
            }
        }
        // Let go early and the jump is a hop.
        if js.jumping && !held && !js.cut && max.vy < -2 { max.vy *= 0.45; js.cut = true }
    }

    /// Takeoff. Power 1 is about a tile and a third.
    func jump(power: Double) {
        guard max.mode == .walk else { return }
        max.ground = false
        max.vy = -Tuning.jumpSpeed * power
        max.air = 0
        max.squash = Swift.max(max.squash, 0.1)
        max.crK = 0.08
        js.jumping = true
        js.cut = false
        js.sinceGround = 1
        emit(.whoosh)
        story.flags.insert("jumped")
    }

    func jump() { jump(power: 1) }
}
