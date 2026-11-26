import SwiftUI
import UIKit
import AfterlightCore

/// Raw UIKit touch handling: reacts the instant a finger lands, tracks it as it slides, and survives
/// other fingers on other controls. SwiftUI gestures were too slow and too picky for game controls.
final class TouchPadView: UIView {
    enum Mode { case button, leftRight }
    var mode: Mode = .button
    var onChange: ((Int) -> Void)?
    private var finger: UITouch?
    private var value = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    private func set(_ v: Int) {
        guard v != value else { return }
        value = v
        if v != 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5) }
        onChange?(v)
    }
    private func read(_ t: UITouch) -> Int {
        mode == .button ? 1 : (t.location(in: self).x < bounds.midX ? -1 : 1)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if finger == nil, let t = touches.first { finger = t; set(read(t)) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let f = finger, touches.contains(f) { set(read(f)) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    private func release(_ touches: Set<UITouch>) {
        if let f = finger, touches.contains(f) { finger = nil; set(0) }
    }
}

struct TouchPad: UIViewRepresentable {
    var mode: TouchPadView.Mode = .button
    var onChange: (Int) -> Void
    func makeUIView(context: Context) -> TouchPadView { let v = TouchPadView(); v.mode = mode; v.onChange = onChange; return v }
    func updateUIView(_ v: TouchPadView, context: Context) { v.mode = mode; v.onChange = onChange }
}

/// A button you hold. Several can be held at once (walk + dig). The touch area reaches past the drawing.
struct HoldButton<Label: View>: View {
    var id = ""
    var slop: CGFloat = 12
    var onChange: (Bool) -> Void
    @ViewBuilder var label: (Bool) -> Label
    @State private var down = false
    var body: some View {
        label(down)
            .padding(slop)
            .overlay(TouchPad { v in
                let d = v != 0
                if d != down { down = d; onChange(d) }
            })
            .padding(-slop)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
            .accessibilityLabel(id)
    }
}

/// A chunky rounded arrowhead.
struct Arrowhead: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.12))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.28, y: r.maxY - r.height * 0.12))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.12), control: CGPoint(x: r.minX + r.width * 0.5, y: r.midY))
        return p
    }
}

/// ◀ ▶ as one pad: press either side, slide your thumb across to turn around.
struct MovePad: View {
    var onChange: (Int) -> Void
    @State private var dir = 0
    var body: some View {
        HStack(spacing: 6) {
            half(-1, id: "move.left")
            half(1, id: "move.right")
        }
        .padding(6)
        .background(Capsule().fill(Color.black.opacity(0.42)))
        .background(.ultraThinMaterial.opacity(0.3), in: Capsule())
        .overlay(Capsule().stroke(Color.amber.opacity(0.28), lineWidth: 1.2))
        .padding(10)
        .overlay(TouchPad(mode: .leftRight) { v in dir = v; onChange(v) }.accessibilityHidden(true))
        .padding(-10)
        .animation(.easeOut(duration: 0.07), value: dir)
    }
    private func half(_ d: Int, id: String) -> some View {
        let on = dir == d
        return ZStack {
            Capsule().fill(on ? Color.amber.opacity(0.42) : Color.white.opacity(0.06))
            Arrowhead().fill(on ? Color.black.opacity(0.75) : Color.cream.opacity(0.9))
                .frame(width: 26, height: 26).scaleEffect(x: CGFloat(d), y: 1)
        }
        .frame(width: 86, height: 68)
        .shadow(color: on ? Color.amber.opacity(0.6) : .clear, radius: 10)
        .scaleEffect(on ? 0.96 : 1)
        .accessibilityElement().accessibilityAddTraits(.isButton).accessibilityIdentifier(id).accessibilityLabel(id)
    }
}

