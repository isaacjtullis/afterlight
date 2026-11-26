import Foundation

extension Game {
    /// Battery drain, the cost of working on empty, and collapsing when health runs out.
    func survivalTick(_ dt: Double) {
        guard started, cine == nil else { return }
        // Flashlight battery
        if flashlightLit {
            battery = Swift.max(0, battery - dt * 100 / (Tuning.batteryMinutes * 60))
            if battery < 15 && !story.flags.contains("said.lowBattery") {
                story.flags.insert("said.lowBattery")
                think("The flashlight’s getting dim.", 2.4)
                later(2.6) { $0.hint("Tap the battery meter to swap in a lamp cell from your bag.", 6) }
            }
            if battery <= 0 {
                story.flags.insert("lightOff")
                think(available(.lampCell) > 0 ? "Dead. I’ve got a cell in the bag." : "Dead. I need a lamp cell.", 2.6)
                emit(.flashOn)
            }
        }
        if battery > 30 { story.flags.remove("said.lowBattery") }
        // Hunger: slow, steady. Fed, Max heals a little over time; starving, he weakens.
        max.hunger = Swift.max(0, max.hunger - Tuning.hungerPerMinute / 60 * dt)
        if max.hunger > 50 && max.health < max.healthMax { max.health = Swift.min(max.healthMax, max.health + 0.08 * dt) }
        if max.hunger <= 0 { hurt(0.4 * dt, why: "starving") }
        if max.hunger < 25 && !story.flags.contains("said.hungry") {
            story.flags.insert("said.hungry")
            think(packedFood ? "I’m hungry. Good thing I packed food." : "I’m hungry. I should have packed food.", 2.6)
            later(2.8) { $0.hint("Open your bag and tap food to eat it. Pack rations at the pantry before heading out.", 7) }
        }
        if max.hunger > 50 { story.flags.remove("said.hungry") }
        if max.hammerT > 0 { max.hammerT = Swift.max(0, max.hammerT - dt) }
    }

    func hurt(_ amount: Double, why: String) {
        guard amount > 0 else { return }
        max.health = Swift.max(0, max.health - amount)
        if why == "fall" && amount > 3 { think("Ow.", 1.2) }
        if why == "starving" && !story.flags.contains("said.exhausted") {
            story.flags.insert("said.exhausted")
            think("I’m pushing too hard. I need to eat.", 2.6)
        }
        if max.health > 40 { story.flags.remove("said.exhausted") }
        if max.health <= 0 { collapse() }
    }

    /// Max passes out and comes to in his bed. Nothing is lost but time.
    func collapse() {
        if max.mode == .climb { exitClimb() }
        max.pos = V2(22.4, 30); max.vx = 0; max.vy = 0; max.ground = true
        max.swingOn = false
        max.health = 35; max.stamina = 35
        order = nil
        think("…I made it home. Barely.", 3)
        later(3.2) { $0.hint("Eat at the pantry and rest in bed to get your health back.", 6) }
        emit(.land(speed: 8))
        emit(.saveNow)
    }

    /// Fit a fresh lamp cell to the flashlight.
    public func swapCell() {
        guard inv.has(.flashlight), battery < 95 else { return }
        guard available(.lampCell) > 0 else { think("No lamp cells. I’ll have to find some.", 2.4); return }
        consume(.lampCell, 1)
        battery = 100
        story.flags.insert("flashOn"); story.flags.remove("lightOff")
        emit(.flashOn)
        think("Fresh cell. Good.", 1.6)
        emit(.saveNow)
    }

    /// Meal and rest amounts: each helps a little, not all the way.
    public func recover(stamina s: Double, health h: Double) {
        max.stamina = Swift.min(max.staminaMax, max.stamina + s)
        max.health = Swift.min(max.healthMax, max.health + h)
    }

    public var packedFood: Bool { inv.slots.contains { $0?.id.food != nil } }

    /// Eat something from the bag.
    public func eat(_ id: ItemID) {
        guard let f = id.food, inv.count(id) > 0 else { return }
        guard max.hunger < 95 || max.stamina < max.staminaMax - 5 else { think("I’m full.", 1.2); return }
        inv.remove(id, 1)
        max.hunger = Swift.min(100, max.hunger + f.hunger)
        recover(stamina: f.stamina, health: f.health)
        think(["Better.", "That helps.", "Mm. Cold, but it helps."][Int(time) % 3], 1.6)
        emit(.chime)
        emit(.saveNow)
    }

    /// Take a ration from the pantry into the bag.
    public func packRation() {
        guard let i = world.propIndex("pantry"), let si = world.props[i].stock.firstIndex(where: { $0.id == .ration }) else { think("No tins left.", 1.6); return }
        guard inv.add(.ration, 1) == 1 else { think("My bag’s full.", 1.6); return }
        world.props[i].stock[si].count -= 1
        if world.props[i].stock[si].count <= 0 { world.props[i].stock.remove(at: si) }
        story.flags.insert("packedFood")
        if !story.flags.contains("said.packed") {
            story.flags.insert("said.packed")
            hint("Packed. When the hunger meter runs low out there, open the bag and tap the ration to eat it.", 7)
        }
        emit(.saveNow)
    }

    /// Hammer at something: Max swings, sparks fly.
    func hammer(at p: V2, for t: Double = 1.2) {
        max.hammerT = t
        max.busy = Swift.max(max.busy, t)
        for i in 0..<Int(t / 0.3) { later(Double(i) * 0.3 + 0.15) { g in g.emit(.spark(at: p)); g.emit(.hammerHit) } }
    }
}
