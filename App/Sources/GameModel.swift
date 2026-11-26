import SwiftUI
import AfterlightCore
import UserNotifications

/// What the SwiftUI layer shows. Rebuilt every frame, published only when it changes.
struct UIState: Equatable {
    var context: ContextAction? = nil
    var hint = ""
    var clue: String? = nil
    var stamina = 100
    var staminaMax = 100
    var showStamina = false
    var canClimb = false
    var climbing = false
    var hasPick = false
    var facing = 1
    var cinematic = false
    var planning: String? = nil
    var planReady = false
    var jobTitle: String? = nil
    var jobDone = 0
    var jobTotal = 0
    var packUsed = 0
    var wood = 0
    var hasFlashlight = false
    var health = 100
    var battery = 100
    var started = false
    var aim = 0          // -1 the wheel points up, 1 down, 0 ahead
    var flashOn = false
    var pulseDown = false
    var ordersOK = false
    var speech: String? = nil
    var speaker = ""
    var coopStatus: String? = nil
}

@MainActor
final class GameModel: ObservableObject {
    @Published var ui = UIState()
    @Published var showTitle = true
    @Published var showIntro = false
    /// UI tests read Max's state through an invisible label.
    @Published var debugState = ""
    var smokeSkipIntro = false
    @Published var sheet: Sheet? = nil
    @Published var conversation: Conversation? = nil
    @Published var lineIndex = 0
    @Published var banner: String? = nil
    @Published var report: JobReport? = nil
    @Published var panel: Panel? = nil
    @Published var confirming: PanelRow? = nil
    @Published var panelPoint: CGPoint = .zero

    private(set) var game: Game
    var input = GameInput()
    var planTarget: Int? = nil

    let local = LocalStore()
    let cloud = CloudSync()
    let audio = AudioEngine()
    let haptics = Haptics()
    weak var scene: GameScene?

    private var saveDue: Double? = nil
    private var cloudDue: Double? = nil
    private var clock = 0.0

    init() {
        if ProcessInfo.processInfo.arguments.contains("-uitest") { LocalStore().erase() }
        if let s = LocalStore().load() {
            game = Game.load(s)
            showTitle = true
        } else {
            game = Game()
        }
        if ProcessInfo.processInfo.arguments.contains("-smoketest") { runSmokeTest() }
    }

