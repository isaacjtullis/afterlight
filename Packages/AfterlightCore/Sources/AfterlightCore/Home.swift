import Foundation

extension Game {
    /// Props added to the home after saves already existed; old saves get them on load.
    static let addedLater = ["pantry", "signal", "lantern.clue", "shelter.light", "generator"]

    // MARK: eating and drinking

    /// Eat and drink at the pantry. A ration (or home-grown greens) restores Max fully; plain water helps a little.
    public func eatAndDrink() {
        guard max.hunger < 95 || max.health < max.healthMax - 1 else { think("Not hungry. Not yet.", 1.8); return }
        if let i = world.propIndex("pantry"), let si = world.props[i].stock.firstIndex(where: { $0.id == .ration }) {
            world.props[i].stock[si].count -= 1
            if world.props[i].stock[si].count <= 0 { world.props[i].stock.remove(at: si) }
            recover(stamina: 30, health: 10); max.hunger = Swift.min(100, max.hunger + 50)
            let left = world.props[i].stock.first(where: { $0.id == .ration })?.count ?? 0
            think(left > 0 ? "Beans and cold water. Better. \(left) tins left." : "That was the last tin. I’ll need to grow something.", 3)
        } else if available(.greens) > 0 {
            consume(.greens, 1)
            recover(stamina: 15, health: 5); max.hunger = Swift.min(100, max.hunger + 25)
            think("Greens from the beds. Better.", 2.4)
        } else if available(.trailMeal) > 0 {
            consume(.trailMeal, 1)
            recover(stamina: 30, health: 10); max.hunger = Swift.min(100, max.hunger + 60)
            think("Better.", 1.5)
        } else {
            recover(stamina: 15, health: 3)
            think("Just water. It helps a little.", 2.4)
        }
        if quarters.decor.contains("table") { max.hunger = Swift.min(100, max.hunger + 10) }
        max.restT = 0
        emit(.chime)
        emit(.saveNow)
    }

    // MARK: bag management

    /// Put a pocket's contents down where Max stands. It stays there, saved, until he picks it up.
    public func dropSlot(_ i: Int) {
        guard inv.slots.indices.contains(i), let s = inv.slots[i] else { return }
        inv.slots[i] = nil
        let x = max.pos.x + Double(max.face) * 0.7
        let y = world.groundY(x, from: max.pos.y - 1.0, to: max.pos.y + 1.5) ?? max.pos.y
        if let near = world.props.firstIndex(where: { $0.kind == .pile && $0.pos.dist(V2(x, y)) < 1.0 }) {
            world.props[near].stock.append(s)
        } else {
            world.props.append(Prop(id: "pile.\(Int(time * 1000))", kind: .pile, pos: V2(x, y), stock: [s]))
        }
        emit(.placed("pile"))
        emit(.saveNow)
    }

    /// At home, move a pocket into workshop storage.
    /// Bag wood plus, at home, the wood pile in storage.
    public var woodAvailable: Int { inv.wood + (atHome ? storage.wood : 0) }
    public func storeWood(_ n: Int? = nil) {
        guard atHome else { return }
        let k = Swift.min(n ?? inv.wood, inv.wood)
        guard k > 0 else { return }
        inv.wood -= k; storage.wood += k
        emit(.saveNow)
    }
    public func takeWood(_ n: Int? = nil) {
        guard atHome else { return }
        let k = Swift.min(n ?? storage.wood, storage.wood, Inventory.woodCap - inv.wood)
        guard k > 0 else { return }
        storage.wood -= k; inv.wood += k
        emit(.saveNow)
    }

    public func storeSlot(_ i: Int) {
        guard atHome, inv.slots.indices.contains(i), let s = inv.slots[i] else { return }
        inv.slots[i] = nil
        storage.add(s.id, s.count)
        emit(.saveNow)
    }

    /// Picking up a pile empties it, and an empty pile is gone.
    func clearEmptyPiles() {
        world.props.removeAll { $0.kind == .pile && $0.stock.isEmpty }
    }

    /// Starting a job from a ladder: step off first, so Max is on his feet to go.
    func standUpForJob() {
        guard max.mode == .climb, let id = max.climbID, let c = world.climbs.first(where: { $0.id == id }) else { return }
        let y = world.groundY(c.x, from: c.bottom - 0.3, to: c.bottom + 0.5) ?? c.bottom
        max.pos = V2(c.x, y)
        exitClimb()
    }
}
