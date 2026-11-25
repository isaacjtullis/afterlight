import Foundation

// Reusable rules for working with (and against) other survivors: shared jobs at a place,
// agreements with recorded terms, who owns what, and where water goes.
// Mara is the first person to use them; later survivors plug into the same pieces.

// MARK: - Shared jobs

/// One participant's part in a shared job.
public struct Contribution: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        case deliver(ItemStack)   // a part brought to the job site
        case task(String)         // something done on site; the string is the story flag that marks it
        case work(Double)         // timed work by the job's worker, in seconds
    }
    public var id: String
    public var by: String
    public var text: String
    public var kind: Kind
    public var done = false

    public init(id: String, by: String, text: String, kind: Kind, done: Bool = false) {
        self.id = id; self.by = by; self.text = text; self.kind = kind; self.done = done
    }

    public var isWork: Bool { if case .work = kind { return true } else { return false } }
    public var part: ItemStack? { if case .deliver(let s) = kind { return s } else { return nil } }
}

public enum JobStatus: String, Codable, Sendable { case open, working, paused, done, canceled }

/// A job at a location with visible prerequisites, one contribution from each participant,
/// and a change to the world when it's done.
public struct SharedJob: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var siteID: String
    public var site: V2
    public var worker: String
    public var contributions: [Contribution]
    /// Parts delivered to the site but not yet fitted. Reclaimable once if the job is cancelled.
    public var reserved: [ItemStack] = []
    /// Parts fitted when the job finished. These stay where they are.
    public var installed: [ItemStack] = []
    public var workDone = 0.0
    public var lastTick: Date? = nil
    public var status: JobStatus = .open
    public var blocker: String? = nil
    public var effect: String
    public var agreementID: String? = nil
    public var reclaimed = false

    public init(id: String, title: String, siteID: String, site: V2, worker: String,
                contributions: [Contribution], effect: String, agreementID: String? = nil) {
        self.id = id; self.title = title; self.siteID = siteID; self.site = site; self.worker = worker
        self.contributions = contributions; self.effect = effect; self.agreementID = agreementID
    }

    public var workNeeded: Double {
        var t = 0.0
        for c in contributions { if case .work(let s) = c.kind { t += s } }
        return t
    }
    public var progress: Double { workNeeded > 0 ? Swift.min(1, workDone / workNeeded) : 1 }
    public var prerequisites: [Contribution] { contributions.filter { !$0.isWork } }
    public var ready: Bool { prerequisites.allSatisfy(\.done) }
    public var finished: Bool { status == .done || status == .canceled }
    public var reclaimable: [ItemStack] { (status == .canceled && !reclaimed) ? reserved : [] }
    public var secondsLeft: Double { Swift.max(0, workNeeded - workDone) }
}

// MARK: - Agreements

public enum TermState: String, Codable, Sendable { case pending, kept, broken }

public struct Term: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var by: String
    public var text: String
    public var state: TermState = .pending
    public var note: String? = nil
    public init(id: String, by: String, text: String) { self.id = id; self.by = by; self.text = text }
}

public enum AgreementState: String, Codable, Sendable { case active, fulfilled, broken, cancelled }

/// What two people agreed, term by term. Breaking it is recorded and never quietly undone.
public struct Agreement: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var with: String
    public var title: String
    public var terms: [Term]
    /// What the other side still owes Max, in plain words. Kept even if the deal goes bad.
    public var owedToMax: [String]
    public var state: AgreementState = .active
    public var brokenBy: String? = nil
    public var log: [String] = []

    public init(id: String, with: String, title: String, terms: [Term], owedToMax: [String]) {
        self.id = id; self.with = with; self.title = title; self.terms = terms; self.owedToMax = owedToMax
    }
}

// MARK: - Ownership and evidence

/// Something Max is carrying that belongs to someone else.
public struct Holding: Codable, Equatable, Sendable {
    public var owner: String
    public var item: ItemID
    public var count: Int
    public var how: String
}

/// What someone actually knows. Blame needs one of these.
public struct Evidence: Codable, Equatable, Sendable {
    public var id: String
    public var heldBy: String
    public var against: String
    public var text: String
}

// MARK: - Water

public enum WaterRoute: String, Codable, Sendable { case outpost, home, split }

public struct WaterState: Codable, Equatable, Sendable {
    public var outpostPumpRunning = false
    public var route: WaterRoute = .outpost
    public init() {}

    public var outpostTapFlow: Double { outpostPumpRunning ? (route == .outpost ? 1 : (route == .split ? 0.5 : 0)) : 0 }
    public var homeFromOutpost: Double { outpostPumpRunning ? (route == .home ? 1 : (route == .split ? 0.5 : 0)) : 0 }
}

/// Everything about living alongside other people, saved with the story.
public struct Coop: Codable, Equatable, Sendable {
    public var jobs: [SharedJob] = []
    public var agreements: [Agreement] = []
    public var holdings: [Holding] = []
    public var evidence: [Evidence] = []
    public var water = WaterState()
    public var trust: [String: Int] = [:]
    public var appliedEffects: Set<String> = []
    public init() {}
}

// MARK: - Panels