/// A round control: dark glass with a brass rim that lights up while held.
struct GlassCircle: View {
    var size: CGFloat
    var pressed: Bool
    var pulse = false
    var icon: AnyView
    var caption: String? = nil
    var body: some View {
        ZStack {
            Circle().fill(pressed ? Color.amber.opacity(0.42) : Color.black.opacity(0.42))
            Circle().stroke(pulse ? Color.violet : Color.amber.opacity(pressed ? 0.9 : 0.3), lineWidth: pulse ? 2 : 1.2)
            VStack(spacing: 2) {
                icon.foregroundStyle(pressed ? Color.black.opacity(0.8) : Color.cream)
                if let caption {
                    Text(caption).font(.avenir(10, "DemiBold")).tracking(1.2)
                        .foregroundStyle(pressed ? Color.black.opacity(0.7) : Color.cream.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .background(.ultraThinMaterial.opacity(0.3), in: Circle())
        .shadow(color: pulse ? Color.violet.opacity(0.6) : (pressed ? Color.amber.opacity(0.55) : .black.opacity(0.3)), radius: pressed || pulse ? 14 : 8)
        .scaleEffect(pressed ? 0.93 : 1)
        .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// A spade seen from the side: D-grip, shaft, pointed blade, and a little chevron showing where it cuts.
/// Drawn pointing right; mirror it to point left, rotate it to point down.
struct DigIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24
            func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
            var grip = Path()
            grip.addRoundedRect(in: CGRect(x: 1 * s, y: 8.6 * s, width: 3.2 * s, height: 6.8 * s), cornerSize: CGSize(width: 1.6 * s, height: 1.6 * s))
            ctx.stroke(grip, with: .foreground, lineWidth: 1.6 * s)
            var shaft = Path(); shaft.move(to: P(4.2, 12)); shaft.addLine(to: P(12, 12))
            ctx.stroke(shaft, with: .foreground, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round))
            var blade = Path()
            blade.move(to: P(11.4, 8.2)); blade.addLine(to: P(16.4, 8.2))
            blade.addQuadCurve(to: P(19.6, 12), control: P(18.9, 8.6))
            blade.addQuadCurve(to: P(16.4, 15.8), control: P(18.9, 15.4))
            blade.addLine(to: P(11.4, 15.8)); blade.closeSubpath()
            ctx.fill(blade, with: .foreground)
            var chev = Path(); chev.move(to: P(20.8, 9.6)); chev.addLine(to: P(23, 12)); chev.addLine(to: P(20.8, 14.4))
            ctx.stroke(chev, with: .foreground, style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round, lineJoin: .round))
        }
    }
}

struct HUDView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        let ui = model.ui
        ZStack {
            VStack(spacing: 10) {
                topBar(ui)
                if ui.started { meters(ui) }
                if !ui.hint.isEmpty {
                    Text(ui.hint)
                        .font(.avenir(15)).foregroundStyle(Color.cream).multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.5)))
                        .frame(maxWidth: 420)
                        .transition(.opacity)
                }
                if let s = ui.speech {
                    (Text(ui.speaker + "  ").font(.avenir(14, "DemiBold")).foregroundColor(Color.amber) + Text(s).font(.avenir(15)).foregroundColor(Color.cream))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.12, green: 0.18, blue: 0.18).opacity(0.78)))
                        .frame(maxWidth: 440)
                        .transition(.opacity)
                }
                if let c = ui.coopStatus {
                    Text(c).font(.avenir(13, "DemiBold")).foregroundStyle(Color.cream.opacity(0.9))
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Capsule().fill(Color.black.opacity(0.4)))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.3), value: ui.hint)
            .animation(.easeInOut(duration: 0.3), value: ui.speech)

            if ui.jobTitle == nil && ui.planning == nil && !ui.cinematic {
                controls(ui)
            }
            if let text = ui.planning { planBar(text, ready: ui.planReady) }
            if let t = ui.jobTitle { jobBanner(t, ui) }
            if let c = model.conversation { ConversationCard(convo: c) }
            if let p = model.panel { if p.speaker != nil { TalkPanel(panel: p) } else { PanelCard(panel: p) } }
            if let t = model.talk {
                TalkStage(speaker: t.speaker, line: t.lines.joined(separator: " "), progress: nil,
                          choices: t.choices.map { TalkStage.Choice(id: $0.id, label: $0.label, detail: $0.detail, enabled: $0.enabled, primary: $0.primary) },
                          ledger: model.game.agreementLines(with: t.graph).enumerated().map { i, l in PanelRow.info("l\(i)", l.text, done: l.done) },
                          onChoose: { model.chooseTalk($0) }, onAdvance: nil, onClose: { model.closeTalk() })
                    .id(t.node)
                    .transition(.opacity)
            }
            if let s = model.sheet { SheetHost(sheet: s) }
            if let r = model.report { ReportCard(report: r) }
        }
    }

    private func topBar(_ ui: UIState) -> some View {
        HStack(alignment: .top) {
            if let clue = ui.clue {
                Button { model.sheet = .journal } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed").font(.system(size: 13))
                        Text(clue).font(.avenir(14)).lineLimit(1)
                    }
                    .foregroundStyle(Color.cream.opacity(0.9))
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
            } else {
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if ui.hasFlashlight {
                    Button { model.game.toggleFlashlight(); model.haptics.tap() } label: { circleIcon(ui.flashOn ? "flashlight.on.fill" : "flashlight.off.fill") }
                        .accessibilityIdentifier("flashlight")
                }
                if ui.started {
                    Button { model.sheet = .map } label: { circleIcon("map") }
                        .accessibilityIdentifier("map")
                }
                if ui.ordersOK {
                    Button { model.sheet = .mission } label: { circleIcon("sun.horizon") }
                }
                Button { model.sheet = .pack } label: {
                    HStack(spacing: 8) {
                        if ui.wood > 0 {
                            HStack(spacing: 4) {
                                WoodIcon().frame(width: 18, height: 14)
                                Text("\(ui.wood)").font(.avenir(13, "DemiBold")).monospacedDigit()
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                        Image(systemName: "backpack").font(.system(size: 15))
                        Text("\(ui.packUsed)/\(Inventory.capacity)").font(.avenir(13, "DemiBold")).monospacedDigit()
                    }
                    .foregroundStyle(Color.cream)
                    .padding(.horizontal, 12).frame(height: 44)
                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    .overlay(Capsule().stroke(Color.amber.opacity(ui.packUsed >= Inventory.capacity ? 0.8 : 0.15)))
                    .animation(.spring(duration: 0.3), value: ui.wood > 0)
                }
                .accessibilityIdentifier("bag")
            }
        }
    }

    /// Health, stamina and (once he has one) flashlight battery: always in view, top left.
    private func meters(_ ui: UIState) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                meter("heart.fill", ui.health, Color(red: 0.95, green: 0.42, blue: 0.4), id: "meter.health")
                meter("bolt.fill", ui.stamina, Color.amber, id: "meter.stamina")
                meter("fork.knife", ui.hunger, Color(red: 0.7, green: 0.85, blue: 0.45), id: "meter.hunger")
                if ui.hasFlashlight {
                    Button { model.game.swapCell(); model.haptics.tap() } label: {
                        meter("battery.75", ui.battery, Color(red: 0.6, green: 0.85, blue: 1), id: "meter.battery")
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.cream.opacity(0.6)).frame(width: 14)
                    Text(ui.depth).font(.avenir(11, "DemiBold")).monospacedDigit().foregroundStyle(Color.cream.opacity(0.75))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.38)))
            Spacer()
        }
    }

    private func meter(_ icon: String, _ value: Int, _ tint: Color, id: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(value < 20 ? Color.red : tint).frame(width: 14)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(value < 20 ? Color.red.opacity(0.85) : tint).frame(width: g.size.width * CGFloat(max(0, min(100, value))) / 100)
                        .animation(.easeOut(duration: 0.3), value: value)
                }
            }
            .frame(width: 92, height: 7)
        }
        .accessibilityIdentifier(id)
    }

    private func sideButton(_ icon: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold))
            Text(caption).font(.avenir(9, "Bold")).tracking(1.2)
        }
        .foregroundStyle(Color.cream)
        .frame(width: 54, height: 54)
        .background(Circle().fill(Color.black.opacity(0.45)))
        .overlay(Circle().stroke(Color.amber.opacity(0.35), lineWidth: 1))
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16)).foregroundStyle(Color.cream)
            .frame(width: 42, height: 42)
            .background(Circle().fill(Color.black.opacity(0.4)))
    }

    private func controls(_ ui: UIState) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if ui.started {
                        HStack(spacing: 10) {
                            Button { model.sheet = .workbench; model.haptics.tap() } label: { sideButton("hammer.fill", "BUILD") }
                                .accessibilityIdentifier("build")
                            if ui.canGoInside {
                                Button { model.game.quartersTick(now: Date()); withAnimation(.easeInOut(duration: 0.5)) { model.showQuarters = true } } label: { sideButton("house.fill", "HOME") }
                                    .accessibilityIdentifier("quarters")
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.leading, 8)
                        .animation(.spring(duration: 0.3), value: ui.canGoInside)
                    }
                    MoveWheel(climbing: ui.climbing || ui.canClimb) { dx, run, up, down in
                        model.input.dx = dx; model.input.run = run; model.input.up = up; model.input.climbDown = down
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 14) {
                    if let what = ui.placing {
                        Button { model.game.cancelPlacing(); model.haptics.tap() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                                Text("Cancel \(what.lowercased())").font(.avenir(13, "DemiBold"))
                            }
                            .foregroundStyle(Color.cream.opacity(0.85))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                        }
                        .transition(.opacity)
                    }
                    if let c = ui.context {
                        Button { model.performContext() } label: {
                            Text(c.label).font(.avenir(c.prominent ? 17 : 15, "DemiBold")).foregroundStyle(Color.cream)
                                .padding(.horizontal, 18).frame(minHeight: 46)
                                .background(Capsule().fill(c.prominent ? Color.amber.opacity(0.32) : Color.black.opacity(0.45)))
                                .overlay(Capsule().stroke(Color.white.opacity(c.prominent ? 0.55 : 0.2), lineWidth: 1))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    // One DIG: it cuts wherever the wheel points (ahead, up or down). JUMP beside it.
                    HStack(alignment: .bottom, spacing: 14) {
                        HoldButton(id: "jump", onChange: { model.input.jump = $0 }) { p in
                            GlassCircle(size: 64, pressed: p, icon: AnyView(Arrowhead().frame(width: 20, height: 20).rotationEffect(.degrees(-90))), caption: "JUMP")
                        }
                        .padding(.bottom, 34)
                        HoldButton(id: "dig", onChange: { model.input.dig = $0 }) { p in
                            GlassCircle(size: 86, pressed: p, pulse: ui.pulseDown,
                                        icon: AnyView(DigIcon().frame(width: 38, height: 38)
                                            .rotationEffect(.degrees(Double(ui.aim) * 90))
                                            .scaleEffect(x: ui.aim != 0 ? 1 : CGFloat(ui.facing), y: 1)
                                            .animation(.spring(duration: 0.2), value: ui.aim)),
                                        caption: "DIG")
                        }
                    }
                }
                .animation(.spring(duration: 0.3), value: ui.context)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 26)
        }
    }

    private func planBar(_ text: String, ready: Bool) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Text(text).font(.avenir(15)).foregroundStyle(Color.cream).frame(maxWidth: .infinity, alignment: .leading)
                Button("Cancel") { model.cancelPlan() }.buttonStyle(PillStyle(prominent: false))
                Button("Send Max") { model.confirmPlan() }.buttonStyle(PillStyle(prominent: true)).disabled(!ready).opacity(ready ? 1 : 0.4)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.7)))
            .padding(.horizontal, 12).padding(.bottom, 14)
        }
    }

    private func jobBanner(_ title: String, _ ui: UIState) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Max is out working").font(.avenir(13, "DemiBold")).foregroundStyle(Color.amber)
                Text(title).font(.avenir(19, "DemiBold")).foregroundStyle(Color.cream)
                ProgressView(value: Double(ui.jobDone), total: Double(max(1, ui.jobTotal))).tint(Color.amber)
                Text("\(ui.jobDone) of \(ui.jobTotal) steps so far. He keeps going while the game is closed.").font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.8))
                Button("Take over now") { model.collectJob(recalled: true) }.buttonStyle(PillStyle(prominent: true))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.72)))
            .padding(.horizontal, 12).padding(.bottom, 14)
        }
    }
}

