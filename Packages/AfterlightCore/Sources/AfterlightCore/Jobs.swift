import Foundation

/// A job Max can carry out on his own, including while the game is closed.
/// Plans are fully worked out up front (every step's duration, stamina and effect),
/// so the server only has to count how many steps fit in the elapsed time.
public enum JobKind: String, Codable, Sendable { case dig, tend, haul }

public struct CarveOp: Codable, Equatable, Sendable {
    public var x: Double, y: Double, r: Double
    public var floorY: Double?
}

public struct JobStep: Codable, Equatable, Sendable {
    public var label: String
    public var seconds: Int
    public var stamina: Int
    public var endPos: V2
    public var carves: [CarveOp] = []
    public var tendBeds = false
    public var haulFrom: String? = nil
    public var haul: ItemStack? = nil
}

public struct JobPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var kind: JobKind
    public var title: String
    public var summary: String
    public var steps: [JobStep]
    public var staminaBudget: Int
    /// Max stops before this step and waits for the player (an opening, a person, bedrock).
    public var pauseIndex: Int?
    public var pauseReason: String?
    public var mealsPacked = 0

    public var totalSeconds: Int { steps.prefix(pauseIndex ?? steps.count).reduce(0) { $0 + $1.seconds } }
    /// How many steps Max can finish before his strength runs out, ignoring time.
    public var staminaLimitedSteps: Int {
        var s = 0, n = 0
        for (i, st) in steps.enumerated() {
            if let p = pauseIndex, i >= p { break }
            s += st.stamina
            if s > staminaBudget { break }
            n += 1
        }
        return n
    }
}

public struct JobRecord: Codable, Equatable, Sendable {
    public var plan: JobPlan
    public var startedAt: Date
    public var serverID: String? = nil
}

public struct JobReport: Codable, Equatable, Sendable {
    public var title: String
    public var lines: [String]
    public var completed: Int
    public var total: Int
    public var stopped: String
}

public enum JobResolver {
    /// Steps finished after `elapsed` seconds. Must match `public.claim_job` in Supabase exactly.
    public static func completedSteps(_ plan: JobPlan, elapsed: Double) -> Int {
        var t = 0, s = 0, n = 0
        for (i, step) in plan.steps.enumerated() {
            if let p = plan.pauseIndex, i >= p { break }
            t += step.seconds
            s += step.stamina
            if Double(t) > elapsed || s > plan.staminaBudget { break }
            n += 1
        }
        return n
    }

    public static func stopReason(_ plan: JobPlan, completed: Int, elapsed: Double, recalled: Bool) -> String {
        let limit = min(plan.pauseIndex ?? plan.steps.count, plan.staminaLimitedSteps)
        if completed >= plan.steps.count { return "Finished the whole job." }
        if completed >= limit {
            if let p = plan.pauseIndex, completed >= p { return plan.pauseReason ?? "Stopped to wait for you." }
            return "Ran out of strength. Pack a meal next time to go further."
        }
        return recalled ? "You called him back." : "Still working when you checked in."
    }
}

extension Game {

