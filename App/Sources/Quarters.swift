import SwiftUI
import AfterlightCore

/// The living quarters, seen from above: tap a station and Max walks over to it.
struct QuartersView: View {
    @EnvironmentObject var model: GameModel
    @State private var maxPos = CGPoint(x: 4.5, y: 5.6)
    @State private var facing: CGFloat = 1
    @State private var walking = false
    @State private var at: Station? = nil
    @State private var tick = 0

    /// Room is 9 × 7 units; stations sit on its edges and in the middle.
    static let spots: [Station: CGPoint] = [
        .bed: CGPoint(x: 1.3, y: 1.2), .pantry: CGPoint(x: 3.4, y: 0.9), .stove: CGPoint(x: 5.5, y: 0.9),
        .lamps: CGPoint(x: 7.8, y: 1.0), .bench: CGPoint(x: 7.8, y: 3.4), .storage: CGPoint(x: 7.8, y: 5.4),
        .garden: CGPoint(x: 1.4, y: 4.3), .water: CGPoint(x: 4.5, y: 3.3), .door: CGPoint(x: 4.5, y: 6.6),
    ]

    var body: some View {
        let g = model.game
        GeometryReader { geo in
            let unit = min(geo.size.width / 9.4, (geo.size.height - 260) / 7.4)
            let origin = CGPoint(x: (geo.size.width - unit * 9) / 2, y: geo.safeAreaInsets.top + 70)
            let sp: (CGPoint) -> CGPoint = { p in CGPoint(x: origin.x + p.x * unit, y: origin.y + p.y * unit) }
            ZStack(alignment: .topLeading) {
                Color(red: 0.07, green: 0.05, blue: 0.06).ignoresSafeArea()
                // Floor and walls
                Canvas { ctx, _ in
                    let room = CGRect(x: origin.x, y: origin.y, width: unit * 9, height: unit * 7)
                    ctx.fill(Path(roundedRect: room.insetBy(dx: -unit * 0.35, dy: -unit * 0.35), cornerRadius: unit * 0.4), with: .color(Color(red: 0.2, green: 0.17, blue: 0.19)))
                    ctx.fill(Path(room), with: .color(Color(red: 0.36, green: 0.28, blue: 0.24)))
                    for y in 0..<7 { for x in 0..<9 where (x + y) % 2 == 0 {
                        ctx.fill(Path(CGRect(x: room.minX + CGFloat(x) * unit, y: room.minY + CGFloat(y) * unit, width: unit, height: unit)), with: .color(Color.black.opacity(0.06)))
                    } }
                    // rug
                    ctx.fill(Path(roundedRect: CGRect(x: room.minX + unit * 3, y: room.minY + unit * 4.3, width: unit * 3, height: unit * 1.8), cornerRadius: unit * 0.3), with: .color(Color(red: 0.55, green: 0.25, blue: 0.2).opacity(0.55)))
                    if g.quarters.decor.contains("table") {
                        ctx.fill(Path(roundedRect: CGRect(x: room.minX + unit * 4.0, y: room.minY + unit * 4.7, width: unit * 1.2, height: unit * 0.8), cornerRadius: unit * 0.12), with: .color(Color(red: 0.55, green: 0.37, blue: 0.22)))
                        ctx.fill(Path(ellipseIn: CGRect(x: room.minX + unit * 5.35, y: room.minY + unit * 4.85, width: unit * 0.5, height: unit * 0.5)), with: .color(Color(red: 0.45, green: 0.3, blue: 0.18)))
                    }
                    // door gap
                    ctx.fill(Path(CGRect(x: room.minX + unit * 4, y: room.maxY - 2, width: unit, height: unit * 0.4)), with: .color(Color.black))
                }
                ForEach(Station.allCases, id: \.self) { s in
                    stationView(s, g: g, unit: unit)
                        .position(sp(Self.spots[s]!))
                        .onTapGesture { go(to: s) }
                        .accessibilityIdentifier("station.\(s.rawValue)")
                }
                // Max, from above
                TopDownMax(walking: walking, facing: facing)
                    .frame(width: unit * 0.9, height: unit * 0.9)
                    .position(sp(maxPos))
                // Lighting: the lamp rack's charge decides how bright the room is.
                RadialGradient(colors: [.clear, Color.black.opacity(0.75)], center: .center, startRadius: unit * (1.5 + 3 * CGFloat(g.quarters.charge / 100)), endRadius: unit * 7)
                    .allowsHitTesting(false).ignoresSafeArea()
                header(g).padding(.top, geo.safeAreaInsets.top + 6).padding(.horizontal, 16)
                VStack { Spacer(); card(g).padding(.horizontal, 12).padding(.bottom, geo.safeAreaInsets.bottom + 10) }
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            model.game.quartersTick(now: Date()); tick += 1
        }
    }

    private func go(to s: Station) {
        guard let target = Self.spots[s] else { return }
        let dest = CGPoint(x: target.x, y: min(6.2, target.y + 0.9))
        let d = hypot(dest.x - maxPos.x, dest.y - maxPos.y)
        facing = dest.x >= maxPos.x ? 1 : -1
        walking = true
        model.haptics.tap()
        withAnimation(.linear(duration: max(0.15, d / 3.2))) { maxPos = dest }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(0.15, d / 3.2)))
            walking = false
            if s == .door { leave() } else { withAnimation(.spring(duration: 0.3)) { at = s } }
        }
    }

    private func leave() {
        model.saveNow(cloud: false)
        withAnimation(.easeInOut(duration: 0.5)) { model.showQuarters = false }
    }

    private func header(_ g: Game) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Living quarters").font(.avenir(20, "DemiBold")).foregroundStyle(Color.cream)
                let needs = g.quartersNeeds(now: Date())
                Text(needs.isEmpty ? "Everything’s in order." : needs.joined(separator: " · "))
                    .font(.avenir(13)).foregroundStyle(needs.isEmpty ? Color.cream.opacity(0.6) : Color.amber)
            }
            Spacer()
            Button { leave() } label: {
                Label("Workshop", systemImage: "arrow.down.right.and.arrow.up.left").font(.avenir(13, "DemiBold"))
                    .foregroundStyle(Color.cream).padding(.horizontal, 12).frame(height: 36).background(Capsule().fill(Color.black.opacity(0.45)))
            }
            .accessibilityIdentifier("quarters.leave")
        }
        .id(tick)
    }

    // MARK: stations

    @ViewBuilder private func stationView(_ s: Station, g: Game, unit: CGFloat) -> some View {
        let need = needs(s, g: g)
        ZStack {
            RoundedRectangle(cornerRadius: unit * 0.22).fill(Color(red: 0.16, green: 0.12, blue: 0.11))
                .frame(width: unit * (s == .garden ? 1.6 : 1.3), height: unit * (s == .garden ? 2.8 : 1.1))
            RoundedRectangle(cornerRadius: unit * 0.22).stroke(need ? Color.amber : Color.white.opacity(0.12), lineWidth: need ? 2 : 1)
                .frame(width: unit * (s == .garden ? 1.6 : 1.3), height: unit * (s == .garden ? 2.8 : 1.1))
            if s == .garden {
                VStack(spacing: unit * 0.06) {
                    ForEach(0..<g.quarters.plots.count, id: \.self) { i in
                        let p = g.quarters.plots[i]
                        RoundedRectangle(cornerRadius: 6).fill(g.plotDry(i, now: Date()) ? Color(red: 0.42, green: 0.3, blue: 0.22) : Color(red: 0.25, green: 0.17, blue: 0.12))
                            .overlay(Image(systemName: p.crop == nil ? "circle.dotted" : (g.plotReady(i) ? "leaf.fill" : "leaf")).foregroundStyle(p.crop == .spores ? Color(red: 0.6, green: 1, blue: 0.75) : Color(red: 0.55, green: 0.85, blue: 0.45)).font(.system(size: unit * 0.3)))
                            .frame(width: unit * 1.3, height: unit * (g.quarters.plots.count > 3 ? 0.38 : 0.7))
                    }
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: icon(s)).font(.system(size: unit * 0.38)).foregroundStyle(Color.cream)
                    Text(name(s)).font(.avenir(max(9, unit * 0.16), "DemiBold")).foregroundStyle(Color.cream.opacity(0.8))
                }
            }
            if need { Circle().fill(Color.amber).frame(width: 10, height: 10).offset(x: unit * 0.55, y: -unit * 0.45) }
        }
        .id("\(s.rawValue)\(tick)")
    }

    private func icon(_ s: Station) -> String {
        switch s {
        case .bed: return "bed.double.fill"
        case .pantry: return "fork.knife"
        case .stove: return "flame.fill"
        case .garden: return "leaf.fill"
        case .water: return "drop.fill"
        case .lamps: return "lightbulb.fill"
        case .bench: return "hammer.fill"
        case .storage: return "archivebox.fill"
        case .door: return "door.left.hand.open"
        }
    }
    private func name(_ s: Station) -> String {
        switch s {
        case .bed: return "Bed"
        case .pantry: return "Pantry"
        case .stove: return "Stove"
        case .garden: return "Garden"
        case .water: return "Water"
        case .lamps: return "Lamps"
        case .bench: return "Bench"
        case .storage: return "Storage"
        case .door: return "Out"
        }
    }
    private func needs(_ s: Station, g: Game) -> Bool {
        switch s {
        case .water: return g.quarters.filter < 30 || g.quarters.water < 10
        case .lamps: return g.quarters.charge < 15
        case .garden: return (0..<g.quarters.plots.count).contains { g.plotReady($0) || g.plotDry($0, now: Date()) }
        case .pantry: return g.max.stamina < g.max.staminaMax * 0.4
        default: return false
        }
    }

    // MARK: the station card

    @ViewBuilder private func card(_ g: Game) -> some View {
        if let s = at {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(name(s) == "Out" ? "Door" : name(s)).font(.avenir(18, "DemiBold")).foregroundStyle(Color.cream)
                    Spacer()
                    Button { withAnimation { at = nil } } label: { Image(systemName: "xmark").foregroundStyle(Color.cream).frame(width: 36, height: 36) }
                }
                content(s, g: g)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.11, green: 0.08, blue: 0.09).opacity(0.97)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.amber.opacity(0.2)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(tick)
        } else {
            Text("Tap a station and Max walks over.").font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.6))
                .frame(maxWidth: .infinity).padding(.bottom, 8)
        }
    }

    private func action(_ label: String, _ enabled: Bool = true, prominent: Bool = true, _ f: @escaping () -> Void) -> some View {
        Button { f(); flush(); tick += 1 } label: { Text(label) }
            .buttonStyle(PillStyle(prominent: prominent)).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
    private func flush() { for e in model.game.drainEvents() { model.handleExternal(e) } }

    private func bar(_ label: String, _ v: Double, _ tint: Color) -> some View {
        HStack {
            Text(label).font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.8)).frame(width: 70, alignment: .leading)
            GeometryReader { gg in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(v < 20 ? Color.red.opacity(0.8) : tint).frame(width: gg.size.width * CGFloat(max(0, min(100, v))) / 100)
                }
            }.frame(height: 8)
            Text("\(Int(v))").font(.avenir(12, "DemiBold")).monospacedDigit().foregroundStyle(Color.cream.opacity(0.8)).frame(width: 30)
        }
    }

    @ViewBuilder private func content(_ s: Station, g: Game) -> some View {
        let now = Date()
        switch s {
        case .bed:
            Text("Rest a while. It brings back some strength and heals a little.").font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.8))
            bar("Health", g.max.health, Color(red: 0.95, green: 0.42, blue: 0.4)); bar("Stamina", g.max.stamina, Color.amber)
            action("Sleep until rested") { g.recover(stamina: 100, health: 60); g.think("Slept like a stone. Better.", 2) }
        case .pantry:
            let tins = g.world.prop("pantry")?.stock.first { $0.id == .ration }?.count ?? 0
            Text("\(tins) tins left. Greens and trail meals work too.").font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.8))
            bar("Stamina", g.max.stamina, Color.amber)
            HStack { action("Eat") { g.eatAndDrink() }; action("Pack a ration", prominent: false) { g.packRation() } }
        case .stove:
            Text("Two greens or two glowcaps cook into a trail meal for the road.").font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.8))
            Text("Greens \(g.available(.greens)) · Glowcaps \(g.available(.glowcap))").font(.avenir(13, "DemiBold")).foregroundStyle(Color.amber)
            action("Cook a trail meal", g.cookable) { g.cook() }
        case .water:
            bar("Water", g.quarters.water, Color(red: 0.55, green: 0.8, blue: 1)); bar("Filter", g.quarters.filter, Color(red: 0.7, green: 0.9, blue: 0.8))
            Text(g.homeWater ? "The pump sends water home." : "Only a drip from the rock fills it. Get a pump running to fill it faster.").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7))
            HStack { action("Drink") { g.drink() }; action("Rinse filter", prominent: false) { g.rinseFilter() } }
        case .lamps:
            bar("Charge", g.quarters.charge, Color(red: 1, green: 0.85, blue: 0.5))
            Text("The lamps run down without power. Crops won’t grow in the dark.").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7))
            HStack {
                action("Lamp cell (\(g.available(.lampCell)))", g.available(.lampCell) > 0) { g.chargeLamps(with: .lampCell) }
                action("Battery cell (\(g.available(.batteryCell)))", g.available(.batteryCell) > 0, prominent: false) { g.chargeLamps(with: .batteryCell) }
            }
        case .garden:
            ForEach(0..<g.quarters.plots.count, id: \.self) { i in
                let p = g.quarters.plots[i]
                HStack {
                    Text(p.crop == nil ? "Plot \(i + 1): empty" : (g.plotReady(i) ? "Plot \(i + 1): ready" : "Plot \(i + 1): \(Int(min(100, p.grown / Quarters.growMinutes * 100)))% \(g.plotDry(i, now: now) ? "· dry" : "")"))
                        .font(.avenir(14)).foregroundStyle(Color.cream)
                    Spacer()
                    if p.crop == nil {
                        ForEach(g.plantables, id: \.self) { it in action(it == .spores ? "Spores" : "Seeds") { g.plant(i, it) } }
                        if g.plantables.isEmpty { Text("No seeds").font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.5)) }
                    } else if g.plotReady(i) {
                        action("Harvest") { g.harvestPlot(i) }
                    } else {
                        action("Water", g.plotDry(i, now: now) || p.watered == nil, prominent: false) { g.waterPlot(i) }
                    }
                }
            }
            Text("Plants need water every 12 hours and light from the lamps. They keep growing while you’re away.").font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.6))
        case .bench:
            action("Open the workbench") { withAnimation { model.showQuarters = false }; model.sheet = .workbench }
        case .storage:
            action("Open storage") { withAnimation { model.showQuarters = false }; model.sheet = .storage }
        case .door:
            EmptyView()
        }
    }
}

