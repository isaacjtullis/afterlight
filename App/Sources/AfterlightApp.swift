import SwiftUI

@main
struct AfterlightApp: App {
    @StateObject private var model = GameModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active: model.didBecomeActive()
            case .background: model.saveNow(cloud: true)
            default: break
            }
        }
    }
}
