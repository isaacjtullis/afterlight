import Foundation

public struct GameInput: Equatable, Sendable {
    public var dx = 0
    public var up = false
    public var down = false
    public var dig = false
    /// The UP dig button: swing overhead.
    public var digUp = false
    /// The wheel pushed past its ring: run.
    public var run = false
    /// The wheel pulled down: climb down a ladder or rungs, or aim DIG down.
    public var climbDown = false
    /// The JUMP button.
    public var jump = false
    public init(dx: Int = 0, up: Bool = false, down: Bool = false, dig: Bool = false, digUp: Bool = false, run: Bool = false, climbDown: Bool = false, jump: Bool = false) {
        self.dx = dx; self.up = up; self.down = down; self.dig = dig; self.digUp = digUp; self.run = run; self.climbDown = climbDown; self.jump = jump
    }
    var any: Bool { dx != 0 || up || down || dig || digUp || jump }
}

/// Things that happened this frame, for sound, haptics, particles and UI.
public enum GameEvent: Equatable, Sendable {
    case bite(at: V2, kind: SwingKind, carved: Bool, face: Int)
    case clank(at: V2)
    case whoosh
    case step
    case land(speed: Double)
    case pour(at: V2)
    case reveal(at: V2)
    case pickup(String)
    case chime
    case breakthrough(at: V2)
    case flashOn
    case swell
    case knock
    case spark(at: V2)
    case chapter(Int, String)
    case openSheet(Sheet)
    case conversation(String)
    case placed(String)
    case wood(Int)
    case climbStep
    case hammerHit
    case panel(String)
    case checkpoint(Checkpoint)
    /// Max lies down: the app plays the sleep (Zs, the clock spinning) while he recovers.
    case sleep
    case saveNow
}

public enum Sheet: String, Sendable { case workbench, storage, pack, journal, mission, camp, map, pantry, loot, checkpoints }

/// One contextual action shown near the work.
public struct ContextAction: Equatable, Sendable {
    public var id: String
    public var label: String
    public var anchor: V2
    public var prominent: Bool
}

/// A loose item popping out of the ground, waiting to be picked up.
public struct Drop: Codable, Sendable {
    public var item: ItemStack
    public var pos: V2
    public var vy: Double
    public var t: Double
}

public struct Cinematic: Sendable {
    public var kind: String
    public var t = 0.0
    public var beat = 0
    /// Where the camera should look, if anywhere special.
    public var focus: V2? = nil
    public var focusWeight = 0.0
}

/// The live, player-ordered dig ("Max, dig to here").
public struct DigOrder: Sendable {
    public var dir: Int
    public var target: Int
}

public struct OrderPreview: Sendable {
    public var dir: Int
    public var face: Int        // first column with earth
    public var reach: Int       // last column Max can clear before he tires
    public var blockedAt: Int?  // bedrock or steel
    public var floorRow: Int
}

public final class Game {
    public let world: World
    public var max = Max()
    public var inv = Inventory()
    public var storage = Storage()
    public var story = Story()
    public var quarters = Quarters()
    /// Odi waits for a later chapter, far along the cavern.
    public var odi = NPCState(id: "odi", pos: V2(140, 41))
    public var mara = NPCState(id: "mara", pos: Landmarks.maraHome)
    public var drops: [Drop] = []

    public internal(set) var time = 0.0
    public var started = false
    public var candle = 0.0
    public var ambient = 0.0          // cave light once broken through
    /// Flashlight battery, 0…100.
    public var battery = 100.0
    public var flicker = 0.0

    public var thoughtText = "", thoughtT = 0.0
    public var hintText = "", hintT = 0.0
    public var speechWho = "", speechText = "", speechT = 0.0
    var jobTickT = 0.0

    public var order: DigOrder? = nil
    public var planning: OrderPreview? = nil
    public var cine: Cinematic? = nil
    public var context: ContextAction? = nil
    public var pinnedRecipe: String? = nil
    /// The camp crate whose sheet is open.
    public var openCamp: String? = nil
    /// The app shows a loot list for lockers and wrecks; tests and jobs take everything at once.
    public var lootUI = false
    /// The item Max is about to set down (a torch, a lantern, a ladder…), or nil.
    public var placing: ItemID? = nil
    public var openLoot: String? = nil

    public var appliedJobs: Set<String> = []
    public var activeJob: JobRecord? = nil
    public var lastReport: JobReport? = nil