    /// Jobs on offer from the bed. Each is bounded and previewable.
    public func availableJobs(meals: Int = 0) -> [JobPlan] {
        var out: [JobPlan] = []
        let budget = 100 + meals * 40
        if story.flags.contains("ordersOK") {
            if let p = digPlan(name: "Dig the east tunnel", floorY: 30, startX: 32, dir: 1, budget: budget, meals: meals) { out.append(p) }
            if story.chapter >= 3, let p = digPlan(name: "Dig along the warm pipe", floorY: 9, startX: 35, dir: 1, budget: budget, meals: meals) { out.append(p) }
        }
        let beds = world.props(of: .planter)
        if beds.contains(where: { $0.planted != nil }) {
            let steps = (0..<6).map { i in JobStep(label: "Tend the beds", seconds: 1200, stamina: 2, endPos: V2(beds[0].pos.x, 30), tendBeds: true) }
            out.append(JobPlan(id: UUID().uuidString, kind: .tend, title: "Tend the beds",
                               summary: "Max waters and harvests every 20 minutes for two hours, and replants if there are seeds.",
                               steps: steps, staminaBudget: budget, pauseIndex: nil, pauseReason: nil, mealsPacked: meals))
        }
        for pr in world.props where [.liftCar, .drillRig, .gantry].contains(pr.kind) && !pr.stock.isEmpty && story.flags.contains("seen.\(pr.id)") {
            let steps = pr.stock.map { s in
                JobStep(label: "Haul \(s.id.name)", seconds: 600, stamina: s.id.bulky ? 9 : 5, endPos: V2(29.8, 30), haulFrom: pr.id, haul: s)
            }
            out.append(JobPlan(id: UUID().uuidString, kind: .haul, title: "Haul salvage from the \(pr.kind == .liftCar ? "lift car" : pr.kind == .drillRig ? "drill rig" : "gantry")",
                               summary: "Max carries what’s left back to workshop storage, one trip at a time.",
                               steps: steps, staminaBudget: budget, pauseIndex: nil, pauseReason: nil, mealsPacked: meals))
        }
        return out
    }

    func digPlan(name: String, floorY: Double, startX: Int, dir: Int, budget: Int, meals: Int) -> JobPlan? {
        let f = Int(floorY)
        var c = startX
        var face: Int? = nil
        for _ in 0..<120 {
            if world.m(c, f - 1).solid || world.m(c, f - 2).solid { face = c; break }
            c += dir
        }
        guard let F = face else { return nil }
        var steps: [JobStep] = []
        var pause: Int? = nil
        var reason: String? = nil
        var col = F
        while steps.count < 40 {
            let tiles = [world.m(col, f - 2), world.m(col, f - 1)]
            if tiles.contains(where: { $0.hard }) { pause = steps.count; reason = "Hit bedrock. Max waited for you."; break }
            if !tiles.contains(where: { $0.solid }) { break }
            if floorY < 10 && col >= Landmarks.outpost.door - 1 { pause = steps.count; reason = "Reached a door with a light behind it. Max waited for you."; break }
            let cx = Double(col) + 0.5
            let ops = [CarveOp(x: cx, y: floorY - 1.38, r: 0.85, floorY: floorY), CarveOp(x: cx, y: floorY - 0.55, r: 0.85, floorY: floorY)]
            steps.append(JobStep(label: "Dig", seconds: 300, stamina: Int(Tuning.columnCost), endPos: V2(cx - Double(dir) * 0.9, floorY), carves: ops))
            // an unfamiliar opening beyond this column? stop and let the player look first
            let next = [world.m(col + dir, f - 2), world.m(col + dir, f - 1)]
            if next.contains(where: { $0 == .air }) && world.bd(col + dir, f - 1) == .open { pause = steps.count; reason = "Broke into open air. Max waited at the edge for you."; break }
            col += dir
        }
        guard !steps.isEmpty else { return nil }
        var plan = JobPlan(id: UUID().uuidString, kind: .dig, title: name, summary: "", steps: steps,
                           staminaBudget: budget, pauseIndex: pause, pauseReason: reason, mealsPacked: meals)
        let n = plan.staminaLimitedSteps
        plan.summary = "Max digs \(n) of \(steps.count) tiles before he tires (about \(Int(Double(steps.prefix(n).reduce(0) { $0 + $1.seconds }) / 60)) min)." + (reason != nil && pause! <= n ? " Then he stops and waits." : "")
        return plan
    }

    /// Start a job now. The caller registers it with Supabase if online and passes the server id.
    public func startJob(_ plan: JobPlan, startedAt: Date, serverID: String? = nil) {
        var p = plan
        if p.mealsPacked > 0 {
            let k = min(p.mealsPacked, available(.trailMeal))
            consume(.trailMeal, k)
            p.mealsPacked = k
            p.staminaBudget = 100 + k * 40
        }
        activeJob = JobRecord(plan: p, startedAt: startedAt, serverID: serverID)
        emit(.saveNow)
    }

