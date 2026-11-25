import SwiftUI
import UIKit
import AfterlightCore

/// The opening story. Behaves like an Instagram story: segmented progress, tap right/left, hold to pause,
/// swipe down to close.
struct CinematicView: View {
    @EnvironmentObject var model: GameModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var player = IntroPlayer()
    @State private var lastTick = Date()
    @State private var drag: CGFloat = 0
    @State private var touchStart: Date? = nil
    @State private var closing = false
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()
    private let tapHaptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { geo in
            let pull = max(0, drag)
            let k = min(1, pull / 400)
            ZStack {
                Color.black.opacity(1 - k * 0.6).ignoresSafeArea()
                story(geo)
                    .clipShape(RoundedRectangle(cornerRadius: pull > 0 ? 28 : 0, style: .continuous))
                    .scaleEffect(1 - k * 0.18)
                    .offset(y: pull * 0.9)
                    .opacity(closing ? 0 : 1)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(storyGesture(width: geo.size.width))
        }
        .onReceive(timer) { now in
            let dt = min(0.1, now.timeIntervalSince(lastTick))
            lastTick = now
            player.tick(dt)
        }
        .onChange(of: phase) { _, p in player.backgrounded = p != .active }
        .onChange(of: player.index) { _, _ in tapHaptic.impactOccurred(intensity: 0.6) }
        .onAppear {
            lastTick = Date()
            tapHaptic.prepare()
            if model.smokeSkipIntro { DispatchQueue.main.asyncAfter(deadline: .now() + 3) { player.skip() } }
        }
        .statusBarHidden(true)
    }

    private func story(_ geo: GeometryProxy) -> some View {
        let safeTop = geo.safeAreaInsets.top, safeBottom = geo.safeAreaInsets.bottom
        let chrome = !player.held && drag == 0
        return ZStack {
            Color.black
            IntroArt(scene: player.scene, index: player.index, size: geo.size)
                .scaleEffect(reduceMotion ? 1 : 1.04 + 0.06 * player.progress)
                .offset(x: reduceMotion ? 0 : CGFloat(player.index % 2 == 0 ? -1 : 1) * 12 * CGFloat(player.progress - 0.5),
                        y: reduceMotion ? 0 : -10 * CGFloat(player.progress))
                .id(player.index)
                .transition(.opacity)
                .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.6), value: player.index)
            // soft shade where the words sit, like Stories
            LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    progressBar
                    header
                }
                .padding(.top, safeTop + 8).padding(.horizontal, 10)
                .opacity(chrome ? 1 : 0)
                if player.scene.bubble == .top { caption.padding(.top, 14) }
                Spacer(minLength: 0)
                if player.scene.bubble == .bottom { caption }
                if player.waitingForCandle {
                    Button { close() } label: {
                        Label("Light the candle", systemImage: "flame.fill")
                            .font(.avenir(18, "DemiBold"))
                            .padding(.horizontal, 26).frame(height: 54)
                            .background(Capsule().fill(Color(red: 1, green: 0.72, blue: 0.42).opacity(0.9)))
                            .foregroundStyle(Color(red: 0.16, green: 0.08, blue: 0.06))
                            .shadow(color: Color(red: 1, green: 0.7, blue: 0.4).opacity(0.6), radius: 18)
                    }
                    .padding(.top, 18)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .accessibilityIdentifier("intro.candle")
                }
                Text(player.waitingForCandle ? " " : "Swipe down to close")
                    .font(.avenir(12)).foregroundStyle(.white.opacity(0.5))
                    .padding(.top, 10)
                    .padding(.bottom, safeBottom + 14)
                    .opacity(chrome ? 1 : 0)
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: player.waitingForCandle)
            .animation(.easeOut(duration: 0.2), value: chrome)
        }
        .frame(width: geo.size.width, height: geo.size.height)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.75, blue: 0.45), Color(red: 0.75, green: 0.35, blue: 0.3)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "flame.fill").font(.system(size: 14)).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Afterlight").font(.avenir(14, "DemiBold"))
                Text("How the surface fell · \(player.index + 1) of \(player.scenes.count)").font(.avenir(11)).opacity(0.75)
            }
            Spacer()
            Button { player.paused.toggle() } label: {
                Image(systemName: player.paused ? "play.fill" : "pause.fill").font(.system(size: 15, weight: .semibold)).frame(width: 40, height: 40)
            }
            .accessibilityLabel(player.paused ? "Play story" : "Pause story")
            Button { close() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Close story")
            .accessibilityIdentifier("intro.close")
        }
        .foregroundStyle(.white)
    }

    private var progressBar: some View {
        HStack(spacing: 3) {
            ForEach(0..<player.scenes.count, id: \.self) { i in
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3))
                        Capsule().fill(Color.white)
                            .frame(width: g.size.width * CGFloat(i < player.index ? 1 : (i == player.index ? player.progress : 0)))
                    }
                }
                .frame(height: 2.5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Scene \(player.index + 1) of \(player.scenes.count)")
    }

    private var caption: some View {
        Text(player.scene.text)
            .font(.avenir(player.index == 0 ? 30 : 20, player.index == 0 ? "Regular" : "Medium"))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial.opacity(0.55)))
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 16)
            .id("caption\(player.index)")
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 14)), removal: .opacity))
            .animation(.easeOut(duration: 0.45), value: player.index)
            .accessibilityIdentifier("intro.caption")
    }

    /// One gesture for everything a thumb does on a story: tap left/right, hold to pause, swipe down to close.
    private func storyGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if touchStart == nil {
                    let start = Date()
                    touchStart = start
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { if touchStart == start && drag == 0 { player.held = true } }
                }
                if v.translation.height > 8 && abs(v.translation.height) > abs(v.translation.width) {
                    drag = v.translation.height
                    player.held = true
                }
            }
            .onEnded { v in
                let wasHeld = player.held
                let dragged = drag
                touchStart = nil
                player.held = false
                if dragged > 0 {
                    if dragged > 120 || v.predictedEndTranslation.height > 260 { close() }
                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { drag = 0 } }
                    return
                }
                guard !wasHeld, abs(v.translation.width) < 12 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    if v.location.x < width * 0.33 { player.back() } else { player.next() }
                }
            }
    }

    private func close() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeIn(duration: 0.3)) { drag = 900; closing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.finishIntro() }
    }
}

