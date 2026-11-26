import Foundation

// Conversations as data. A graph has entry points (the first whose conditions hold is where a talk
// starts), nodes (what the speaker says) and choices (what Max can answer). Choices carry conditions,
// effects and where the talk goes next. The graphs live in Content/dialogue/*.json.
//
// Conditions:  flag:X  !flag:X  job:X  !job:X  has:ITEM  holding:WHO:ITEM  evidence:ID
//              waterOn  !waterOn  liftRepaired  !liftRepaired  waterAway  trust:WHO>=N
// Effects:     row:PANEL_ROW (runs the same action as the old panels)  flag:X  unflag:X  trust:WHO:+N
//              meet:WHO  say:WHO:TEXT  end
// Text can use {variables} the game fills in (terms, prices, status).

public struct DialogueGraph: Codable, Sendable {
    public var id: String
    public var speaker: String
    public var entries: [Entry]
    public var nodes: [String: Node]

    public struct Entry: Codable, Sendable { public var node: String; public var when: [String]? }
    public struct Node: Codable, Sendable {
        public var lines: [String]
        public var choices: [Choice]
    }
    public struct Choice: Codable, Sendable {
        public var id: String
        public var label: String
        public var detail: String?
        public var when: [String]?
        /// Shown but disabled (with this reason) when `when` fails. Without it, the choice is hidden.
        public var locked: String?
        public var effects: [String]?
        public var next: String?
        public var primary: Bool?
    }
}

/// A talk in progress: which graph, which node, and what's on screen.
public struct Talk: Equatable, Sendable {
    public var graph: String
    public var node: String
    public var speaker: String
    public var lines: [String]
    public var choices: [TalkOption]
}

public struct TalkOption: Equatable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var detail: String?
    public var enabled: Bool
    public var primary: Bool
}

public enum Dialogue {
    /// Every graph shipped with the game, by id.
    public static let graphs: [String: DialogueGraph] = load()

    static func load() -> [String: DialogueGraph] {
        var out: [String: DialogueGraph] = [:]
        for d in ContentFiles.all(in: "dialogue") {
            if let g = try? JSONDecoder().decode(DialogueGraph.self, from: d) { out[g.id] = g }
        }
        return out
    }

    /// Problems in a graph: missing nodes, unknown conditions or effects. Empty means it's sound.
    public static func validate(_ g: DialogueGraph) -> [String] {
        var errs: [String] = []
        for e in g.entries {
            if g.nodes[e.node] == nil { errs.append("entry → missing node \(e.node)") }
            for c in e.when ?? [] where !Self.knownCondition(c) { errs.append("entry \(e.node): unknown condition \(c)") }
        }
        for (k, n) in g.nodes {
            if n.choices.isEmpty { errs.append("\(k): no choices (a talk must always have a way out)") }
            for c in n.choices {
                if let nx = c.next, g.nodes[nx] == nil { errs.append("\(k).\(c.id): next → missing node \(nx)") }
                for w in c.when ?? [] where !Self.knownCondition(w) { errs.append("\(k).\(c.id): unknown condition \(w)") }
                for f in c.effects ?? [] where !Self.knownEffect(f) { errs.append("\(k).\(c.id): unknown effect \(f)") }
            }
        }
        if g.entries.last?.when?.isEmpty == false { errs.append("the last entry must have no conditions, so a talk always starts") }
        return errs
    }

    static func knownCondition(_ c: String) -> Bool {
        let s = c.hasPrefix("!") ? String(c.dropFirst()) : c
        if ["waterOn", "liftRepaired", "waterAway"].contains(s) { return true }
        for p in ["flag:", "job:", "evidence:", "unflagged:"] where s.hasPrefix(p) { return s.count > p.count }
        if s.hasPrefix("has:") { return ItemID(rawValue: String(s.dropFirst(4))) != nil }
        if s.hasPrefix("holding:") { let a = s.split(separator: ":"); return a.count == 3 && ItemID(rawValue: String(a[2])) != nil }
        if s.hasPrefix("trust:") { return s.contains(">=") || s.contains("<") }
        return false
    }

    static func knownEffect(_ f: String) -> Bool {
        if f == "end" { return true }
        for p in ["row:", "flag:", "unflag:", "trust:", "meet:", "say:"] where f.hasPrefix(p) { return f.count > p.count }
        return false
    }
}

extension Game {

    public func hasTalk(_ graph: String) -> Bool { Dialogue.graphs[graph] != nil }

    /// Start a conversation at the first entry whose conditions hold.
    public func startTalk(_ graphID: String) {
        guard let g = Dialogue.graphs[graphID], let e = g.entries.first(where: { check($0.when) }) else { return }
        showNode(g, e.node)
    }

    public func endTalk() {
        guard let t = talk else { return }
        talk = nil
        if t.graph == "mara" { meetMara() }
        emit(.saveNow)
    }

    /// Max answers. Effects run, then the talk moves on (or ends).
    public func chooseTalk(_ choiceID: String) {
        guard let t = talk, let g = Dialogue.graphs[t.graph], let n = g.nodes[t.node],
              let c = n.choices.first(where: { $0.id == choiceID }), check(c.when) else { return }
        var ends = c.next == nil
        for f in c.effects ?? [] {
            if f == "end" { ends = true; continue }
            runEffect(f)
        }
        if ends { endTalk() } else if let nx = c.next { showNode(g, nx) }
    }

    func showNode(_ g: DialogueGraph, _ id: String) {
        guard let n = g.nodes[id] else { talk = nil; return }
        let opts: [TalkOption] = n.choices.compactMap { c in
            let ok = check(c.when)
            if !ok && c.locked == nil { return nil }
            return TalkOption(id: c.id, label: fill(c.label), detail: ok ? c.detail.map(fill) : c.locked.map(fill), enabled: ok, primary: c.primary ?? false)
        }
        talk = Talk(graph: g.id, node: id, speaker: g.speaker, lines: n.lines.map(fill), choices: opts)
    }