    /// Injected clock so jobs and crops use real time (and tests can fake it).
    public var clock: () -> Date = { Date() }

    var events: [GameEvent] = []
    var timers: [(at: Double, fn: (Game) -> Void)] = []
    var prev = GameInput()
    var clankAt = -99.0
    // A quick tap still does something: a short step, or one full swing of the shovel.
    var digLatch = false, downLatch = false, latchT = 0.0
    var walkHold = 0.0, walkHoldDir = 0
    var runWanted = false
    var js = JumpState()
    // Holding the wheel up or down for a moment takes hold of a climb; a brush doesn't.
    var upHeld = 0.0, downHeld = 0.0
    var climbCooldown = 0.0
    /// After stepping off a climb, ▲ must be let go before Max grabs another one.
    var needUpRelease = false
    // Never stuck: pushing at something soft for a moment clears a way through it.
    var stuckT = 0.0, stuckX = 0.0
    /// Trying to move and getting nowhere (a pit, a dead end): after a few seconds Max offers to climb out.
    var trapT = 0.0, trapAnchor = V2(0, 0), trapTried: Set<Int> = []
    public var trapped = false

    /// Saves made before the cavern moved away from home don't carry this flag.
    public static let worldVersionFlag = "world2"
    /// Rows from here down were rebuilt when the cavern moved.
    public static let reworkTopRow = 12

    public init(world: World = WorldGen.make()) {
        self.world = world
        story.addQuest(.blackout)
        story.flags.insert(Game.worldVersionFlag)
        story.flags.insert("finds1")
        story.flags.insert("world3")
        story.flags.insert("gen1")
        story.flags.insert("tape1")
    }

    public func drainEvents() -> [GameEvent] { defer { events.removeAll() }; return events }
    func emit(_ e: GameEvent) { events.append(e) }
    func later(_ s: Double, _ fn: @escaping (Game) -> Void) { timers.append((time + s, fn)) }

    public func think(_ s: String, _ d: Double = 3.2) { thoughtText = s; thoughtT = d }
    public func hint(_ s: String, _ d: Double = 6) { hintText = s; hintT = d }
    public func clearHint() { hintT = 0 }

    public func begin() {
        started = true
        later(1.4) { $0.think("Power’s out. Just the candle now.", 3.4) }
    }

    /// Home is the workshop, the shaft and the maintenance room: crafting pulls from storage here.
    public var atHome: Bool {
        let p = max.pos
        return (p.x > 18.5 && p.x < 36 && p.y > 3 && p.y < 31.5)
    }

    // MARK: frame