/// The illustration for a scene. Uses the artwork if it's in the asset catalog (01-valley … 12-max),
/// otherwise a painted stand-in in the same mood and composition.
struct IntroArt: View {
    let scene: IntroScene
    let index: Int
    let size: CGSize

    var body: some View {
        if let img = UIImage(named: scene.image) {
            Image(uiImage: img).resizable().scaledToFill().frame(width: size.width, height: size.height)
        } else {
            Canvas { ctx, sz in IntroPainter.paint(index, ctx: &ctx, size: sz) }
                .frame(width: size.width, height: size.height)
        }
    }
}

enum IntroPainter {
    static func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r / 255, green: g / 255, blue: b / 255).opacity(a) }

    static func paint(_ i: Int, ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let full = Path(CGRect(origin: .zero, size: size))
        func sky(_ top: Color, _ bottom: Color) {
            ctx.fill(full, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        }
        func mountain(_ peak: CGFloat, _ col: Color, mine: Bool = false) {
            var p = Path()
            p.move(to: CGPoint(x: -20, y: h * 0.72))
            p.addLine(to: CGPoint(x: w * 0.28, y: h * (peak + 0.12)))
            p.addLine(to: CGPoint(x: w * 0.52, y: h * peak))
            p.addLine(to: CGPoint(x: w * 0.78, y: h * (peak + 0.15)))
            p.addLine(to: CGPoint(x: w + 20, y: h * 0.68))
            p.addLine(to: CGPoint(x: w + 20, y: h)); p.addLine(to: CGPoint(x: -20, y: h)); p.closeSubpath()
            ctx.fill(p, with: .color(col))
            if mine {
                ctx.fill(Path(roundedRect: CGRect(x: w * 0.47, y: h * 0.6, width: w * 0.08, height: h * 0.05), cornerRadius: 10), with: .color(c(20, 12, 10)))
                ctx.fill(Path(CGRect(x: w * 0.5, y: h * 0.62, width: 4, height: 6)), with: .color(c(255, 200, 120)))
            }
        }
        func ground(_ col: Color, _ y: CGFloat = 0.78) { ctx.fill(Path(CGRect(x: 0, y: h * y, width: w, height: h * (1 - y))), with: .color(col)) }
        func person(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat = 1, _ col: Color = c(30, 20, 18)) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3 * s, y: y - 17 * s, width: 6 * s, height: 6 * s)), with: .color(col))
            ctx.fill(Path(roundedRect: CGRect(x: x - 3.5 * s, y: y - 11 * s, width: 7 * s, height: 11 * s), cornerRadius: 2 * s), with: .color(col))
        }
        func glow(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ col: Color) {
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .radialGradient(Gradient(colors: [col, col.opacity(0)]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
        func houses(_ y: CGFloat, lit: Bool) {
            for k in 0..<7 {
                let x = w * (0.08 + 0.13 * CGFloat(k)), hh = h * 0.035
                ctx.fill(Path(CGRect(x: x, y: y - hh, width: w * 0.08, height: hh)), with: .color(c(36, 24, 26)))
                if lit && k % 2 == 0 { ctx.fill(Path(CGRect(x: x + w * 0.03, y: y - hh * 0.6, width: 4, height: 4)), with: .color(c(255, 210, 140))) }
            }
        }
        switch i {
        case 0: // the valley
            sky(c(242, 186, 140), c(120, 70, 74)); glow(w * 0.5, h * 0.3, w * 0.6, c(255, 230, 190, 0.6))
            mountain(0.32, c(92, 58, 60), mine: true); houses(h * 0.8, lit: true); ground(c(60, 38, 40), 0.8)
        case 1: // a rumor between shifts
            sky(c(70, 46, 52), c(30, 20, 26)); mountain(0.3, c(46, 30, 34), mine: true); ground(c(34, 22, 26), 0.8)
            person(w * 0.45, h * 0.8); person(w * 0.52, h * 0.8); glow(w * 0.485, h * 0.76, 40, c(255, 190, 110, 0.5))
        case 2: // empty shifts
            sky(c(60, 44, 50), c(26, 18, 22)); mountain(0.3, c(42, 28, 32), mine: true); ground(c(30, 20, 24), 0.8)
            for k in 0..<6 { ctx.fill(Path(CGRect(x: w * (0.2 + 0.1 * CGFloat(k)), y: h * 0.74, width: 3, height: h * 0.06)), with: .color(c(70, 50, 44))) }
            person(w * 0.3, h * 0.8)
        case 3: // empty shelves, a line anyway
            sky(c(40, 32, 36), c(18, 14, 16)); ground(c(28, 22, 24), 0.82)
            for k in 0..<4 { ctx.fill(Path(CGRect(x: w * 0.1, y: h * (0.3 + 0.1 * CGFloat(k)), width: w * 0.8, height: 4)), with: .color(c(90, 76, 66))) }
            for k in 0..<9 { person(w * (0.12 + 0.09 * CGFloat(k)), h * 0.82, 1.2) }
        case 4: // the road barrier
            sky(c(110, 76, 70), c(40, 26, 30)); mountain(0.36, c(64, 42, 44)); ground(c(44, 30, 32), 0.76)
            ctx.fill(Path(CGRect(x: w * 0.2, y: h * 0.72, width: w * 0.6, height: h * 0.02)), with: .color(c(200, 160, 90)))
            for k in 0..<5 { ctx.fill(Path(CGRect(x: w * (0.22 + 0.14 * CGFloat(k)), y: h * 0.72, width: 6, height: h * 0.05)), with: .color(c(90, 70, 50))) }
            person(w * 0.15, h * 0.86, 0.8); person(w * 0.86, h * 0.86, 0.8)
        case 5: // the rich dig in
            sky(c(30, 22, 26), c(12, 8, 10)); mountain(0.22, c(52, 36, 34))
            for k in 0..<3 { let x = w * (0.3 + 0.18 * CGFloat(k)); ctx.fill(Path(roundedRect: CGRect(x: x, y: h * 0.45, width: w * 0.12, height: h * 0.06), cornerRadius: 6), with: .color(c(255, 214, 140, 0.85))) }
            ground(c(26, 18, 18), 0.82); for k in 0..<4 { person(w * (0.35 + 0.08 * CGFloat(k)), h * 0.82, 0.9) }
        case 6: // the miners' own shelter, off the maps
            sky(c(20, 14, 16), c(8, 6, 8)); mountain(0.22, c(40, 28, 28))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.15, y: h * 0.62, width: w * 0.12, height: h * 0.05), cornerRadius: 6), with: .color(c(255, 180, 100, 0.6)))
            glow(w * 0.21, h * 0.645, 70, c(255, 170, 90, 0.4)); ground(c(22, 14, 14), 0.82)
            for k in 0..<5 { person(w * (0.3 + 0.07 * CGFloat(k)), h * 0.82, 0.8) }
        case 7: // the strikes
            sky(c(150, 70, 50), c(40, 18, 20)); glow(w * 0.3, h * 0.6, 160, c(255, 140, 60, 0.6)); glow(w * 0.72, h * 0.66, 120, c(255, 120, 50, 0.5))
            mountain(0.34, c(52, 30, 30)); houses(h * 0.8, lit: false); ground(c(30, 16, 16), 0.8)
        case 8: // the collapse
            sky(c(60, 40, 40), c(20, 12, 12)); mountain(0.3, c(46, 30, 30))
            for k in 0..<30 { let x = w * 0.5 + CGFloat((k * 37) % 120) - 60, y = h * 0.62 + CGFloat((k * 53) % 60); ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 10, height: 8)), with: .color(c(80, 58, 50))) }
            ground(c(26, 16, 16), 0.82)
        case 9: // the radio
            sky(c(16, 12, 14), c(6, 4, 6)); glow(w * 0.5, h * 0.6, 140, c(255, 170, 90, 0.35))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.38, y: h * 0.56, width: w * 0.24, height: h * 0.07), cornerRadius: 6), with: .color(c(70, 52, 40)))
            ctx.fill(Path(ellipseIn: CGRect(x: w * 0.42, y: h * 0.575, width: 18, height: 18)), with: .color(c(200, 160, 100)))
            person(w * 0.32, h * 0.66, 1.3)
        case 10: // generations underground
            sky(c(22, 16, 16), c(8, 6, 6)); glow(w * 0.5, h * 0.62, 180, c(255, 180, 100, 0.3)); ground(c(28, 18, 16), 0.8)
            for k in 0..<6 { person(w * (0.2 + 0.12 * CGFloat(k)), h * 0.8, k < 2 ? 1.25 : 1.0) }
        default: // Max at the grave, candle lit
            sky(c(10, 7, 7), c(4, 3, 3)); ground(c(24, 16, 14), 0.78)
            var mound = Path(); mound.addEllipse(in: CGRect(x: w * 0.42, y: h * 0.75, width: w * 0.3, height: h * 0.06)); ctx.fill(mound, with: .color(c(60, 40, 30)))
            ctx.fill(Path(CGRect(x: w * 0.68, y: h * 0.66, width: 5, height: h * 0.1)), with: .color(c(110, 80, 56)))
            person(w * 0.32, h * 0.79, 1.6, c(40, 26, 22))
            glow(w * 0.38, h * 0.77, 90, c(255, 190, 110, 0.65))
            ctx.fill(Path(CGRect(x: w * 0.375, y: h * 0.765, width: 4, height: 8)), with: .color(c(255, 236, 190)))
        }
    }
}