/// A choice offered in a small panel at a person or object.
public struct PanelRow: Equatable, Sendable, Identifiable {
    public enum Style: String, Sendable { case action, primary, info, done }
    public var id: String
    public var label: String
    public var detail: String? = nil
    public var enabled = true
    /// Shown before acting. Only for breaking agreements, redirecting water, or taking supplies.
    public var confirm: String? = nil
    public var style: Style = .action

    public init(id: String, label: String, detail: String? = nil, enabled: Bool = true, confirm: String? = nil, style: Style = .action) {
        self.id = id; self.label = label; self.detail = detail; self.enabled = enabled; self.confirm = confirm; self.style = style
    }
    static func info(_ id: String, _ text: String, done: Bool = false) -> PanelRow {
        PanelRow(id: id, label: text, enabled: false, style: done ? .done : .info)
    }
}

public struct Panel: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var speaker: String? = nil
    public var lines: [String] = []
    public var anchor: V2
    public var rows: [PanelRow]
}

// MARK: - Engine

extension Game {

    public func job(_ id: String) -> SharedJob? { story.coop.jobs.first { $0.id == id } }
    func editJob(_ id: String, _ f: (inout SharedJob) -> Void) {
        if let i = story.coop.jobs.firstIndex(where: { $0.id == id }) { f(&story.coop.jobs[i]) }
    }
    public func agreement(_ id: String) -> Agreement? { story.coop.agreements.first { $0.id == id } }
    func editAgreement(_ id: String, _ f: (inout Agreement) -> Void) {
        if let i = story.coop.agreements.firstIndex(where: { $0.id == id }) { f(&story.coop.agreements[i]) }
    }
    public func trust(_ who: String) -> Int { story.coop.trust[who, default: 0] }
    func addTrust(_ who: String, _ n: Int) { story.coop.trust[who, default: 0] += n }

    /// Adds a job, marking any prerequisite that's already true in the world.
    func addJob(_ j: SharedJob) {
        guard job(j.id) == nil else { return }
        var j = j
        for i in j.contributions.indices {
            if case .task(let flag) = j.contributions[i].kind, story.flags.contains(flag) { j.contributions[i].done = true }
        }
        j.lastTick = clock()
        story.coop.jobs.append(j)
        advanceSharedJobs(to: clock())
    }

    /// The one job a worker is on: the earliest unfinished one they've taken on.
    public func activeJobID(for worker: String) -> String? {
        story.coop.jobs.first { $0.worker == worker && !$0.finished }?.id
    }

    /// Accounts for time passed (including while the game was closed). Work continues only while the
    /// worker, route and parts are all available; otherwise it pauses with the exact reason.
    public func advanceSharedJobs(to now: Date) {
        for idx in story.coop.jobs.indices where !story.coop.jobs[idx].finished {
            let j = story.coop.jobs[idx]
            let last = j.lastTick ?? now
            if now < last { continue }   // a clock that ran backwards never undoes work
            if let b = jobBlocker(j) {
                story.coop.jobs[idx].status = j.ready ? .paused : .open
                story.coop.jobs[idx].blocker = b
                story.coop.jobs[idx].lastTick = now
                continue
            }
            let dt = Swift.max(0, now.timeIntervalSince(last))
            story.coop.jobs[idx].status = .working
            story.coop.jobs[idx].blocker = nil
            story.coop.jobs[idx].workDone = Swift.min(j.workNeeded, j.workDone + dt)
            story.coop.jobs[idx].lastTick = now
            if story.coop.jobs[idx].workDone >= j.workNeeded - 1e-6 {
                // The worker moves on at the moment this one finished, not at the moment we noticed.
                let finishedAt = last.addingTimeInterval(Swift.max(0, j.workNeeded - j.workDone))
                completeJob(j.id)
                for k in story.coop.jobs.indices where k != idx && story.coop.jobs[k].worker == j.worker && !story.coop.jobs[k].finished {
                    story.coop.jobs[k].lastTick = finishedAt
                }
            }
        }
    }

    func jobBlocker(_ j: SharedJob) -> String? {
        if let next = j.prerequisites.first(where: { !$0.done }) { return "Waiting on: \(next.text)" }
        if let a = activeJobID(for: j.worker), a != j.id, let other = job(a) {
            return "\(name(j.worker)) is on “\(other.title)” first."
        }
        if let r = routeBlocker(j) { return r }
        for c in j.contributions {
            if let part = c.part {
                let have = (j.reserved + j.installed).filter { $0.id == part.id }.reduce(0) { $0 + $1.count }
                if have < part.count { return "\(part.id.name) is missing from the site." }
            }
        }
        return standingBlocker(j)
    }

    func completeJob(_ id: String) {
        editJob(id) { j in
            j.installed += j.reserved
            j.reserved = []
            j.status = .done
            j.blocker = nil
            for i in j.contributions.indices where j.contributions[i].isWork { j.contributions[i].done = true }
        }
        guard let j = job(id) else { return }
        if story.coop.appliedEffects.insert("job." + id).inserted {
            applyEffect(j.effect, job: j)
        }
        emit(.saveNow)
    }