    public func update(dt rawDt: Double, input: GameInput) {
        let dt = Swift.min(rawDt, 1.0 / 30.0)
        time += dt
        let due = timers.filter { $0.at <= time }
        timers.removeAll { $0.at <= time }
        for t in due { t.fn(self) }
        if thoughtT > 0 { thoughtT -= dt }
        if hintT > 0 { hintT -= dt }
        if !story.checkpoints.isEmpty { for c in story.checkpoints { emit(.checkpoint(c)) }; story.checkpoints.removeAll() }
        if speechT > 0 { speechT -= dt }
        jobTickT += dt
        if jobTickT >= 0.5 { jobTickT = 0; if !story.coop.jobs.isEmpty { advanceSharedJobs(to: clock()) }; quartersTick(now: clock()) }
        if started { candle = Swift.min(1, candle + dt * 0.8) }
        flicker = Swift.max(0, flicker - dt * 0.5)
        if story.flags.contains("broke") { ambient = Swift.min(1, ambient + dt * 0.25) }

        let fresh = (dig: input.dig && !prev.dig, down: input.down && !prev.down, up: input.up && !prev.up)
        let freshDx = input.dx != 0 && input.dx != prev.dx
        if order != nil && input.any && !prev.any { stopOrder("player") }
        let freshDigUp = input.digUp && !prev.digUp
        let freshJump = input.jump && !prev.jump
        prev = input
        let prePos = max.pos
        defer { smoothSnaps(from: prePos) }

        // Taps: a quick press on an arrow still takes a short step; a quick DIG still lands one swing.
        var input = input
        if input.climbDown && max.mode == .climb { input.down = true }
        runWanted = input.run
        if freshDx { walkHold = 0.16; walkHoldDir = input.dx }
        walkHold = Swift.max(0, walkHold - dt)
        if input.dx == 0 && walkHold > 0 && max.mode == .walk { input.dx = walkHoldDir }
        if fresh.dig { digLatch = true; latchT = 0 }
        if fresh.down && max.mode == .walk && max.ground { downLatch = true; latchT = 0 }
        if digLatch || downLatch {
            latchT += dt
            if latchT > 0.7 { digLatch = false; downLatch = false }
        }
        if digLatch && !input.dig { input.dig = true }
        if downLatch && !input.down { input.down = true }

        var dir = 0
        var swingWanted: SwingKind? = nil

        if cine != nil {
            dir = cineTick(dt)
        } else if max.busy > 0 {
            max.busy -= dt
        } else if planning != nil || max.oneShot != nil {
            // waiting
        } else if order != nil {
            (dir, swingWanted) = orderTick()
        } else if started {
            if max.mode == .climb {
                climbTick(dt, input: input, freshDig: fresh.dig || freshDigUp)
                updateFeel(dt)
                pickupsTick(dt)
                storyTick(dt)
                return
            }
            dir = input.dx
            if dir != 0 { story.flags.insert("moved"); max.face = dir }
            if !input.up { needUpRelease = false }
            upHeld = input.up && !needUpRelease ? upHeld + dt : 0
            downHeld = (input.climbDown && !input.dig) ? downHeld + dt : 0
            climbCooldown = Swift.max(0, climbCooldown - dt)
            // Take hold of a ladder or rungs only on a deliberate hold of the wheel, never mid-dig.
            if climbCooldown <= 0 && !input.dig && (upHeld > 0.14 || downHeld > 0.14) && tryEnterClimb(up: upHeld > 0.14) {
                updateFeel(dt); storyTick(dt); return
            }
            // Footholds only up earth too tall to jump, and only after holding the wheel up against it.
            var climbed = false
            if upHeld > 0.3 && !input.dig && max.ground && max.oneShot == nil && climbCooldown <= 0 {
                climbed = tryFoothold(dir: max.face)
                if !climbed && wallBeside(max.face) { climbed = tryFoothold(dir: -max.face) }
            }
            jumpTick(tap: freshJump, held: input.jump, blocked: climbed, dt: dt)
            // One DIG button: the wheel aims it. Up digs overhead, down digs the floor, otherwise straight ahead.
            let aimUp = input.up || input.digUp
            let aimDown = input.climbDown || (input.down && !input.dig)
            if (input.dig && aimUp) || input.digUp {
                if !climbed { swingWanted = .up }
            } else if aimDown && (input.dig || input.down) && max.ground {
                let below = V2(max.pos.x, max.pos.y + 0.25)
                if world.hardAt(below.x, below.y) {
                    if fresh.dig || fresh.down { startOneShot(.clankDown, at: V2(max.pos.x, max.pos.y + 0.05)) }
                } else if world.solid(below.x, below.y) || buriedBelow() != nil {
                    swingWanted = .down
                }
            } else if input.dig {
                if let pr = frontProbe(max.face) {
                    if !pr.hard { swingWanted = .side } else if pr.d < 0.45 && fresh.dig { startOneShot(.clank, at: pr.point) }
                } else if fresh.dig { startOneShot(.air, at: nil) }
            }
        }

        oneShotTick(dt)
        if let sw = swingWanted {
            dir = swingTick(dt, kind: sw)
        } else if max.swingOn {
            max.swing += dt / Tuning.swingPeriod
            if max.swing >= 1 { max.swingOn = false; max.swing = 0 }
        }
        physics(dir: dir, dt: dt)
        unstick(dir: dir, dt: dt)
        trapCheck(input, dt: dt)
        updateFeel(dt)
        if !max.swingOn && max.oneShot == nil {
            max.restT += dt
            // Catching his breath brings stamina back; an empty belly slows it down.
            let regen = Tuning.restRegen * (max.hunger < 20 ? 0.35 : 1)
            if max.restT > 0.9 && order == nil && max.stamina < max.staminaMax { max.stamina = Swift.min(max.staminaMax, max.stamina + regen * dt) }
        }
        pickupsTick(dt)
        survivalTick(dt)
        aimTick(dt, lookUp: input.up && max.mode == .walk, input: input)
        odiTick(dt)
        maraTick(dt)
        storyTick(dt)
        context = computeContext()
    }

