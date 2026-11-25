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
            LinearGradient(colors: [Color(red: 0.17, green: 0.09, blue: 0.14), Color(red: 0.43, green: 0.23, blue: 0.28), Color(red: 0.79, green: 0.51, blue: 0.38), Color(red: 0.48, green: 0.25, blue: 0.27), Color(red: 0.18, green: 0.09, blue: 0.14)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 1, green: 0.93, blue: 0.78), Color(red: 1, green: 0.77, blue: 0.55).opacity(0.5), .clear], center: UnitPoint(x: 0.5, y: 0.64), startRadius: 0, endRadius: 260)
            VStack(spacing: 0) {
                Spacer()
                Text("AFTERLIGHT").font(.avenir(46, "UltraLight")).tracking(14).foregroundStyle(Color(red: 1, green: 0.95, blue: 0.89))
                Text("214 miles below the surface, the power has just gone out.")
                    .font(.avenir(17)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).padding(.top, 14).frame(maxWidth: 300)
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
