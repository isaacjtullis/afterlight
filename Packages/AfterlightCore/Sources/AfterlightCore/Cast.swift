import Foundation

// The people Max meets after Mara and Odi: travelers, the hotel crowd, the toll crew. Each actor
// has a place in the world, whatever they carry, and a route they're walking. Their errands are
// authored (see Errands.swift); this file only moves them and keeps them where they are.

/// One point on an actor's route. `jump` moves them there in one go (riding a lift, climbing a rope);
/// otherwise they walk. `tag` is reported when they arrive, so an errand can move on.
public struct Waypoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var jump: Bool = false
    public var wait: Double = 0
    public var tag: String? = nil
    public init(_ x: Double, _ y: Double, jump: Bool = false, wait: Double = 0, tag: String? = nil) {
        self.x = x; self.y = y; self.jump = jump; self.wait = wait; self.tag = tag
    }
}

public struct Actor: Codable, Equatable, Sendable {
    public var id: String
    public var pos: V2
    public var face = 1
    public var walking = false
    /// Not in the world right now (gone home, away on a long errand).
    public var hidden = false
    public var carrying: [ItemStack] = []
    /// Carrying a lit lamp (it shows, and lights a little ground around them).
    public var lamp = false
    public var route: [Waypoint] = []
    public var wait = 0.0
    /// Which authored errand they're on, and how far into it.
    public var errand = ""
    public var phase = 0
    /// Seconds of game time on this phase (used for timed beats).
    public var phaseT = 0.0
    public var speed = 1.6

    public init(id: String, pos: V2) { self.id = id; self.pos = pos }

    public func holds(_ item: ItemID) -> Int { carrying.filter { $0.id == item }.reduce(0) { $0 + $1.count } }
    public mutating func give(_ item: ItemID, _ n: Int = 1) {
        if let i = carrying.firstIndex(where: { $0.id == item }) { carrying[i].count += n } else { carrying.append(ItemStack(item, n)) }
    }
    @discardableResult
    public mutating func takeAway(_ item: ItemID, _ n: Int = 1) -> Int {
        guard let i = carrying.firstIndex(where: { $0.id == item }) else { return 0 }
        let k = Swift.min(n, carrying[i].count)
        carrying[i].count -= k
        if carrying[i].count <= 0 { carrying.remove(at: i) }
        return k
    }
}

/// Display names and looks for everyone, so the app can label speech and draw the right person.
public enum Cast {
    public static let names: [String: String] = [
        "max": "Max", "mara": "Mara", "odi": "Odi", "wren": "Wren", "ellis": "Ellis", "scav": "Corvin",
        "kid1": "Jun", "kid2": "Pip", "toll1": "Hask", "toll2": "Toller", "upper": "Sela", "keeper": "Bram",
    ]
    public static func name(_ id: String) -> String { names[id] ?? id.capitalized }
}

extension Game {

    public func actor(_ id: String) -> Actor? { story.cast[id] }

    /// Everyone who's in the world right now, for drawing.
    public var visibleCast: [Actor] { story.cast.values.filter { !$0.hidden }.sorted { $0.id < $1.id } }

    func setActor(_ id: String, _ f: (inout Actor) -> Void) {
        guard var a = story.cast[id] else { return }
        f(&a)
        story.cast[id] = a
    }

    func spawn(_ id: String, at p: V2, carrying: [ItemStack] = [], lamp: Bool = false) {
        var a = story.cast[id] ?? Actor(id: id, pos: p)
        a.pos = p; a.hidden = false; a.carrying = carrying; a.lamp = lamp; a.route = []; a.wait = 0
        story.cast[id] = a
    }

    func send(_ id: String, _ route: [Waypoint]) {
        setActor(id) { $0.route = route; $0.wait = 0 }
    }

    func nearActor(_ id: String, _ r: Double = 1.7) -> Bool {
        guard let a = story.cast[id], !a.hidden else { return false }
        return abs(a.pos.x - max.pos.x) < r && abs(a.pos.y - max.pos.y) < 1.4
    }

    /// People remember what they saw Max do, one fact at a time. Only the person who saw it knows it.
    public func remembers(_ who: String, _ what: String) -> Bool { story.memories[who]?.contains(what) ?? false }
    func remember(_ who: String, _ what: String) { story.memories[who, default: []].insert(what) }


    /// A bubble over whoever's talking. Max's own lines go to his thoughts.
    func line(_ who: String, _ text: String, _ d: Double = 3.6) {
        if who == "max" { think(text, d) } else { say(who, text, d) }
    }

    /// A short exchange played as speech while Max keeps moving. Each line waits for the last.
    func banter(_ lines: [(String, String)], gap: Double = 0.4, then: ((Game) -> Void)? = nil) {
        var t = 0.0
        for (who, text) in lines {
            let d = Swift.max(2.4, 0.9 + Double(text.split(separator: " ").count) * 0.28)
            later(t) { $0.line(who, text, d) }
            t += d + gap
        }
        if let then { later(t) { then($0) } }
    }

    // MARK: moving people

    func castTick(_ dt: Double) {
        for id in story.cast.keys.sorted() {
            guard var a = story.cast[id], !a.hidden else { continue }
            a.phaseT += dt
            if a.wait > 0 {
                a.wait -= dt; a.walking = false
                story.cast[id] = a
                continue
            }
            guard let wp = a.route.first else {
                a.walking = false
                story.cast[id] = a
                continue
            }
            var arrived = false
            if wp.jump {
                a.pos = V2(wp.x, wp.y); arrived = true
            } else {
                let dx = wp.x - a.pos.x, dy = wp.y - a.pos.y
                if abs(dx) > 0.12 {
                    let step = Swift.min(abs(dx), a.speed * dt)
                    a.pos.x += dx > 0 ? step : -step
                    a.face = dx > 0 ? 1 : -1
                    a.walking = true
                    // Floors along a route are level; small steps up or down follow along.
                    if abs(dy) > 0.01 { a.pos.y += dy * Swift.min(1, step / Swift.max(0.2, abs(dx))) }
                } else if abs(dy) > 0.05 {
                    // Climbing straight up or down (rungs, stairs).
                    let step = Swift.min(abs(dy), 1.4 * dt)
                    a.pos.y += dy > 0 ? step : -step
                    a.walking = true
                } else { arrived = true }
            }
            if arrived {
                a.pos = V2(wp.x, wp.y)
                a.route.removeFirst()
                a.wait = wp.wait
                a.walking = false
            }
            story.cast[id] = a
            if arrived, let tag = wp.tag { actorArrived(id, tag) }
        }
    }

    /// Where an errand goes next once someone gets where they were going.
    func actorArrived(_ id: String, _ tag: String) {
        errandArrived(id, tag)
    }
}
