import Foundation

public enum MoveMode: String, Codable, Sendable { case walk, climb }
public enum SwingKind: String, Codable, Sendable { case side, down, up }
public enum OneShotKind: String, Codable, Sendable { case air, clank, clankDown, tryUp }

/// A single swing that doesn't carve: a miss, a clank on steel, or the "try digging up" beat.
public struct OneShot: Codable, Sendable {
    public var kind: OneShotKind
    public var phase = 0          // 0 plant, 1 windup, 2 strike, 3 recover
    public var t = 0.0
    public var point: V2? = nil
}

/// Max's physical and animation state. Everything a renderer needs to draw him.
public struct Max: Codable, Sendable {
    public var pos = V2(22.6, 30)
    public var vx = 0.0, vy = 0.0, ax = 0.0
    public var face = 1
    public var ground = true
    public var mode: MoveMode = .walk
    public var climbID: String? = nil

    // feel
    public var phase = 0.0, walkAmp = 0.0, bob = 0.0, lean = 0.0, tilt = 0.0
    public var crouch = 0.0, crK = 0.0, stance = 0.07, squash = 0.0
    public var shovel = -2.2
    public var lant = 0.0, lantV = 0.0
    public var pom = 0.0, pomV = 0.0
    public var slope = 0.0, vyG = 0.0, air = 0.0
    public var sliding = false, stopping = false
    public var runT = 0.0, running = false

    // climbing: the body swings like a pendulum under the hands
    public var sway = 0.0, swayV = 0.0
    /// Drawing offset that glides away after a snap, so Max never visibly jumps.
    public var visOff = V2(0, 0)
    /// Pushing into something that won't give: stand braced instead of twitching the walk cycle.
    public var pushing = false

    // digging
    public var swing = 0.0, swingOn = false, swingKind: SwingKind = .side
    public var biteHigh = false, digFloor = 30.0
    public var oneShot: OneShot? = nil

    // body
    public var stamina = 100.0, staminaMax = 100.0, restT = 9.0, busy = 0.0

    // light
    public var lookUp = 0.0, beamA = 0.05, flashI = 0.0

    public init() {}
}

public enum Tuning {
    public static let halfWidth = 0.3
    public static let height = 1.68
    public static let walkSpeed = 3.0
    /// Hold an arrow for a moment and Max breaks into a run.
    public static let runSpeed = 5.4
    public static let runAfter = 0.55
    /// Stamina per second while running.
    public static let runCost = 3.0
    /// Takeoff speed for a jump about 1.35 tiles high.
    public static let jumpSpeed = (2.0 * 34.0 * 1.35).squareRoot()
    public static let accel = 16.0
    public static let decel = 15.0
    public static let gravity = 34.0
    public static let airGravity = 17.0
    public static let climbSpeed = 2.4
    public static let swingPeriod = 0.36
    public static let tiredSwingPeriod = 0.62
    public static let biteCost = 3.0
    /// Stamina per tile column, used by order previews. Measured from the bite loop.
    public static let columnCost = 7.0
}