/// Max from above: shadow, cloak, scarf, beanie with the pom-pom bobbing as he walks.
struct TopDownMax: View {
    var walking: Bool
    var facing: CGFloat
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let bob = walking ? CGFloat(sin(t * 14)) * 0.05 : CGFloat(sin(t * 2)) * 0.015
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.36, y: c.y - s * 0.2 + s * 0.22, width: s * 0.72, height: s * 0.36)), with: .color(.black.opacity(0.35)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.32, y: c.y - s * 0.3 + bob * s, width: s * 0.64, height: s * 0.62)), with: .color(Color(red: 0.93, green: 0.86, blue: 0.74)))
                ctx.fill(Path(roundedRect: CGRect(x: c.x - s * 0.26, y: c.y - s * 0.1 + bob * s, width: s * 0.52, height: s * 0.12), cornerRadius: s * 0.05), with: .color(Color(red: 0.78, green: 0.27, blue: 0.18)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.2, y: c.y - s * 0.34 + bob * s, width: s * 0.4, height: s * 0.4)), with: .color(Color(red: 0.29, green: 0.23, blue: 0.36)))
                let pom = CGPoint(x: c.x - facing * s * 0.12, y: c.y - s * 0.3 + bob * s * 1.6)
                ctx.fill(Path(ellipseIn: CGRect(x: pom.x - s * 0.08, y: pom.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: .color(Color(red: 0.91, green: 0.64, blue: 0.23)))
            }
        }
    }
}