    /// Brings one part to the site. It's reserved there: out of the pack, not yet fitted.
    @discardableResult
    public func deliver(job id: String, contribution cid: String) -> Bool {
        guard let j = job(id), !j.finished,
              let c = j.contributions.first(where: { $0.id == cid }), !c.done, let part = c.part,
              available(part.id) >= part.count else { return false }
        consume(part.id, part.count)
        editJob(id) { j in
            j.reserved.append(part)
            if let i = j.contributions.firstIndex(where: { $0.id == cid }) { j.contributions[i].done = true }
        }
        onDelivered(part, job: id)
        advanceSharedJobs(to: clock())
        emit(.chime)
        emit(.saveNow)
        return true
    }

    /// Marks a task done wherever it's a prerequisite.
    func completeTask(_ flag: String) {
        advanceSharedJobs(to: clock())
        story.flags.insert(flag)
        for i in story.coop.jobs.indices where !story.coop.jobs[i].finished {
            for k in story.coop.jobs[i].contributions.indices {
                if case .task(let f) = story.coop.jobs[i].contributions[k].kind, f == flag { story.coop.jobs[i].contributions[k].done = true }
            }
        }
        advanceSharedJobs(to: clock())
    }

    /// Stops a job. Fitted parts stay; delivered-but-unfitted parts wait at the site to be taken back.
    public func cancelJob(_ id: String, by who: String) {
        guard let j = job(id), !j.finished else { return }
        advanceSharedJobs(to: clock())
        guard job(id)?.finished == false else { return }
        editJob(id) { $0.status = .canceled; $0.blocker = nil }
        if let aid = j.agreementID, who == "max" {
            breakAgreement(aid, by: "max", term: nil, note: "Max called off “\(j.title)”.")
        }
        advanceSharedJobs(to: clock())
        emit(.saveNow)
    }

    /// Takes back parts from a cancelled job. Works exactly once.
    @discardableResult
    public func reclaim(job id: String) -> [ItemStack] {
        guard let j = job(id) else { return [] }
        let parts = j.reclaimable
        guard !parts.isEmpty else { return [] }
        editJob(id) { $0.reserved = []; $0.reclaimed = true }
        for p in parts {
            let added = inv.add(p.id, p.count)
            if added < p.count { storage.add(p.id, p.count - added) }
        }
        emit(.chime)
        emit(.pickup(parts.map { $0.count > 1 ? "\($0.id.name) ×\($0.count)" : $0.id.name }.joined(separator: ", ")))
        emit(.saveNow)
        return parts
    }

    // MARK: agreements

    func addAgreement(_ a: Agreement) {
        guard agreement(a.id) == nil else { return }
        story.coop.agreements.append(a)
    }

    func keepTerm(_ aid: String, _ tid: String) {
        editAgreement(aid) { a in
            guard let i = a.terms.firstIndex(where: { $0.id == tid }), a.terms[i].state == .pending else { return }
            a.terms[i].state = .kept
            if a.state == .active && a.terms.allSatisfy({ $0.state == .kept }) {
                a.state = .fulfilled
                a.owedToMax = []
                a.log.append("Every term kept.")
            }
        }
    }

    /// Records a broken agreement. Nothing later un-breaks it; repairs are logged alongside.
    func breakAgreement(_ aid: String, by who: String, term tid: String?, note: String) {
        editAgreement(aid) { a in
            if let tid, let i = a.terms.firstIndex(where: { $0.id == tid }) {
                a.terms[i].state = .broken
                a.terms[i].note = note
            }
            if a.state == .active || a.state == .fulfilled {
                a.state = .broken
                a.brokenBy = who
            }
            a.log.append(note)
        }
    }

    // MARK: ownership

    public func holding(_ owner: String, _ item: ItemID) -> Int {
        story.coop.holdings.filter { $0.owner == owner && $0.item == item }.reduce(0) { $0 + $1.count }
    }
    func addHolding(_ owner: String, _ item: ItemID, _ n: Int, how: String) {
        story.coop.holdings.append(Holding(owner: owner, item: item, count: n, how: how))
    }
    /// Settles up to `n` of what Max holds of `owner`'s. Returns how many were settled.
    @discardableResult
    func settleHolding(_ owner: String, _ item: ItemID, _ n: Int) -> Int {
        var left = n
        for i in story.coop.holdings.indices.reversed() where left > 0 {
            if story.coop.holdings[i].owner == owner && story.coop.holdings[i].item == item {
                let k = Swift.min(left, story.coop.holdings[i].count)
                story.coop.holdings[i].count -= k
                left -= k
                if story.coop.holdings[i].count == 0 { story.coop.holdings.remove(at: i) }
            }
        }
        return n - left
    }
    public func evidence(heldBy who: String, against: String = "max") -> [Evidence] {
        story.coop.evidence.filter { $0.heldBy == who && $0.against == against }
    }
    func addEvidence(_ e: Evidence) {
        if !story.coop.evidence.contains(where: { $0.id == e.id }) { story.coop.evidence.append(e) }
    }

    func name(_ who: String) -> String { who == "max" ? "Max" : who.prefix(1).uppercased() + who.dropFirst() }
}
