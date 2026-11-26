import Foundation

extension Game {
    /// Battery drain, the cost of working on empty, and collapsing when health runs out.
    func survivalTick(_ dt: Double) {
        guard started, cine == nil else { return }
        // Flashlight battery
        if inv.has(.flashlight) && story.flags.contains("flashOn") {
            battery = Swift.max(0, battery - dt * 100 / (Tuning.batteryMinutes * 60))
            if battery < 15 && !story.flags.contains("said.lowBattery") {
                story.flags.insert("said.lowBattery")
                think("The flashlight’s getting dim.", 2.4)
                later(2.6) { $0.hint("Tap the battery meter to swap in a lamp cell from your bag.", 6) }
            }
            if battery <= 0 {
                story.flags.remove("flashOn")
                think(available(.lampCell) > 0 ? "Dead. I’ve got a cell in the bag." : "Dead. I need a lamp cell.", 2.6)
                emit(.flashOn)
            }
        }
        if battery > 30 { story.flags.remove("said.lowBattery") }
        // Working with nothing left costs health.
        if max.stamina <= 0.5 && (max.swingOn || max.running) { hurt(3 * dt, why: "exhausted") }
    }

    func hurt(_ amount: Double, why: String) {
        guard amount > 0 else { return }
        max.health = Swift.max(0, max.health - amount)
        if why == "fall" && amount > 3 { think("Ow.", 1.2) }
        if why == "exhausted" && !story.flags.contains("said.exhausted") {
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
        story.flags.insert("flashOn")
        emit(.flashOn)
        think("Fresh cell. Good.", 1.6)
        emit(.saveNow)
    }

    /// Meal and rest amounts: each helps a little, not all the way.
    func recover(stamina s: Double, health h: Double) {
        max.stamina = Swift.min(max.staminaMax, max.stamina + s)
        max.health = Swift.min(max.healthMax, max.health + h)
    }
}
