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
                if let o = model.ui.outside, !model.showTitle { OutsideView(walk: o, thought: model.ui.thought).ignoresSafeArea().transition(.opacity) }
                if !model.showTitle && !model.showIntro {
                    HUDView()
                        .transition(.opacity)
                }
                if let c = model.cards.first, !model.showTitle && !model.showIntro {
                    CheckpointCard(card: c).id(c.title + c.text + "\(c.kind)")
                        .transition(.opacity)
                        .zIndex(5)
                }
                if model.sleeping { SleepView().transition(.opacity).zIndex(6) }
                if let lines = model.ui.epilogue { EpilogueView(lines: lines) { model.game.closeEpilogue() }.transition(.opacity).zIndex(7) }
                if model.showThoughts { ThoughtsCard().askingForHint().transition(.scale(scale: 0.95).combined(with: .opacity)) }
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


/// The moment a step lands, in the spirit of Journey: no box, no buttons. A glyph of light draws
/// itself, a few words fade in over the world, and then everything fades away on its own.
struct CheckpointCard: View {
    @EnvironmentObject var model: GameModel
    let card: Checkpoint
    @State private var draw: CGFloat = 0
    @State private var shown = false
    @State private var showNext = false

    var body: some View {
        let label: String = { switch card.kind { case .step: return "A STEP FORWARD"; case .questDone: return "COMPLETE"; case .newQuest: return card.side ? "SOMETHING ELSE" : "A NEW PATH" } }()
        VStack(spacing: 10) {
            ZStack {
                // soft bloom behind the glyph
                Circle().fill(RadialGradient(colors: [Color.amber.opacity(0.45), .clear], center: .center, startRadius: 2, endRadius: 60))
                    .frame(width: 130, height: 130).opacity(shown ? 1 : 0)
                Glyph(kind: card.kind).trim(from: 0, to: draw)
                    .stroke(Color(red: 1, green: 0.95, blue: 0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 56, height: 56)
                    .shadow(color: Color.amber, radius: 8)
            }
            .frame(height: 90)
            Text(label).font(.avenir(11, "DemiBold")).tracking(5).foregroundStyle(Color.amber.opacity(0.9))
            Text(card.title).font(.system(size: 26, weight: .light, design: .serif)).tracking(1)
                .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.9))
                .shadow(color: .black.opacity(0.8), radius: 10)
                .multilineTextAlignment(.center)
            Text(card.text).font(.system(size: 15, weight: .regular, design: .serif)).italic()
                .foregroundStyle(Color.cream.opacity(card.kind == .newQuest ? 0.85 : 0.6))
                .shadow(color: .black.opacity(0.8), radius: 8)
                .multilineTextAlignment(.center)
            if let n = card.next, showNext {
                Text(n).font(.system(size: 15, weight: .medium, design: .serif))
                    .foregroundStyle(Color.cream)
                    .shadow(color: .black.opacity(0.8), radius: 8)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 28)
        .background(
            // A soft pool of shadow behind the words, so a busy scene can never swallow them.
            Ellipse().fill(RadialGradient(colors: [.black.opacity(0.72), .black.opacity(0.45), .clear], center: .center, startRadius: 10, endRadius: 230))
                .padding(.horizontal, -30).padding(.vertical, -40)
                .blur(radius: 14)
        )
        .padding(.horizontal, 40)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 150)
        .allowsHitTesting(false)
        .onAppear {
            model.haptics.tap()
            withAnimation(.easeOut(duration: 1.0)) { shown = true }
            withAnimation(.easeInOut(duration: 1.4).delay(0.2)) { draw = 1 }
            withAnimation(.easeIn(duration: 0.8).delay(1.4)) { showNext = true }
        }
    }
}

/// Simple constellation-like glyphs drawn in one stroke.
struct Glyph: Shape {
    let kind: Checkpoint.Kind
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
        switch kind {
        case .step:
            // a ring with a rising stroke through it
            p.addEllipse(in: r.insetBy(dx: R * 0.25, dy: R * 0.25))
            p.move(to: CGPoint(x: c.x, y: r.maxY)); p.addLine(to: CGPoint(x: c.x, y: r.minY))
        case .questDone:
            // a star of eight rays
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi
                p.move(to: c); p.addLine(to: CGPoint(x: c.x + cos(a) * R, y: c.y + sin(a) * R))
            }
            p.addEllipse(in: r.insetBy(dx: R * 0.55, dy: R * 0.55))
        case .newQuest:
            // a path: three marks climbing to a point
            p.move(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: c.x - R * 0.3, y: c.y + R * 0.2))
            p.addLine(to: CGPoint(x: c.x + R * 0.2, y: c.y + R * 0.35)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addEllipse(in: CGRect(x: r.maxX - R * 0.3, y: r.minY - R * 0.05, width: R * 0.3, height: R * 0.3))
        }
        return p
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


