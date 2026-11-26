import SwiftUI
import SpriteKit
import AfterlightCore

extension Color {
    static let amber = Color(red: 1, green: 0.79, blue: 0.55)
    static let cream = Color(red: 0.98, green: 0.92, blue: 0.84)
    static let glass = Color(red: 0.16, green: 0.08, blue: 0.11).opacity(0.55)
    static let violet = Color(red: 0.75, green: 0.62, blue: 1)
}

extension Font {
    static func avenir(_ size: CGFloat, _ weight: String = "Medium") -> Font { .custom("AvenirNext-\(weight)", size: size) }
}

struct RootView: View {
    @EnvironmentObject var model: GameModel
    @State private var scene: GameScene? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                    .defersSystemGestures(on: .all)
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                        .ignoresSafeArea()
                        .gesture(SpatialTapGesture().onEnded { v in
                            if model.game.planning != nil { model.pickPlanTarget(worldX: scene.worldX(fromScreenX: v.location.x)) }
                            else if abs(scene.worldX(fromScreenX: v.location.x) - model.game.max.pos.x) < 2.2 { withAnimation(.spring(duration: 0.3)) { model.showThoughts = true } }
                        })
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            if model.ui.ordersOK && model.game.planning == nil && model.game.order == nil { model.beginPlan() }
                        })
                }
                if !model.showTitle && !model.showIntro {
                    HUDView()
                        .transition(.opacity)
                }
                if let c = model.cards.first, !model.showTitle && !model.showIntro {
                    CheckpointCard(card: c).id(c.title + c.text)
                        .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .scale(scale: 0.9).combined(with: .opacity)))
                        .zIndex(5)
                }
                if model.showThoughts { ThoughtsCard().transition(.scale(scale: 0.95).combined(with: .opacity)) }
                if model.showQuarters { QuartersView().transition(.opacity) }
                if let b = model.banner { ChapterBanner(text: b).transition(.opacity) }
                if model.showTitle { TitleView().transition(.opacity) }
                if model.showIntro { CinematicView().transition(.opacity) }   // fills the screen itself
                if ProcessInfo.processInfo.arguments.contains("-uitest") {
                    Text(model.debugState).font(.system(size: 6)).opacity(0.02)
                        .accessibilityIdentifier("debug.state").accessibilityLabel(model.debugState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)
                }
            }
            .onAppear {
                if scene == nil {
                    let s = GameScene(game: model.game, size: geo.size)
                    s.model = model
                    model.scene = s
                    scene = s
                }
            }
        }
    }
}

struct TitleView: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        ZStack {
            // Darkness, and one flashlight beam picking out rock and drifting dust.
            Color(red: 0.035, green: 0.025, blue: 0.03)
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let origin = CGPoint(x: size.width * 0.12, y: size.height * 1.02)
                    let aim = -1.05 + 0.07 * sin(t * 0.35) + 0.02 * sin(t * 1.3)      // a slow, hand-held sweep
                    let spread = 0.2
                    let reach = size.height * 1.15
                    var cone = Path()
                    cone.move(to: origin)
                    cone.addLine(to: CGPoint(x: origin.x + cos(aim - spread) * reach, y: origin.y + sin(aim - spread) * reach))
                    cone.addLine(to: CGPoint(x: origin.x + cos(aim + spread) * reach, y: origin.y + sin(aim + spread) * reach))
                    cone.closeSubpath()
                    let center = CGPoint(x: origin.x + cos(aim) * reach * 0.55, y: origin.y + sin(aim) * reach * 0.55)
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 26))
                        l.fill(cone, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.86, blue: 0.62).opacity(0.55), Color(red: 0.9, green: 0.6, blue: 0.4).opacity(0.18), .clear]),
                                                           center: origin, startRadius: 0, endRadius: reach))
                    }
                    // where the beam lands: a warm pool on the rock
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 40))
                        l.fill(Path(ellipseIn: CGRect(x: center.x - 120, y: center.y - 90, width: 240, height: 180)),
                               with: .color(Color(red: 1, green: 0.8, blue: 0.55).opacity(0.22)))
                    }
                    // dust motes, only visible inside the beam
                    ctx.clip(to: cone)
                    for i in 0..<60 {
                        let fi = Double(i)
                        let px = (fi * 97.3).truncatingRemainder(dividingBy: Double(size.width))
                        let py = (fi * 151.7 + t * (6 + fi.truncatingRemainder(dividingBy: 5) * 3)).truncatingRemainder(dividingBy: Double(size.height))
                        let x = px + 10 * sin(t * 0.6 + fi), y = Double(size.height) - py
                        let r = 1.0 + fi.truncatingRemainder(dividingBy: 3)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(Color(red: 1, green: 0.93, blue: 0.8).opacity(0.7)))
                    }
                }
            }
            VStack(spacing: 0) {
                Spacer()
                Text("AFTERLIGHT").font(.avenir(40, "UltraLight")).tracking(9).lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.89))
                    .shadow(color: Color(red: 1, green: 0.8, blue: 0.5).opacity(0.5), radius: 12)
                Text("2,600 feet below the surface, the power has just gone out.")
                    .font(.avenir(17)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center).padding(.top, 14).frame(maxWidth: 300)
                VStack(spacing: 12) {
                    Button(model.hasSave ? "Continue" : "Begin") { if model.hasSave { model.start() } else { model.beginIntro() } }
                        .buttonStyle(PillStyle(prominent: true))
                    if model.hasSave {
                        Button("Start over") { model.resetForNewGame(); model.beginIntro() }.buttonStyle(PillStyle(prominent: false))
                    }
                }
                .padding(.top, 34)
                Spacer()
                Spacer()
            }
            .padding(24)
        }
        .ignoresSafeArea()
    }
}