/// Three cut logs, stacked.
struct WoodIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let r = min(w / 3.4, h / 2.2) / 2
            for (x, y) in [(w * 0.3, h * 0.7), (w * 0.7, h * 0.7), (w * 0.5, h * 0.3)] {
                let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.72, green: 0.5, blue: 0.3)))
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: r * 0.45, dy: r * 0.45)), with: .color(Color(red: 0.45, green: 0.28, blue: 0.16)), lineWidth: 1)
            }
        }
    }
}


// MARK: the movement wheel

/// A thumb wheel: the touch sets a direction vector from the wheel's centre (unit = the ring's radius).
final class StickTouchView: UIView {
    var onChange: ((CGPoint) -> Void)?
    var radius: CGFloat = 60
    private var finger: UITouch?
    private var running = false
    override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = true; backgroundColor = .clear }
    required init?(coder: NSCoder) { fatalError() }
    private func report(_ t: UITouch) {
        let p = t.location(in: self)
        let v = CGPoint(x: (p.x - bounds.midX) / radius, y: (p.y - bounds.midY) / radius)
        let r = abs(v.x) > 1.0
        if r != running { running = r; if r { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.6) } }
        onChange?(v)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if finger == nil, let t = touches.first { finger = t; UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4); report(t) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { if let f = finger, touches.contains(f) { report(f) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
    private func release(_ touches: Set<UITouch>) {
        if let f = finger, touches.contains(f) { finger = nil; running = false; onChange?(.zero) }
    }
}

struct StickTouch: UIViewRepresentable {
    var radius: CGFloat
    var onChange: (CGPoint) -> Void
    func makeUIView(context: Context) -> StickTouchView { let v = StickTouchView(); v.radius = radius; v.onChange = onChange; return v }
    func updateUIView(_ v: StickTouchView, context: Context) { v.radius = radius; v.onChange = onChange }
}

/// Push the knob left or right to walk; past the ring to run (it costs stamina). Up to jump or climb,
/// down to climb down a ladder.
struct MoveWheel: View {
    var climbing: Bool
    var onChange: (_ dx: Int, _ run: Bool, _ up: Bool, _ down: Bool) -> Void
    @State private var v: CGPoint = .zero
    private let R: CGFloat = 58

    var body: some View {
        let mag = min(1.35, hypot(v.x, v.y))
        let ang = atan2(v.y, v.x)
        let knob = CGPoint(x: cos(ang) * mag * R, y: sin(ang) * mag * R)
        let running = abs(v.x) > 1.0
        ZStack {
            // run ring: lights up when the thumb is past it
            Circle().stroke(running ? Color.amber : Color.amber.opacity(0.18), style: StrokeStyle(lineWidth: running ? 3 : 1.2, dash: running ? [] : [4, 5]))
                .frame(width: R * 2.7, height: R * 2.7)
            Circle().fill(Color.black.opacity(0.42)).frame(width: R * 2, height: R * 2)
                .background(.ultraThinMaterial.opacity(0.3), in: Circle())
            Circle().stroke(Color.amber.opacity(0.3), lineWidth: 1.2).frame(width: R * 2, height: R * 2)
            // direction marks
            ForEach(0..<4) { i in
                Arrowhead().fill(Color.cream.opacity(0.35)).frame(width: 12, height: 12)
                    .rotationEffect(.degrees(Double(i) * 90))
                    .offset(x: i == 0 ? R - 14 : i == 2 ? -(R - 14) : 0, y: i == 1 ? R - 14 : i == 3 ? -(R - 14) : 0)
            }
            Text(running ? "RUN" : (v.y < -0.6 ? (climbing ? "CLIMB" : "UP") : (v.y > 0.6 ? "DOWN" : "")))
                .font(.avenir(10, "DemiBold")).tracking(1.2).foregroundStyle(Color.amber)
                .offset(y: -R - 22)
            Circle()
                .fill(RadialGradient(colors: [Color.cream.opacity(0.95), Color.amber.opacity(0.75)], center: .topLeading, startRadius: 2, endRadius: 40))
                .frame(width: 54, height: 54)
                .shadow(color: Color.amber.opacity(running ? 0.8 : 0.35), radius: running ? 16 : 8)
                .offset(x: knob.x, y: knob.y)
                .animation(.interactiveSpring(response: 0.12, dampingFraction: 0.7), value: knob)
            // Invisible targets for UI tests and VoiceOver: walking left and right.
            Color.clear.frame(width: 30, height: 30).offset(x: -R * 0.6)
                .accessibilityElement().accessibilityAddTraits(.isButton).accessibilityIdentifier("move.left").accessibilityLabel("move.left")
            Color.clear.frame(width: 30, height: 30).offset(x: R * 0.6)
                .accessibilityElement().accessibilityAddTraits(.isButton).accessibilityIdentifier("move.right").accessibilityLabel("move.right")
        }
        .frame(width: R * 2.9, height: R * 2.9)
        .overlay(StickTouch(radius: R) { p in
            v = p
            let dx = p.x < -0.3 ? -1 : (p.x > 0.3 ? 1 : 0)
            onChange(dx, abs(p.x) > 1.0, p.y < -0.6, p.y > 0.6)
        }.accessibilityHidden(true))
    }
}
