import SwiftUI
import AfterlightCore

/// A button you hold. Several can be held at once (walk + dig).
struct HoldButton<Label: View>: View {
    var onChange: (Bool) -> Void
    @ViewBuilder var label: (Bool) -> Label
    @State private var down = false
    var body: some View {
        label(down)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !down { down = true; onChange(true) } }
                .onEnded { _ in down = false; onChange(false) })
    }
}

struct GlassCircle: View {
    var size: CGFloat
    var pressed: Bool
    var pulse = false
    var icon: AnyView
    var body: some View {
        ZStack {
            Circle().fill(pressed ? Color(red: 1, green: 0.85, blue: 0.7).opacity(0.3) : Color.white.opacity(0.08))
            Circle().stroke(pulse ? Color.violet : Color.white.opacity(0.22), lineWidth: pulse ? 1.5 : 1)
            icon.foregroundStyle(Color.cream)
        }
        .frame(width: size, height: size)
        .background(.ultraThinMaterial.opacity(0.35), in: Circle())
        .shadow(color: pulse ? Color.violet.opacity(0.6) : .black.opacity(0.25), radius: pulse ? 14 : 8)
        .scaleEffect(pressed ? 0.92 : 1)
        .animation(.easeOut(duration: 0.1), value: pressed)
    }
}

struct ShovelIcon: View {
    var down = false
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 24
            var p = Path()
            p.move(to: CGPoint(x: 2.5 * s, y: 9.5 * s)); p.addLine(to: CGPoint(x: 2.5 * s, y: 14.5 * s))
            p.move(to: CGPoint(x: 2.5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 11.5 * s, y: 12 * s))
            ctx.stroke(p, with: .color(.cream), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            var b = Path()
            b.move(to: CGPoint(x: 11.5 * s, y: 8.6 * s))
            b.addCurve(to: CGPoint(x: 21.5 * s, y: 12 * s), control1: CGPoint(x: 15.7 * s, y: 8.4 * s), control2: CGPoint(x: 19.3 * s, y: 9.8 * s))
            b.addCurve(to: CGPoint(x: 11.5 * s, y: 15.4 * s), control1: CGPoint(x: 19.3 * s, y: 14.2 * s), control2: CGPoint(x: 15.7 * s, y: 15.6 * s))
            b.closeSubpath()
            ctx.fill(b, with: .color(.cream))
        }
        .rotationEffect(.degrees(down ? 90 : 0))
    }
}

struct HUDView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        let ui = model.ui
        ZStack {
            VStack(spacing: 10) {
                topBar(ui)
                if !ui.hint.isEmpty {
                    Text(ui.hint)
                        .font(.avenir(15)).foregroundStyle(Color.cream).multilineTextAlignment(.center)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.5)))
                        .frame(maxWidth: 420)
                        .transition(.opacity)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.3), value: ui.hint)

            if ui.jobTitle == nil && ui.planning == nil && !ui.cinematic {
                controls(ui)
            }
            if let text = ui.planning { planBar(text, ready: ui.planReady) }
            if let t = ui.jobTitle { jobBanner(t, ui) }
            if let c = model.conversation { ConversationCard(convo: c) }
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
                .frame(maxWidth: 260, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 10) {
                if ui.ordersOK {
                    Button { model.sheet = .mission } label: { circleIcon("sun.horizon") }
                }
                Button { model.sheet = .pack } label: {
                    ZStack(alignment: .topTrailing) {
                        circleIcon("backpack")
                        if ui.packUsed > 0 {
                            Text("\(ui.packUsed)/\(Inventory.capacity)").font(.avenir(10, "DemiBold")).foregroundStyle(.black)
                                .padding(.horizontal, 4).background(Capsule().fill(Color.amber)).offset(x: 6, y: -4)
                        }
                    }
                }
            }
        }
    }

    private func circleIcon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 16)).foregroundStyle(Color.cream)
            .frame(width: 44, height: 44)
            .background(Circle().fill(Color.black.opacity(0.4)))
    }

    private func controls(_ ui: UIState) -> some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    if ui.showStamina {
                        HStack(spacing: 8) {
                            Text("Stamina").font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.8))
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.1))
                                    Capsule().fill(ui.stamina < 15 ? Color.red.opacity(0.8) : Color.amber).frame(width: g.size.width * CGFloat(ui.stamina) / CGFloat(max(1, ui.staminaMax)))
                                }
                            }.frame(width: 86, height: 7)
                        }
                    }
                    if ui.canClimb || ui.hasPick {
                        HoldButton(onChange: { model.input.up = $0 }) { p in
                            GlassCircle(size: 56, pressed: p, icon: AnyView(Image(systemName: "chevron.up").font(.system(size: 20, weight: .medium))))
                        }
                        .padding(.leading, 52)
                    }
                    HStack(spacing: 0) {
                        HoldButton(onChange: { v in model.input.dx = v ? -1 : (model.input.dx == -1 ? 0 : model.input.dx) }) { p in
                            Image(systemName: "chevron.left").font(.system(size: 22, weight: .light)).foregroundStyle(Color.cream)
                                .frame(width: 82, height: 72).background(p ? Color.white.opacity(0.14) : .clear)
                        }
                        Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 36)
                        HoldButton(onChange: { v in model.input.dx = v ? 1 : (model.input.dx == 1 ? 0 : model.input.dx) }) { p in
                            Image(systemName: "chevron.right").font(.system(size: 22, weight: .light)).foregroundStyle(Color.cream)
                                .frame(width: 82, height: 72).background(p ? Color.white.opacity(0.14) : .clear)
                        }
                    }
                    .clipShape(Capsule())
                    .background(.ultraThinMaterial.opacity(0.35), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    if let c = ui.context {
                        Button { model.performContext() } label: {
                            Text(c.label).font(.avenir(c.prominent ? 17 : 15, "DemiBold")).foregroundStyle(Color.cream)
                                .padding(.horizontal, 18).frame(minHeight: 46)
                                .background(Capsule().fill(c.prominent ? Color(red: 1, green: 0.67, blue: 0.4).opacity(0.32) : Color.black.opacity(0.45)))
                                .overlay(Capsule().stroke(Color.white.opacity(c.prominent ? 0.55 : 0.2), lineWidth: 1))
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                    HStack(alignment: .bottom, spacing: 14) {
                        HoldButton(onChange: { model.input.down = $0 }) { p in
                            GlassCircle(size: 64, pressed: p, pulse: ui.pulseDown, icon: AnyView(ShovelIcon(down: true).frame(width: 30, height: 30)))
                        }
                        .padding(.bottom, 40)
                        HoldButton(onChange: { model.input.dig = $0 }) { p in
                            GlassCircle(size: 88, pressed: p, icon: AnyView(ShovelIcon().frame(width: 44, height: 44).scaleEffect(x: CGFloat(ui.facing), y: 1)))
                        }
                    }
                }
                .animation(.spring(duration: 0.3), value: ui.context)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
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
