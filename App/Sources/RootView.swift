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
                if let scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                        .ignoresSafeArea()
                        .gesture(SpatialTapGesture().onEnded { v in
                            if model.game.planning != nil { model.pickPlanTarget(worldX: scene.worldX(fromScreenX: v.location.x)) }
                        })
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                            if model.ui.ordersOK && model.game.planning == nil && model.game.order == nil { model.beginPlan() }
                        })
                }
                if !model.showTitle {
                    HUDView()
                        .transition(.opacity)
                }
                if let b = model.banner { ChapterBanner(text: b).transition(.opacity) }
                if model.showTitle { TitleView().transition(.opacity) }
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
        .ignoresSafeArea()
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
                Text("214 miles below the surface, the power has just gone out.")
                    .font(.avenir(17)).foregroundStyle(.white.opacity(0.75)).multilineTextAlignment(.center).padding(.top, 14).frame(maxWidth: 300)
                VStack(spacing: 12) {
                    Button(model.hasSave ? "Continue" : "Light the candle") { model.start() }
                        .buttonStyle(PillStyle(prominent: true))
                    if model.hasSave {
                        Button("Start over") { model.newGame() }.buttonStyle(PillStyle(prominent: false))
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