    /// CI only: plays the opening hands-free so a simulator run can prove the app starts, walks and digs.
    var frames = 0
    static func memoryMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let r = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) } }
        return r == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : -1
    }

    /// CI smoke log: stdout plus a file in the app's Documents the test harness can read back.
    static func smoke(_ line: String) {
        print(line); fflush(stdout)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("smoke.log")
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data((line + "\n").utf8)); try? h.close() }
        else { try? Data((line + "\n").utf8).write(to: url) }
    }

    private func runSmokeTest() {
        Task { @MainActor in
            for i in 0..<70 {
                try? await Task.sleep(for: .seconds(0.5))
                GameModel.smoke("SMOKE t=\(Double(i) * 0.5)s max=(\(Int(self.game.max.pos.x * 10)), \(Int(self.game.max.pos.y * 10))) stamina=\(Int(self.game.max.stamina)) frames=\(self.frames) updates=\(GameScene.updateCalls)/\(GameScene.updateDone) main=\(GameScene.onMain) step=\(GameScene.lastStep) scenePaused=\(self.scene?.isPaused ?? true) viewPaused=\(self.scene?.view?.isPaused ?? true) mem=\(GameModel.memoryMB())MB")
            }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            GameModel.smoke("SMOKE: title shown")
            self.smokeSkipIntro = true
            self.beginIntro()
            try? await Task.sleep(for: .seconds(4))
            GameModel.smoke("SMOKE: intro playing, skipped to the candle")
            try? await Task.sleep(for: .seconds(2))
            self.finishIntro()
            try? await Task.sleep(for: .seconds(4))
            GameModel.smoke("SMOKE: candle lit")
            self.input = GameInput(dx: 1)
            try? await Task.sleep(for: .seconds(2.5))
            self.input = GameInput(dx: 1, dig: true)
            try? await Task.sleep(for: .seconds(6))
            self.input = GameInput()
            GameModel.smoke("SMOKE: walked and dug, Max at \(self.game.max.pos)")
        }
    }

    var hasSave: Bool { game.started }

    func start() {
        if !game.started { game.begin() }
        audio.start()
        withAnimation(.easeOut(duration: 1.2)) { showTitle = false }
        Task { await syncFromCloud() }
    }

    /// New players see the story first; it ends on Max at the grave, waiting for the candle.
    func beginIntro() {
        audio.start()
        withAnimation(.easeInOut(duration: 0.8)) { showIntro = true }
    }

    func finishIntro() {
        withAnimation(.easeInOut(duration: 0.8)) { showIntro = false }
        start()
    }

    func resetForNewGame() {
        local.erase()
        game = Game()
        scene?.reset(game)
    }

    func newGame() {
        local.erase()
        game = Game()
        scene?.reset(game)
        start()
    }

    // MARK: frame

    func tick(_ dt: Double) {
        clock += dt
        frames += 1
        guard !showTitle else { return }
        let paused = conversation != nil || sheet != nil || banner != nil || game.activeJob != nil || panel != nil
        game.update(dt: dt, input: paused ? GameInput() : input)
        for e in game.drainEvents() { handle(e) }
        if let d = saveDue, clock >= d { saveDue = nil; saveNow(cloud: false) }
        if let p = panel, let pt = scene?.viewPoint(p.anchor), abs(pt.x - panelPoint.x) + abs(pt.y - panelPoint.y) > 2 { panelPoint = pt }
        if let d = cloudDue, clock >= d { cloudDue = nil; pushCloud() }
        refreshUI()
        if uiTesting, Int(clock * 10) % 3 == 0 {
            let s = "x=\(String(format: "%.2f", game.max.pos.x)) y=\(String(format: "%.2f", game.max.pos.y)) started=\(game.started) dug=\(game.story.flags.contains("dug"))"
            if s != debugState { debugState = s }
        }
    }
    let uiTesting = ProcessInfo.processInfo.arguments.contains("-uitest")

    private func refreshUI() {
        var u = UIState()
        let g = game
        u.context = g.context
        u.hint = g.hintT > 0 ? g.hintText : ""
        u.clue = g.story.nextClue
        u.stamina = Int((g.max.stamina / g.max.staminaMax * 100).rounded())
        u.health = Int((g.max.health / g.max.healthMax * 100).rounded())
        u.battery = Int(g.battery.rounded())
        u.started = g.started
        u.staminaMax = Int(g.max.staminaMax)
        u.showStamina = g.story.flags.contains("dug") && (g.max.stamina < g.max.staminaMax - 0.5 || g.planning != nil || g.order != nil)
        u.climbing = g.max.mode == .climb
        u.hasPick = g.inv.has(.shortPick)
        u.canClimb = u.climbing || g.world.climbs.contains { abs($0.x - g.max.pos.x) < 0.6 && $0.bottom >= g.max.pos.y - 2.1 && $0.top < g.max.pos.y + 0.4 }
        u.facing = g.max.face
        u.cinematic = g.cine != nil
        u.ordersOK = g.story.flags.contains("ordersOK")
        if let p = g.planning {
            let can = abs(p.reach - p.face) + 1
            if let t = planTarget {
                let n = abs(t - p.face) + 1
                let ok = (t - p.reach) * p.dir <= 0
                u.planning = ok ? "\(n) tile\(n == 1 ? "" : "s"). Max can do all of it." : "\(n) tiles. Max gives out after \(max(0, can))."
                u.planReady = true
            } else {
                u.planning = "Tap the wall to mark a stretch. Max has strength for \(max(0, can)) tiles."
            }
        }
        if let j = g.activeJob {
            u.jobTitle = j.plan.title
            u.jobTotal = j.plan.steps.count
            u.jobDone = JobResolver.completedSteps(j.plan, elapsed: Date().timeIntervalSince(j.startedAt))
        }
        u.packUsed = Inventory.capacity - g.inv.freeSlots
        u.wood = g.inv.wood
        u.hasFlashlight = g.inv.has(.flashlight) && g.story.flags.contains("sawShaft")
        u.flashOn = g.story.flags.contains("flashOn")
        u.aim = input.up ? -1 : (input.climbDown ? 1 : 0)
        if g.speechT > 0 && !g.speechText.isEmpty { u.speech = g.speechText; u.speaker = g.speechWho == "mara" ? "Mara" : g.speechWho }
        if let id = g.activeJobID(for: "mara"), let j = g.job(id), j.status == .working {
            let s = Int(j.secondsLeft.rounded(.up))
            u.coopStatus = "Mara · \(j.title) · \(s / 60):\(String(format: "%02d", s % 60))"
        }
        u.pulseDown = g.world.buried.contains { $0.id == "crystal" && !$0.revealed && abs($0.pos.x - g.max.pos.x) < 1.5 } && g.story.flags.contains("said.glint")
        if u != ui { ui = u }
    }

    // MARK: events

    private func handle(_ e: GameEvent) {
        switch e {
        case .bite(let at, let kind, let carved, let face):
            audio.play(carved ? (kind == .up ? .pick : .scoop) : .whoosh)
            if carved { haptics.bite() }
            scene?.burst(at: at, kind: kind, carved: carved, face: face)
        case .clank(let at): audio.play(.clank); haptics.clank(); scene?.sparks(at: at)
        case .whoosh: audio.play(.whoosh)
        case .step:
            let p = game.max.pos
            let under = game.world.m(Int(p.x.rounded(.down)), Int((p.y + 0.2).rounded(.down)))
            audio.play(under == .metal ? .stepMetal : under == .plank ? .stepWood : .step)
        case .climbStep: audio.play(.climb)
        case .land(let v): audio.play(.land); if v > 6 { haptics.bite() }; scene?.landPuff()
        case .pour(let at): audio.play(.pour); scene?.pour(at: at)
        case .reveal(let at): audio.play(.chime); scene?.sparkle(at: at)
        case .pickup(let name): audio.play(.bag); game.hint("Picked up: \(name)", 2.4)
        case .chime: audio.play(.chime)
        case .breakthrough: audio.play(.rush); haptics.big(); audio.cavern(true)
        case .flashOn: audio.play(.click)
        case .swell: audio.play(.swell)
        case .knock: audio.play(.knock)
        case .spark(let at): audio.play(.spark); scene?.sparks(at: at)
        case .chapter(let n, let title):
            audio.play(.swell)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.8)) { self.banner = "Chapter \(n)\n\(title)" }
                try? await Task.sleep(for: .seconds(3.4))
                withAnimation(.easeInOut(duration: 0.8)) { self.banner = nil }
            }
        case .openSheet(let s): sheet = s
        case .conversation(let id):
            if let c = game.conversation(id) { lineIndex = 0; conversation = c }
        case .placed(let what): audio.play(what == "plank" ? .plank : .scoop); haptics.bite()
        case .wood: audio.play(.chop); haptics.bite()
        case .panel(let id):
            confirming = nil
            if let p = game.panel(id) { panelPoint = scene?.viewPoint(p.anchor) ?? .zero; panel = p }
        case .saveNow: if saveDue == nil { saveDue = clock + 1.5 }
        }
    }

    // MARK: panels

    /// Taps a panel row. Rows that break a deal, move water, or take someone's things ask once first.
    func tapRow(_ row: PanelRow) {
        guard let p = panel, row.enabled else { return }
        if row.confirm != nil && confirming?.id != row.id { confirming = row; haptics.tap(); return }
        confirming = nil
        game.choosePanel(p.id, row.id)
        haptics.tap()
        for e in game.drainEvents() { handle(e) }
        scheduleCoopNotifications()
        if ["ride.up", "ride.down", "chimney.rig"].contains(row.id) { closePanel() } else { panel = game.panel(p.id) }
    }

    func closePanel() {
        if let p = panel { game.panelClosed(p.id) }
        panel = nil
        confirming = nil
    }

    /// Lets the player know when someone finishes work for them while the game is closed.
    private func scheduleCoopNotifications() {
        // Ask only once there's something worth being told about, never on first launch.
        if game.story.coop.jobs.contains(where: { $0.status == .working }) { requestNotifications() }
        let center = UNUserNotificationCenter.current()
        for j in game.story.coop.jobs {
            let id = "coop." + j.id
            center.removePendingNotificationRequests(withIdentifiers: [id])
            guard j.status == .working, j.secondsLeft > 20 else { continue }
            let c = UNMutableNotificationContent()
            c.title = j.worker == "mara" ? "Mara’s done" : "Work finished"
            c.body = j.effect == "waterOn" ? "The outpost’s water is running." : j.effect == "liftOn" ? "The lift works. It goes up to the transit level." : j.title
            center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: j.secondsLeft, repeats: false)))
        }
    }

    // MARK: player actions

    func performContext() { game.performContext(); haptics.tap() }

    func advanceConversation() {
        guard let c = conversation else { return }
        if lineIndex < c.lines.count - 1 { lineIndex += 1 } else if c.choices.count == 1 { choose(c.choices[0].id) }
    }

    func choose(_ choice: String) {
        guard let c = conversation else { return }
        conversation = nil
        game.choose(c.id, choice)
        for e in game.drainEvents() { handle(e) }
    }

    func beginPlan() { planTarget = nil; game.beginPlanning() }
    func cancelPlan() { planTarget = nil; game.cancelPlanning() }
    func confirmPlan() {
        guard let t = planTarget else { return }
        game.confirmOrder(target: t)
        planTarget = nil
        for e in game.drainEvents() { handle(e) }
    }
    func pickPlanTarget(worldX: Double) {
        guard let p = game.planning else { return }
        var c = Int(worldX.rounded(.down))
        if (c - p.face) * p.dir < 0 { c = p.face }
        if abs(c - p.face) > 30 { c = p.face + 30 * p.dir }
        planTarget = c
        haptics.tap()
    }

    // MARK: jobs

    func startJob(_ plan: JobPlan) {
        sheet = nil
        requestNotifications()
        Task {
            let serverStart = await cloud.startJob(plan)
            game.startJob(plan, startedAt: serverStart ?? Date(), serverID: serverStart == nil ? nil : plan.id)
            scheduleJobNotification(plan)
            saveNow(cloud: true)
        }
    }

    /// Ends the job now (or collects a finished one) and shows what Max got done.
    func collectJob(recalled: Bool) {
        guard let j = game.activeJob else { return }
        Task {
            var n: Int? = nil
            if j.serverID != nil { n = await cloud.claimJob(id: j.plan.id) }
            let r: JobReport?
            if let n { r = game.applyJob(j, completed: n, recalled: recalled) } else { r = game.resolveLocally(recalled: recalled) }
            for e in game.drainEvents() { handle(e) }
            scene?.terrainChanged()
            report = r
            saveNow(cloud: true)
        }
    }

    func didBecomeActive() {
        if !showTitle || showIntro { audio.resume() }
        // SpriteKit pauses while the app is inactive (a system prompt, a call); make sure it always resumes.
        scene?.isPaused = false
        scene?.view?.isPaused = false
        guard !showTitle, let j = game.activeJob else { return }
        let done = JobResolver.completedSteps(j.plan, elapsed: Date().timeIntervalSince(j.startedAt))
        if done >= min(j.plan.pauseIndex ?? j.plan.steps.count, j.plan.staminaLimitedSteps) { collectJob(recalled: false) }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func scheduleJobNotification(_ plan: JobPlan) {
        let steps = min(plan.pauseIndex ?? plan.steps.count, plan.staminaLimitedSteps)
        let secs = plan.steps.prefix(steps).reduce(0) { $0 + $1.seconds }
        guard secs > 30 else { return }
        let c = UNMutableNotificationContent()
        c.title = "Max is done"
        c.body = "\(plan.title): come see what changed."
        let req = UNNotificationRequest(identifier: plan.id, content: c, trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(secs), repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: saving

    func saveNow(cloud: Bool) {
        guard game.started, let d = try? game.encodeSave() else { return }
        local.write(d)
        if cloud { pushCloud() } else if cloudDue == nil { cloudDue = clock + 12 }
    }

    private func pushCloud() {
        guard let d = try? game.encodeSave() else { return }
        Task { await cloud.save(d) }
    }

    private func syncFromCloud() async {
        guard let remote = await cloud.load() else { return }
        let localSave = local.load()
        if localSave == nil || remote.savedAt > (localSave?.savedAt ?? .distantPast).addingTimeInterval(5) {
            game = Game.load(remote)
            scene?.reset(game)
        }
    }
}