    func aimTick(_ dt: Double, lookUp: Bool, input: GameInput = GameInput()) {
        guard cine == nil else { return }
        let idle = abs(max.vx) < 0.25 && !max.swingOn
        let want = (lookUp || (story.flags.contains("sawShaft") && underShaft && idle && planning == nil && order == nil)) ? 1.0 : 0.0
        max.lookUp = damp(max.lookUp, want, 6, dt)
        // The beam follows the wheel: up, down, or the diagonals between.
        let down = input.climbDown && max.mode == .walk
        var target = lerpD(0.05, -1.45, max.lookUp)
        if lookUp && input.dx != 0 { target = -0.75 }
        if down { target = input.dx != 0 ? 0.6 : 1.15 }
        max.beamA = damp(max.beamA, target + sin(max.phase * 2) * 0.025 * max.walkAmp, 9, dt)
        if inv.has(.flashlight) { max.flashI = damp(max.flashI, flashlightLit ? 1 : 0, 18, dt) }
    }

    public var underShaft: Bool { max.pos.x > 24.7 && max.pos.x < 27.3 && abs(max.pos.y - 30) < 0.5 }
    public var nearBench: Bool { abs(max.pos.x - Landmarks.bench.x) < 1.7 && abs(max.pos.y - 30) < 0.5 }

    // MARK: pickups

    func pickupsTick(_ dt: Double) {
        for i in drops.indices.reversed() {
            var d = drops[i]
            d.t += dt
            d.vy += 14 * dt
            d.pos.y += d.vy * dt
            if let g = world.groundY(d.pos.x, from: d.pos.y - 0.6, to: d.pos.y + 0.3), d.pos.y > g - 0.35, d.vy > 0 {
                d.pos.y = g - 0.35; d.vy = -d.vy * 0.3
            }
            drops[i] = d
            if d.t > 0.45 && abs(max.pos.x - d.pos.x) < 1.1 && abs(max.pos.y - 1 - d.pos.y) < 2 {
                let added = inv.add(d.item.id, d.item.count)
                if added > 0 {
                    drops.remove(at: i)
                    emit(.chime); emit(.pickup(d.item.id.name))
                    onPickup(d.item.id)
                } else if Int(time * 2) % 6 == 0 {
                    think("My pack’s full.", 1.6)
                }
            }
        }
    }

    // MARK: inventory helpers

    /// Count available for crafting: backpack, plus storage when at home.
    public func available(_ id: ItemID) -> Int { inv.count(id) + (atHome ? storage.count(id) : 0) }

    @discardableResult
    func consume(_ id: ItemID, _ n: Int) -> Bool {
        guard available(id) >= n else { return false }
        let fromPack = Swift.min(n, inv.count(id))
        if fromPack > 0 { inv.remove(id, fromPack) }
        if n - fromPack > 0 { storage.remove(id, n - fromPack) }
        return true
    }

    public func canCraft(_ r: Recipe) -> Bool {
        if case .tool(let t) = r.output, inv.has(t) { return false }
        if case .upgrade(let u) = r.output, !upgradeOpen(u) { return false }
        return woodAvailable >= r.wood && r.inputs.allSatisfy { available($0.id) >= $0.count }
    }

    public var knownRecipes: [Recipe] { Recipes.all.filter { story.flags.contains($0.unlockFlag) } }

    public func craft(_ id: String) {
        guard let r = Recipes.all.first(where: { $0.id == id }), canCraft(r), buildBlocker(r) == nil else { return }
        for i in r.inputs { consume(i.id, i.count) }
        let fromBag = Swift.min(inv.wood, r.wood)
        inv.wood -= fromBag
        storage.wood -= r.wood - fromBag
        switch r.output {
        case .tool(let t):
            inv.belt.append(t)
        case .item(let it, let n):
            let added = inv.add(it, n)
            if added < n { storage.add(it, n - added) }
        case .upgrade(let u):
            applyUpgrade(u)
        }
        if pinnedRecipe == id { pinnedRecipe = nil }
        emit(.chime)
        onCrafted(id)
        emit(.saveNow)
    }

    public func depositAll() {
        for i in inv.slots.indices {
            if let s = inv.slots[i] { storage.add(s.id, s.count); inv.slots[i] = nil }
        }
        emit(.saveNow)
    }

    public func take(_ id: ItemID, _ n: Int = 1) {
        let k = Swift.min(n, storage.count(id), inv.room(for: id))
        guard k > 0 else { return }
        storage.remove(id, k); inv.add(id, k)
    }
}