/// Max turns in: the room dims, Zs drift up from his sleepy head, the clock races round, and he wakes rested.
struct SleepView: View {
    @EnvironmentObject var model: GameModel
    @State private var start = Date()
    var body: some View {
        TimelineView(.animation) { tl in
            let e = tl.date.timeIntervalSince(start)
            let k = min(1, max(0, (e - 0.4) / 2.6))          // how far through the night
            ZStack {
                Color(red: 0.03, green: 0.02, blue: 0.05).opacity(0.94).ignoresSafeArea()
                VStack(spacing: 26) {
                    // the clock, hands racing
                    ZStack {
                        Circle().fill(Color(red: 0.98, green: 0.93, blue: 0.83)).frame(width: 96, height: 96)
                        Circle().stroke(Color(red: 0.78, green: 0.6, blue: 0.4), lineWidth: 5).frame(width: 96, height: 96)
                        ForEach(0..<12) { i in
                            Capsule().fill(Ink.main.opacity(0.5)).frame(width: 2, height: 7).offset(y: -38).rotationEffect(.degrees(Double(i) * 30))
                        }
                        Capsule().fill(Ink.main).frame(width: 4, height: 26).offset(y: -11).rotationEffect(.degrees(k * 720))
                        Capsule().fill(Ink.accent).frame(width: 2.5, height: 36).offset(y: -16).rotationEffect(.degrees(k * 720 * 12))
                        Circle().fill(Ink.main).frame(width: 8, height: 8)
                    }
                    // Max asleep in bed, Zs rising
                    ZStack {
                        Canvas { ctx, size in
                            let w = size.width, h = size.height
                            let breathe = CGFloat(sin(e * 2.2)) * 2
                            ctx.fill(Path(roundedRect: CGRect(x: 10, y: h * 0.45, width: w - 20, height: h * 0.45), cornerRadius: 14), with: .color(Color(red: 0.48, green: 0.3, blue: 0.18)))
                            ctx.fill(Path(roundedRect: CGRect(x: 18, y: h * 0.38, width: w - 36, height: h * 0.3), cornerRadius: 12), with: .color(Color(red: 0.96, green: 0.93, blue: 0.88)))
                            ctx.fill(Path(roundedRect: CGRect(x: 24, y: h * 0.3, width: 70, height: 34), cornerRadius: 12), with: .color(.white))
                            // head with the beanie
                            ctx.fill(Path(ellipseIn: CGRect(x: 40, y: h * 0.22, width: 44, height: 40)), with: .color(Color(red: 0.95, green: 0.82, blue: 0.7)))
                            ctx.fill(Path(ellipseIn: CGRect(x: 36, y: h * 0.18, width: 50, height: 28)), with: .color(Color(red: 0.29, green: 0.23, blue: 0.36)))
                            ctx.fill(Path(ellipseIn: CGRect(x: 30, y: h * 0.16, width: 14, height: 14)), with: .color(Color(red: 0.91, green: 0.64, blue: 0.23)))
                            var lid = Path(); lid.move(to: CGPoint(x: 66, y: h * 0.22 + 24)); lid.addQuadCurve(to: CGPoint(x: 76, y: h * 0.22 + 24), control: CGPoint(x: 71, y: h * 0.22 + 28))
                            ctx.stroke(lid, with: .color(Color(red: 0.2, green: 0.12, blue: 0.1)), lineWidth: 1.6)
                            // quilt over him, rising and falling
                            ctx.fill(Path(roundedRect: CGRect(x: 80, y: h * 0.36 - breathe, width: w - 104, height: h * 0.34 + breathe), cornerRadius: 14), with: .color(Color(red: 0.31, green: 0.48, blue: 0.63)))
                            ctx.fill(Path(CGRect(x: 80, y: h * 0.36 - breathe, width: w - 104, height: 6)), with: .color(Color(red: 0.95, green: 0.84, blue: 0.62)))
                            // Zs
                            for i in 0..<3 {
                                let ph = (e * 0.55 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                                let zx = 76 + CGFloat(ph) * 70 + CGFloat(sin(ph * 6 + Double(i))) * 8
                                let zy = h * 0.2 - CGFloat(ph) * h * 0.55
                                ctx.draw(Text("z").font(.system(size: 14 + CGFloat(ph) * 16, weight: .heavy, design: .rounded)).foregroundColor(Color(red: 0.98, green: 0.93, blue: 0.83).opacity(1 - ph)), at: CGPoint(x: zx, y: zy))
                            }
                        }
                    }
                    .frame(width: 260, height: 150)
                    // strength coming back
                    VStack(spacing: 8) {
                        bar("heart.fill", Color(red: 0.95, green: 0.42, blue: 0.4), 0.3 + 0.7 * k * (model.game.max.health / 100))
                        bar("bolt.fill", Color.amber, 0.2 + 0.8 * k)
                    }
                    .frame(width: 220)
                    Text(k < 1 ? "Sleeping…" : "Rested").font(.avenir(18, "DemiBold")).foregroundStyle(Color.cream)
                }
            }
        }
        .onAppear { start = Date() }
        .onTapGesture { }   // swallow taps while asleep
    }
    private func bar(_ icon: String, _ c: Color, _ v: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(c).frame(width: 16)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(c).frame(width: g.size.width * CGFloat(min(1, max(0, v))))
                }
            }
            .frame(height: 8)
        }
    }
}