struct PillStyle: ButtonStyle {
    var prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.avenir(17, "DemiBold"))
            .foregroundStyle(Color.cream)
            .padding(.horizontal, 22).frame(minHeight: 46)
            .background(Capsule().fill(prominent ? Color(red: 1, green: 0.67, blue: 0.4).opacity(0.3) : Color.glass))
            .overlay(Capsule().stroke(Color.white.opacity(prominent ? 0.5 : 0.22), lineWidth: 1))
            .background(.ultraThinMaterial.opacity(0.4), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct ChapterBanner: View {
    let text: String
    var body: some View {
        let parts = text.split(separator: "\n").map(String.init)
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 10) {
                Text(parts.first ?? "").font(.avenir(15, "DemiBold")).foregroundStyle(Color.amber)
                Text(parts.count > 1 ? parts[1] : "").font(.avenir(34, "UltraLight")).tracking(4).foregroundStyle(Color.cream)
            }
        }
        .allowsHitTesting(false)
    }
}


/// The moment a step lands: a stamped seal with light behind it, the step crossed off, and what's next.
struct CheckpointCard: View {
    @EnvironmentObject var model: GameModel
    let card: Checkpoint
    @State private var stamp = false
    @State private var check: CGFloat = 0
    @State private var strike: CGFloat = 0
    @State private var showNext = false

    var body: some View {
        let big = card.kind == .questDone
        let label: String = { switch card.kind { case .step: return "CHECKPOINT"; case .questDone: return "QUEST COMPLETE"; case .newQuest: return card.side ? "NEW SIDE QUEST" : "NEW QUEST" } }()
        VStack {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    TimelineView(.animation) { tl in
                        let t = tl.date.timeIntervalSinceReferenceDate
                        Canvas { ctx, size in
                            let c = CGPoint(x: size.width / 2, y: size.height / 2)
                            for i in 0..<12 {
                                let a = Double(i) / 12 * 2 * .pi + t * 0.6
                                var p = Path()
                                p.move(to: c)
                                p.addLine(to: CGPoint(x: c.x + cos(a - 0.12) * size.width, y: c.y + sin(a - 0.12) * size.width))
                                p.addLine(to: CGPoint(x: c.x + cos(a + 0.12) * size.width, y: c.y + sin(a + 0.12) * size.width))
                                ctx.fill(p, with: .color(Color.amber.opacity(0.13)))
                            }
                        }
                    }
                    .frame(width: 92, height: 92)
                    .mask(Circle())
                    Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.88, blue: 0.62), Color(red: 0.85, green: 0.55, blue: 0.28)], center: .topLeading, startRadius: 2, endRadius: 50))
                        .frame(width: 54, height: 54)
                        .overlay(Circle().stroke(Color(red: 1, green: 0.95, blue: 0.8), lineWidth: 2).padding(3))
                        .shadow(color: Color.amber.opacity(0.8), radius: 12)
                    if card.kind == .newQuest {
                        Image(systemName: "scroll.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Color(red: 0.3, green: 0.17, blue: 0.08))
                    } else {
                        CheckShape().trim(from: 0, to: check)
                            .stroke(Color(red: 0.3, green: 0.17, blue: 0.08), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            .frame(width: 24, height: 20)
                    }
                }
                .scaleEffect(stamp ? 1 : 2.2)
                .opacity(stamp ? 1 : 0)
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).font(.avenir(11, "Bold")).tracking(2.4).foregroundStyle(Color.amber)
                    Text(card.title).font(.avenir(big ? 21 : 18, "Bold")).foregroundStyle(Color.cream).lineLimit(1).minimumScaleFactor(0.7)
                    Text(card.text).font(.avenir(14)).foregroundStyle(Color.cream.opacity(card.kind == .newQuest ? 0.85 : 0.6))
                        .overlay(alignment: .leading) {
                            if card.kind != .newQuest {
                                GeometryReader { g in Rectangle().fill(Color.amber).frame(width: g.size.width * strike, height: 1.5).offset(y: g.size.height / 2) }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    if let n = card.next, showNext {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.turn.down.right").font(.system(size: 11, weight: .bold))
                            Text(n).font(.avenir(13, "DemiBold"))
                        }
                        .foregroundStyle(Color.cream)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.15, blue: 0.1), Color(red: 0.12, green: 0.07, blue: 0.07)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(LinearGradient(colors: [Color.amber.opacity(0.9), Color.amber.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .padding(.horizontal, 14)
            .padding(.top, 64)
            .onTapGesture { dismiss() }
            Spacer()
        }
        .task {
            model.audio.play(.swell)
            model.haptics.big()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.25)) { stamp = true }
            withAnimation(.easeOut(duration: 0.35).delay(0.5)) { check = 1 }
            withAnimation(.easeInOut(duration: 0.4).delay(0.8)) { strike = 1 }
            withAnimation(.spring(duration: 0.4).delay(1.2)) { showNext = true }
            try? await Task.sleep(for: .seconds(card.kind == .questDone ? 4.6 : 3.6))
            dismiss()
        }
    }

    private func dismiss() {
        guard model.cards.first == card else { return }
        withAnimation(.easeInOut(duration: 0.35)) { _ = model.cards.removeFirst() }
    }
}

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}