    /// Apply the first `completed` steps of the active job. Safe to call twice: the second call does nothing.
    @discardableResult
    public func applyJob(_ record: JobRecord, completed: Int, recalled: Bool) -> JobReport? {
        guard !appliedJobs.contains(record.plan.id) else { activeJob = nil; return nil }
        appliedJobs.insert(record.plan.id)
        let plan = record.plan
        let n = min(completed, plan.steps.count)
        var lines: [String] = []
        var found: [String] = []
        var greens = 0, hauled: [String] = []
        var elapsed = 0
        for i in 0..<n {
            let s = plan.steps[i]
            elapsed += s.seconds
            for op in s.carves {
                let r = world.carve(center: V2(op.x, op.y), radius: op.r, floorY: op.floorY, tool: .shovel)
                for b in r.revealed { if inv.add(b.item.id, b.item.count) < b.item.count { storage.add(b.item.id, b.item.count) }; found.append(b.item.id.name) }
                if let o = r.touchedOpen { story.flags.insert("broke"); _ = o }
                onCarved(r)
            }
            if s.tendBeds {
                let at = record.startedAt.addingTimeInterval(Double(elapsed))
                for bi in world.props.indices where world.props[bi].kind == .planter {
                    guard let t = world.props[bi].planted, let mins = cropMinutes(world.props[bi]) else { continue }
                    if at.timeIntervalSince(t) >= mins * 60 {
                        storage.add(.greens, 3); greens += 3
                        story.flags.insert("harvested")
                        story.step("seeds", "harvest")
                        if story.counters["seeds", default: 0] >= 2 { story.counters["seeds", default: 0] -= 2; world.props[bi].planted = at } else { world.props[bi].planted = nil }
                    }
                }
            }
            if let from = s.haulFrom, let item = s.haul, let pi = world.propIndex(from) {
                if let si = world.props[pi].stock.firstIndex(where: { $0.id == item.id }) {
                    let k = min(item.count, world.props[pi].stock[si].count)
                    world.props[pi].stock[si].count -= k
                    if world.props[pi].stock[si].count <= 0 { world.props[pi].stock.remove(at: si) }
                    storage.add(item.id, k); hauled.append(k > 1 ? "\(item.id.name) ×\(k)" : item.id.name)
                }
            }
        }
        if n > 0 { max.pos = plan.steps[n - 1].endPos; max.vx = 0; max.ground = true }
        let spent = plan.steps.prefix(n).reduce(0) { $0 + $1.stamina }
        max.stamina = clampD(Double(plan.staminaBudget - spent), 0, max.staminaMax)
        switch plan.kind {
        case .dig: lines.append(n == 0 ? "Max didn’t get started." : "Dug \(n) tile\(n == 1 ? "" : "s").")
        case .tend: lines.append(greens > 0 ? "Harvested \(greens) greens into storage." : "Watered the beds. Nothing was ready yet.")
        case .haul: lines.append(hauled.isEmpty ? "Nothing hauled yet." : "Hauled \(hauled.joined(separator: ", ")) to storage.")
        }
        if !found.isEmpty { lines.append("Found: \(found.joined(separator: ", ")).") }
        let elapsedNow = clock().timeIntervalSince(record.startedAt)
        let report = JobReport(title: plan.title, lines: lines, completed: n, total: plan.steps.count,
                               stopped: JobResolver.stopReason(plan, completed: n, elapsed: elapsedNow, recalled: recalled))
        lastReport = report
        activeJob = nil
        emit(.saveNow)
        return report
    }

    /// Offline fallback: resolve with the device clock when Supabase isn't reachable.
    @discardableResult
    public func resolveLocally(recalled: Bool) -> JobReport? {
        guard let j = activeJob else { return nil }
        let n = JobResolver.completedSteps(j.plan, elapsed: clock().timeIntervalSince(j.startedAt))
        return applyJob(j, completed: n, recalled: recalled)
    }
}