    // MARK: conditions and effects

    func check(_ conds: [String]?) -> Bool { (conds ?? []).allSatisfy(check) }

    func check(_ c: String) -> Bool {
        if c.hasPrefix("!") { return !check(String(c.dropFirst())) }
        switch c {
        case "waterOn": return waterOn
        case "liftRepaired": return liftRepaired
        case "waterAway": return waterOn && story.coop.water.route != .outpost
        default: break
        }
        let parts = c.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return false }
        switch parts[0] {
        case "flag": return story.flags.contains(parts[1])
        case "unflagged": return !story.flags.contains(parts[1])
        case "job": return job(parts[1]) != nil
        case "evidence": return story.coop.evidence.contains { $0.id == parts[1] }
        case "has": return ItemID(rawValue: parts[1]).map { available($0) > 0 } ?? false
        case "holding": return parts.count == 3 && ItemID(rawValue: parts[2]).map { holding(parts[1], $0) > 0 } ?? false
        case "trust":
            let rest = parts[1]
            if let r = rest.range(of: ">=") { return trust(String(rest[..<r.lowerBound])) >= Int(rest[r.upperBound...]) ?? 0 }
            if let r = rest.range(of: "<") { return trust(String(rest[..<r.lowerBound])) < Int(rest[r.upperBound...]) ?? 0 }
            return false
        default: return false
        }
    }

    func runEffect(_ f: String) {
        let parts = f.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return }
        switch parts[0] {
        case "row": choosePanel(talk?.graph ?? "", parts[1])
        case "flag": story.flags.insert(parts[1])
        case "unflag": story.flags.remove(parts[1])
        case "trust": if parts.count == 3, let n = Int(parts[2].replacingOccurrences(of: "+", with: "")) { addTrust(parts[1], n) }
        case "meet": if parts[1] == "mara" { meetMara() }
        case "say": if parts.count == 3 { say(parts[1], fill(parts[2])) }
        default: break
        }
    }

    /// Fills {variables} in dialogue text from the game's state.
    func fill(_ s: String) -> String {
        guard s.contains("{") else { return s }
        let list: ([ItemStack]) -> String = { $0.map { "\($0.id.name) ×\($0.count)" }.joined(separator: ", ") }
        let have: ([ItemStack]) -> String = { $0.map { "\($0.id.name) \(Swift.min(self.available($0.id), $0.count))/\($0.count)" }.joined(separator: ", ") }
        let vars: [String: String] = [
            "price": list(MaraDeal.price),
            "priceHave": have(MaraDeal.price),
            "chimneyCost": list(MaraDeal.chimneyCost),
            "chimneyHave": have(MaraDeal.chimneyCost),
            "liftReward": job(MaraDeal.liftJob) != nil || liftRepaired ? "two trail meals when the water runs" : "she repairs your lift",
            "status": maraStatusLine(),
        ]
        var out = s
        for (k, v) in vars { out = out.replacingOccurrences(of: "{\(k)}", with: v) }
        return out
    }

    func maraStatusLine() -> String {
        let water = job(MaraDeal.waterJob), lift = job(MaraDeal.liftJob)
        if let w = water, w.status == .working || w.status == .paused { return w.blocker.map { "I’m stuck. \($0)" } ?? "Fitting your valve. Give me a couple of minutes." }
        if let l = lift, !l.finished, l.status == .working { return "Working on your lift. The drive’s seized, but it’s coming." }
        if waterOn { return "Water’s running. First time in a week the beds have had a drink." }
        if let w = water, !w.finished { return "Valve’s in the sump by the intake. Clear the silt and bring it up." }
        return "Still dry out here."
    }

    /// What Max and Mara have agreed, for the ledger under a talk.
    public func agreementLines(with who: String) -> [(text: String, done: Bool)] {
        var out: [(String, Bool)] = []
        for a in story.coop.agreements where a.with == who {
            out.append(("\(a.title) — \(a.state == .fulfilled ? "kept" : a.state.rawValue)", a.state == .fulfilled))
            for t in a.terms { out.append((termLine(t), t.state == .kept)) }
            for o in a.owedToMax { out.append(("Owed to you: \(o)", false)) }
        }
        return out
    }
}

/// Files bundled under Content/ (kept as folders).
enum ContentFiles {
    static var root: URL? { Bundle.module.url(forResource: "Content", withExtension: nil) }

    static func file(_ path: String) -> Data? {
        guard let u = root?.appendingPathComponent(path) else { return nil }
        return try? Data(contentsOf: u)
    }

    static func all(in folder: String) -> [Data] {
        guard let dir = root?.appendingPathComponent(folder),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { try? Data(contentsOf: dir.appendingPathComponent($0)) }
    }
}

/// Every quest, from Content/story/quests.json, by id.
public enum Quests {
    struct Row: Decodable {
        struct Step: Decodable { var id: String; var text: String }
        var id: String, title: String, side: Bool, steps: [Step]
    }
    public static let all: [String: Quest] = {
        guard let d = ContentFiles.file("story/quests.json"), let rows = try? JSONDecoder().decode([Row].self, from: d) else { return [:] }
        var out: [String: Quest] = [:]
        for r in rows { out[r.id] = Quest(id: r.id, title: r.title, side: r.side, steps: r.steps.map { QuestStep(id: $0.id, text: $0.text) }) }
        return out
    }()
    /// A quest by id. Missing ids come back as an empty side quest (a validation test makes sure none are).
    public static func get(_ id: String) -> Quest { all[id] ?? Quest(id: id, title: id, side: true, steps: []) }
}
