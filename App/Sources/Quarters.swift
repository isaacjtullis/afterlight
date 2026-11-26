import SwiftUI
import AfterlightCore

/// The living quarters, seen from above: tap a station and Max walks over to it.
struct QuartersView: View {
    @EnvironmentObject var model: GameModel
    @State private var maxPos = CGPoint(x: 4.5, y: 6.0)
    @State private var facing: CGFloat = 1
    @State private var walking = false
    @State private var at: Station? = nil
    @State private var tick = 0
    @State private var bounce: [Station: Date] = [:]

    /// The room is 9 × 7.4 units: a back wall along the top, plank floor below.
    static let wallH: CGFloat = 1.5
    /// Where each piece sits (centre) and how big it is, in room units.
    static let spots: [Station: CGRect] = [
        .bed: CGRect(x: 0.35, y: 1.15, width: 1.75, height: 2.35),
        .pantry: CGRect(x: 2.5, y: 0.35, width: 1.45, height: 1.55),
        .stove: CGRect(x: 4.25, y: 0.55, width: 1.25, height: 1.4),
        .lamps: CGRect(x: 7.55, y: 0.3, width: 0.95, height: 1.75),
        .water: CGRect(x: 5.85, y: 1.2, width: 0.95, height: 1.15),
        .bench: CGRect(x: 7.05, y: 2.75, width: 1.75, height: 1.2),
        .storage: CGRect(x: 7.2, y: 4.75, width: 1.5, height: 1.05),
        .garden: CGRect(x: 0.35, y: 4.15, width: 1.8, height: 2.6),
        .door: CGRect(x: 3.9, y: 6.75, width: 1.2, height: 0.6),
    ]
    static let roomW: CGFloat = 9, roomH: CGFloat = 7.4

    var body: some View {
        let g = model.game
        GeometryReader { geo in
            let unit = min((geo.size.width - 16) / Self.roomW, (geo.size.height - 280) / Self.roomH)
            let origin = CGPoint(x: (geo.size.width - unit * Self.roomW) / 2, y: geo.safeAreaInsets.top + 78)
            let sp: (CGPoint) -> CGPoint = { p in CGPoint(x: origin.x + p.x * unit, y: origin.y + p.y * unit) }
            ZStack(alignment: .topLeading) {
                Color(red: 0.06, green: 0.04, blue: 0.05).ignoresSafeArea()
                TimelineView(.animation) { tl in
                    let t = tl.date
                    Canvas { ctx, _ in
                        RoomArt.draw(ctx: ctx, origin: origin, u: unit, g: g, t: t, bounce: bounce, maxPos: maxPos, walking: walking, facing: facing)
                    }
                }
                .allowsHitTesting(false)
                // Tap the floor to wander; tap a piece to use it.
                Color.clear.contentShape(Rectangle())
                    .frame(width: unit * Self.roomW, height: unit * (Self.roomH - Self.wallH))
                    .position(x: origin.x + unit * Self.roomW / 2, y: origin.y + unit * (Self.wallH + (Self.roomH - Self.wallH) / 2))
                    .gesture(SpatialTapGesture().onEnded { v in
                        let p = CGPoint(x: v.location.x / unit, y: v.location.y / unit + Self.wallH)
                        walk(to: CGPoint(x: min(8.6, max(0.4, p.x)), y: min(7.0, max(Self.wallH + 0.6, p.y))), then: nil)
                    })
                ForEach(Station.allCases, id: \.self) { s in
                    let r = Self.spots[s]!
                    Color.clear.contentShape(Rectangle())
                        .frame(width: r.width * unit, height: r.height * unit)
                        .position(sp(CGPoint(x: r.midX, y: r.midY)))
                        .onTapGesture { go(to: s) }
                        .accessibilityElement().accessibilityAddTraits(.isButton)
                        .accessibilityLabel(name(s))
                        .accessibilityIdentifier("station.\(s.rawValue)")
                }
                // "!" bubbles over anything that wants tending
                ForEach(Station.allCases.filter { needs($0, g: g) }, id: \.self) { s in
                    let r = Self.spots[s]!
                    NeedBubble().position(sp(CGPoint(x: r.midX, y: r.minY - 0.1)))
                        .allowsHitTesting(false)
                }
                header(g).padding(.top, geo.safeAreaInsets.top + 8).padding(.horizontal, 16)
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
        guard let r = Self.spots[s] else { return }
        bounce[s] = Date()
        let below = CGPoint(x: min(8.5, max(0.5, r.midX + (s == .bed || s == .garden ? r.width / 2 + 0.45 : 0))),
                            y: s == .bed || s == .garden ? r.midY : min(7.0, r.maxY + 0.45))
        let dest = s == .door ? CGPoint(x: r.midX, y: 7.1) : below
        walk(to: dest) {
            if s == .door { leave() } else { withAnimation(.spring(duration: 0.3)) { at = s } }
        }
    }

    private func walk(to dest: CGPoint, then: (() -> Void)?) {
        let d = hypot(dest.x - maxPos.x, dest.y - maxPos.y)
        if abs(dest.x - maxPos.x) > 0.05 { facing = dest.x >= maxPos.x ? 1 : -1 }
        walking = true
        model.haptics.tap()
        if then == nil { withAnimation(.spring(duration: 0.2)) { at = nil } }
        let dur = max(0.15, d / 3.4)
        withAnimation(.linear(duration: dur)) { maxPos = dest }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(dur))
            walking = false
            then?()
        }
    }

    private func leave() {
        model.saveNow(cloud: false)
        withAnimation(.easeInOut(duration: 0.5)) { model.showQuarters = false }
    }

    private func header(_ g: Game) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Home").font(.avenir(24, "Bold")).foregroundStyle(Color.cream)
                let needs = g.quartersNeeds(now: Date())
                Text(needs.isEmpty ? "Cozy. Everything’s in order." : needs.joined(separator: " · "))
                    .font(.avenir(13, "DemiBold")).foregroundStyle(needs.isEmpty ? Color.cream.opacity(0.6) : Color.amber).lineLimit(2)
            }
            Spacer()
            Button { leave() } label: {
                Label("Back out", systemImage: "door.left.hand.open").font(.avenir(13, "DemiBold"))
                    .foregroundStyle(Color.cream).padding(.horizontal, 12).frame(height: 36).background(Capsule().fill(Color.black.opacity(0.5)))
            }
            .accessibilityIdentifier("quarters.leave")
        }
        .id(tick)
    }

    // MARK: stations

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
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(Color.amber).frame(width: 38, height: 38)
                        Image(systemName: icon(s)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(red: 0.3, green: 0.17, blue: 0.08))
                    }
                    Text(name(s)).font(.avenir(20, "Bold")).foregroundStyle(Color(red: 0.3, green: 0.18, blue: 0.1))
                    Spacer()
                    Button { withAnimation { at = nil } } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(red: 0.3, green: 0.18, blue: 0.1))
                            .frame(width: 34, height: 34).background(Circle().fill(Color.black.opacity(0.08)))
                    }
                }
                content(s, g: g)
                    .environment(\.colorScheme, .light)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.98, green: 0.93, blue: 0.83))
                    .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
            )
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color(red: 0.78, green: 0.6, blue: 0.4), lineWidth: 3))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(red: 0.78, green: 0.6, blue: 0.4).opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5, 4])).padding(6))
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(tick)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                Text("Tap something to use it · tap the floor to walk")
            }
            .font(.avenir(13, "DemiBold")).foregroundStyle(Color.cream.opacity(0.7))
            .padding(.horizontal, 14).frame(height: 36).background(Capsule().fill(Color.black.opacity(0.4)))
            .frame(maxWidth: .infinity).padding(.bottom, 8)
        }
    }

    private func action(_ label: String, _ enabled: Bool = true, prominent: Bool = true, _ f: @escaping () -> Void) -> some View {
        Button { f(); flush(); tick += 1; model.haptics.tap() } label: {
            Text(label).font(.avenir(15, "Bold")).foregroundStyle(prominent ? Color.white : Ink.main)
                .padding(.horizontal, 18).frame(minHeight: 42)
                .background(Capsule().fill(prominent ? Color(red: 0.36, green: 0.62, blue: 0.42) : Color(red: 0.9, green: 0.82, blue: 0.68)))
                .overlay(Capsule().stroke(Color.black.opacity(0.12), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 0, y: 3)
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
    private func flush() { for e in model.game.drainEvents() { model.handleExternal(e) } }

    private func bar(_ label: String, _ v: Double, _ tint: Color) -> some View {
        HStack {
            Text(label).font(.avenir(13, "DemiBold")).foregroundStyle(Ink.soft).frame(width: 70, alignment: .leading)
            GeometryReader { gg in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.1))
                    Capsule().fill(v < 20 ? Color.red.opacity(0.8) : tint).frame(width: gg.size.width * CGFloat(max(0, min(100, v))) / 100)
                }
            }.frame(height: 8)
            Text("\(Int(v))").font(.avenir(12, "DemiBold")).monospacedDigit().foregroundStyle(Ink.soft).frame(width: 30)
        }
    }

    @ViewBuilder private func content(_ s: Station, g: Game) -> some View {
        let now = Date()
        switch s {
        case .bed:
            Text("Rest a while. It brings back some strength and heals a little.").font(.avenir(14)).foregroundStyle(Ink.soft)
            bar("Health", g.max.health, Color(red: 0.95, green: 0.42, blue: 0.4)); bar("Stamina", g.max.stamina, Color.amber)
            action("Sleep until rested") { g.recover(stamina: 100, health: 60); model.playSleep(); g.think("Slept like a stone. Better.", 2) }
        case .pantry:
            let tins = g.world.prop("pantry")?.stock.first { $0.id == .ration }?.count ?? 0
            Text("\(tins) tins left. Greens and trail meals work too.").font(.avenir(14)).foregroundStyle(Ink.soft)
            bar("Stamina", g.max.stamina, Color.amber)
            HStack { action("Eat") { g.eatAndDrink() }; action("Pack a ration", prominent: false) { g.packRation() } }
        case .stove:
            Text("Two greens or two glowcaps cook into a trail meal for the road.").font(.avenir(14)).foregroundStyle(Ink.soft)
            Text("Greens \(g.available(.greens)) · Glowcaps \(g.available(.glowcap))").font(.avenir(13, "DemiBold")).foregroundStyle(Ink.accent)
            action("Cook a trail meal", g.cookable) { g.cook() }
        case .water:
            bar("Water", g.quarters.water, Color(red: 0.55, green: 0.8, blue: 1)); bar("Filter", g.quarters.filter, Color(red: 0.7, green: 0.9, blue: 0.8))
            Text(g.homeWater ? "The pump sends water home." : "Only a drip from the rock fills it. Get a pump running to fill it faster.").font(.avenir(13)).foregroundStyle(Ink.soft)
            HStack { action("Drink") { g.drink() }; action("Rinse filter", prominent: false) { g.rinseFilter() } }
        case .lamps:
            bar("Charge", g.quarters.charge, Color(red: 1, green: 0.85, blue: 0.5))
            Text("The lamps run down without power. Crops won’t grow in the dark.").font(.avenir(13)).foregroundStyle(Ink.soft)
            HStack {
                action("Lamp cell (\(g.available(.lampCell)))", g.available(.lampCell) > 0) { g.chargeLamps(with: .lampCell) }
                action("Battery cell (\(g.available(.batteryCell)))", g.available(.batteryCell) > 0, prominent: false) { g.chargeLamps(with: .batteryCell) }
            }
        case .garden:
            ForEach(0..<g.quarters.plots.count, id: \.self) { i in
                let p = g.quarters.plots[i]
                HStack {
                    Text(p.crop == nil ? "Plot \(i + 1): empty" : (g.plotReady(i) ? "Plot \(i + 1): ready" : "Plot \(i + 1): \(Int(min(100, p.grown / Quarters.growMinutes * 100)))% \(g.plotDry(i, now: now) ? "· dry" : "")"))
                        .font(.avenir(14)).foregroundStyle(Ink.main)
                    Spacer()
                    if p.crop == nil {
                        ForEach(g.plantables, id: \.self) { it in action(it == .spores ? "Spores" : "Seeds") { g.plant(i, it) } }
                        if g.plantables.isEmpty { Text("No seeds").font(.avenir(12)).foregroundStyle(Ink.faint) }
                    } else if g.plotReady(i) {
                        action("Harvest") { g.harvestPlot(i) }
                    } else {
                        action("Water", g.plotDry(i, now: now) || p.watered == nil, prominent: false) { g.waterPlot(i) }
                    }
                }
            }
            Text("Plants need water every 12 hours and light from the lamps. They keep growing while you’re away.").font(.avenir(12)).foregroundStyle(Ink.faint)
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


enum Ink {
    static let main = Color(red: 0.3, green: 0.18, blue: 0.1)
    static let soft = Color(red: 0.42, green: 0.3, blue: 0.22)
    static let faint = Color(red: 0.55, green: 0.45, blue: 0.36)
    static let accent = Color(red: 0.78, green: 0.42, blue: 0.16)
}

/// A bouncing "!" over something that wants tending.
struct NeedBubble: View {
    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(Color.white).frame(width: 24, height: 24).shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                Text("!").font(.avenir(16, "Heavy")).foregroundStyle(Color(red: 0.9, green: 0.45, blue: 0.15))
            }
            .offset(y: CGFloat(-abs(sin(t * 3.2))) * 6)
        }
    }
}

/// The whole room, drawn: wall, planks, rug and every piece of furniture, with Max walking around in it.
enum RoomArt {
    static func c(_ hex: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255).opacity(a)
    }

    static func draw(ctx: GraphicsContext, origin o: CGPoint, u: CGFloat, g: Game, t date: Date, bounce: [Station: Date], maxPos: CGPoint, walking: Bool, facing: CGFloat) {
        let t = date.timeIntervalSinceReferenceDate
        func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: o.x + x * u, y: o.y + y * u, width: w * u, height: h * u) }
        func fill(_ r: CGRect, _ col: Color, _ rad: CGFloat = 0) { ctx.fill(rad > 0 ? Path(roundedRect: r, cornerRadius: rad * u) : Path(r), with: .color(col)) }
        func oval(_ r: CGRect, _ col: Color) { ctx.fill(Path(ellipseIn: r), with: .color(col)) }
        let W = QuartersView.roomW, H = QuartersView.roomH, wh = QuartersView.wallH
        let lit = g.story.flags.contains("shelterLit")
        let charge = g.quarters.charge / 100

        // outer walls
        fill(R(-0.3, -0.3, W + 0.6, H + 0.6), c(0x2a1d1c), 0.35)
        // back wall: warm wallpaper with a stripe pattern, wainscot and a baseboard
        fill(R(0, 0, W, wh), c(0x8a5f4c))
        for i in 0..<Int(W * 3) where i % 2 == 0 { fill(R(CGFloat(i) / 3, 0, 1 / 6, wh * 0.62), c(0x9b6d57)) }
        fill(R(0, wh * 0.62, W, wh * 0.38), c(0x6b4433))
        for i in 0..<Int(W * 2) { fill(R(CGFloat(i) / 2 + 0.24, wh * 0.66, 0.02, wh * 0.3), c(0x000000, 0.15)) }
        fill(R(0, wh - 0.1, W, 0.1), c(0x3e2820))
        // a framed photo and a little clock on the wall
        fill(R(2.05, 0.18, 0.42, 0.34), c(0x4a3020), 0.04); fill(R(2.1, 0.23, 0.32, 0.24), c(0xc9b48f)); oval(R(2.18, 0.27, 0.12, 0.12), c(0x6e8fa6))
        let cl = R(6.85, 0.15, 0.36, 0.36); oval(cl, c(0x3e2820)); oval(cl.insetBy(dx: 0.04 * u, dy: 0.04 * u), c(0xf4e8d0))
        var hand = Path(); hand.move(to: CGPoint(x: cl.midX, y: cl.midY)); hand.addLine(to: CGPoint(x: cl.midX + cos(t * 0.5) * 0.11 * u, y: cl.midY + sin(t * 0.5) * 0.11 * u))
        ctx.stroke(hand, with: .color(c(0x3e2820)), lineWidth: 1.5)

        // plank floor
        let floorR = R(0, wh, W, H - wh)
        fill(floorR, c(0xb07c52))
        let rowsN = Int((H - wh) / 0.45) + 1
        for r in 0..<rowsN {
            let y = wh + CGFloat(r) * 0.45
            fill(R(0, y, W, 0.45), (r % 2 == 0 ? c(0xb98559) : c(0xa97449)))
            fill(R(0, y + 0.43, W, 0.02), c(0x5a3a24, 0.4))
            var x: CGFloat = (r % 3 == 0) ? 0.6 : (r % 3 == 1 ? 1.5 : 1.0)
            while x < W { fill(R(x, y, 0.025, 0.45), c(0x5a3a24, 0.35)); x += 2.4 }
        }
        // rug
        let rug = R(2.7, 3.6, 3.6, 2.4)
        ctx.fill(Path(roundedRect: rug, cornerRadius: 0.5 * u), with: .color(c(0xc45a45)))
        ctx.stroke(Path(roundedRect: rug.insetBy(dx: 0.14 * u, dy: 0.14 * u), cornerRadius: 0.4 * u), with: .color(c(0xf1c27d)), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        oval(R(3.95, 4.3, 1.1, 1.0), c(0xe4a35c, 0.7))
        // door in the bottom wall
        fill(R(3.9, H - 0.08, 1.2, 0.4), c(0x120c0c))
        fill(R(3.95, H - 0.55, 1.1, 0.45), c(0x5a7a5c), 0.08)
        ctx.draw(Text("WELCOME").font(.system(size: max(6, 0.14 * u), weight: .heavy)).foregroundColor(c(0xe8dcb5)), at: CGPoint(x: o.x + 4.5 * u, y: o.y + (H - 0.33) * u))

        // table and chair, if built
        if g.quarters.decor.contains("table") {
            oval(R(3.9, 4.95, 1.2, 0.3), c(0x000000, 0.25))
            fill(R(3.95, 4.15, 1.1, 0.85), c(0x8b5a33), 0.1); fill(R(3.95, 4.15, 1.1, 0.12), c(0xa8713f), 0.06)
            oval(R(4.2, 4.35, 0.3, 0.22), c(0xf3ead7)); oval(R(4.6, 4.45, 0.22, 0.22), c(0xd2e3ee, 0.9))
            fill(R(5.25, 4.25, 0.5, 0.55), c(0x6e4426), 0.08)
        }

        func scale(_ s: Station) -> CGFloat {
            guard let b = bounce[s] else { return 1 }
            let e = date.timeIntervalSince(b)
            guard e < 0.6 else { return 1 }
            return 1 + CGFloat(sin(e * 18) * exp(-e * 7)) * 0.12
        }
        func piece(_ s: Station, _ f: (CGRect) -> Void) {
            let r0 = QuartersView.spots[s]!
            let r = R(r0.minX, r0.minY, r0.width, r0.height)
            let k = scale(s)
            // shadow on the floor
            oval(CGRect(x: r.minX + r.width * 0.05, y: r.maxY - r.height * 0.12, width: r.width * 0.9, height: r.height * 0.22), c(0x000000, 0.22))
            if k == 1 { f(r) } else {
                let sr = CGRect(x: r.midX - r.width * k / 2, y: r.maxY - r.height * k, width: r.width * k, height: r.height * k)
                f(sr)
            }
        }

        // BED: wooden frame, patchwork quilt, pillow
        piece(.bed) { r in
            let x = r.minX, y = r.minY, w = r.width, h = r.height
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: w * 0.12), with: .color(c(0x7a4b2c)))
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: w, height: h * 0.16), cornerRadius: w * 0.1), with: .color(c(0x8f5a35)))
            ctx.fill(Path(roundedRect: CGRect(x: x + w * 0.08, y: y + h * 0.12, width: w * 0.84, height: h * 0.8), cornerRadius: w * 0.1), with: .color(c(0xf4ece0)))
            ctx.fill(Path(roundedRect: CGRect(x: x + w * 0.2, y: y + h * 0.15, width: w * 0.6, height: h * 0.15), cornerRadius: w * 0.08), with: .color(.white))
            let q = CGRect(x: x + w * 0.08, y: y + h * 0.36, width: w * 0.84, height: h * 0.56)
            ctx.fill(Path(roundedRect: q, cornerRadius: w * 0.08), with: .color(c(0x4f7aa1)))
            for i in 0..<3 { for j in 0..<4 where (i + j) % 2 == 0 {
                ctx.fill(Path(CGRect(x: q.minX + q.width * CGFloat(i) / 3, y: q.minY + q.height * CGFloat(j) / 4, width: q.width / 3, height: q.height / 4).insetBy(dx: 1, dy: 1)), with: .color(c(0x6a94b8)))
            } }
            ctx.fill(Path(CGRect(x: q.minX, y: q.minY, width: q.width, height: q.height * 0.08)), with: .color(c(0xf2d7a0)))
        }
        // PANTRY: shelves with tins and jars
        piece(.pantry) { r in
            let tins = g.world.prop("pantry")?.stock.first { $0.id == .ration }?.count ?? 0
            ctx.fill(Path(roundedRect: r, cornerRadius: 0.08 * u), with: .color(c(0x8a5a37)))
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.1)), with: .color(c(0xa06c43)))
            for sIdx in 0..<3 {
                let sy = r.minY + r.height * (0.14 + CGFloat(sIdx) * 0.29)
                ctx.fill(Path(CGRect(x: r.minX + r.width * 0.07, y: sy, width: r.width * 0.86, height: r.height * 0.25)), with: .color(c(0x4a2e1c)))
                ctx.fill(Path(CGRect(x: r.minX + r.width * 0.05, y: sy + r.height * 0.24, width: r.width * 0.9, height: r.height * 0.04)), with: .color(c(0xb27a4a)))
                for k in 0..<4 {
                    let idx = sIdx * 4 + k
                    guard idx < tins + 2 else { continue }
                    let tx = r.minX + r.width * (0.12 + CGFloat(k) * 0.2)
                    let col: Color = idx >= tins ? c(0xa7d3c6) : [c(0xd9534f), c(0xf0ad4e), c(0x5cb85c), c(0x5bc0de)][idx % 4]
                    ctx.fill(Path(roundedRect: CGRect(x: tx, y: sy + r.height * 0.06, width: r.width * 0.15, height: r.height * 0.18), cornerRadius: 2), with: .color(col))
                    ctx.fill(Path(CGRect(x: tx, y: sy + r.height * 0.11, width: r.width * 0.15, height: r.height * 0.05)), with: .color(.white.opacity(0.6)))
                }
            }
        }
        // STOVE: cast iron, a flickering fire window, chimney up the wall, a pot
        piece(.stove) { r in
            ctx.fill(Path(CGRect(x: r.midX - r.width * 0.08, y: o.y, width: r.width * 0.16, height: r.minY - o.y + 2)), with: .color(c(0x2f2a2c)))
            ctx.fill(Path(roundedRect: r, cornerRadius: 0.1 * u), with: .color(c(0x3a3437)))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX - 2, y: r.minY, width: r.width + 4, height: r.height * 0.14), cornerRadius: 3), with: .color(c(0x55494d)))
            let fireW = CGRect(x: r.minX + r.width * 0.22, y: r.minY + r.height * 0.4, width: r.width * 0.56, height: r.height * 0.38)
            ctx.fill(Path(roundedRect: fireW, cornerRadius: 4), with: .color(c(0x1a1213)))
            let fl = 0.75 + 0.25 * sin(t * 9) * sin(t * 5.3)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 3))
                l.fill(Path(ellipseIn: fireW.insetBy(dx: fireW.width * 0.12, dy: fireW.height * 0.15).offsetBy(dx: 0, dy: fireW.height * 0.1)), with: .color(c(0xff8a2a, fl)))
                l.fill(Path(ellipseIn: fireW.insetBy(dx: fireW.width * 0.3, dy: fireW.height * 0.32).offsetBy(dx: 0, dy: fireW.height * 0.12)), with: .color(c(0xffe08a, fl)))
            }
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + r.width * 0.25, y: r.minY - r.height * 0.18, width: r.width * 0.5, height: r.height * 0.26), cornerRadius: 4), with: .color(c(0x7d8a93)))
            for i in 0..<3 {
                let ph = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                ctx.fill(Path(ellipseIn: CGRect(x: r.midX - 4 + CGFloat(sin(t * 2 + Double(i))) * 5, y: r.minY - r.height * 0.25 - CGFloat(ph) * 0.5 * u, width: 8, height: 8)), with: .color(.white.opacity(0.35 * (1 - ph))))
            }
        }
        // WATER BARREL: staves, hoops, a shimmering top
        piece(.water) { r in
            ctx.fill(Path(roundedRect: r, cornerRadius: r.width * 0.25), with: .color(c(0x9a6338)))
            for i in 1..<4 { ctx.fill(Path(CGRect(x: r.minX + r.width * CGFloat(i) / 4, y: r.minY + 4, width: 1.2, height: r.height - 8)), with: .color(c(0x5a3a24, 0.5))) }
            for y in [0.22, 0.74] as [CGFloat] { ctx.fill(Path(CGRect(x: r.minX, y: r.minY + r.height * y, width: r.width, height: r.height * 0.08)), with: .color(c(0x5c6670))) }
            let top = CGRect(x: r.minX + r.width * 0.08, y: r.minY + 2, width: r.width * 0.84, height: r.height * 0.24)
            ctx.fill(Path(ellipseIn: top), with: .color(c(0x3c2617)))
            let lvl = CGFloat(g.quarters.water / max(1, g.quarters.barrelCap))
            ctx.fill(Path(ellipseIn: top.insetBy(dx: top.width * (0.4 - 0.32 * lvl), dy: top.height * (0.4 - 0.3 * lvl))), with: .color(c(0x6fb4e0, 0.95)))
            ctx.fill(Path(ellipseIn: CGRect(x: top.midX - 6 + CGFloat(sin(t * 1.7)) * 6, y: top.midY - 2, width: 8, height: 3)), with: .color(.white.opacity(0.7)))
        }
        // LAMP: a tall floor lamp; its glow follows the charge
        piece(.lamps) { r in
            ctx.fill(Path(CGRect(x: r.midX - 2, y: r.minY + r.height * 0.3, width: 4, height: r.height * 0.62)), with: .color(c(0x3e2b22)))
            ctx.fill(Path(ellipseIn: CGRect(x: r.midX - r.width * 0.3, y: r.maxY - r.height * 0.1, width: r.width * 0.6, height: r.height * 0.1)), with: .color(c(0x3e2b22)))
            var shade = Path()
            shade.move(to: CGPoint(x: r.minX + r.width * 0.25, y: r.minY)); shade.addLine(to: CGPoint(x: r.maxX - r.width * 0.25, y: r.minY))
            shade.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.32)); shade.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.32)); shade.closeSubpath()
            ctx.fill(shade, with: .color(c(lit && charge > 0.05 ? 0xf6c56b : 0x8b7a60)))
            if lit && charge > 0.05 {
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 18))
                    l.fill(Path(ellipseIn: CGRect(x: r.midX - u * 1.3, y: r.minY - u * 0.2, width: u * 2.6, height: u * 2.2)), with: .color(c(0xffd27a, 0.35 * Double(charge))))
                }
            }
        }
        // WORKBENCH: a thick top, a vise, tools hung on it
        piece(.bench) { r in
            ctx.fill(Path(CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.4, width: r.width * 0.08, height: r.height * 0.6)), with: .color(c(0x5a3a24)))
            ctx.fill(Path(CGRect(x: r.maxX - r.width * 0.14, y: r.minY + r.height * 0.4, width: r.width * 0.08, height: r.height * 0.6)), with: .color(c(0x5a3a24)))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY + r.height * 0.1, width: r.width, height: r.height * 0.42), cornerRadius: 4), with: .color(c(0xb0784a)))
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY + r.height * 0.1, width: r.width, height: r.height * 0.08)), with: .color(c(0xc99062)))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX + r.width * 0.08, y: r.minY, width: r.width * 0.18, height: r.height * 0.22), cornerRadius: 2), with: .color(c(0x6b7780)))
            // hammer and saw on the top
            ctx.fill(Path(CGRect(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.24, width: r.width * 0.28, height: 3)), with: .color(c(0x6e4426)))
            ctx.fill(Path(CGRect(x: r.minX + r.width * 0.68, y: r.minY + r.height * 0.18, width: 5, height: r.height * 0.16)), with: .color(c(0x9aa3ab)))
            ctx.fill(Path(CGRect(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.36, width: r.width * 0.3, height: r.height * 0.06)), with: .color(c(0xc8ced3)))
            for i in 0..<5 { ctx.fill(Path(ellipseIn: CGRect(x: r.minX + r.width * (0.2 + CGFloat(i) * 0.13), y: r.maxY - 4, width: 5, height: 3)), with: .color(c(0xe2b57f, 0.8))) }
        }
        // STORAGE CHEST: banded lid, brass corners and latch
        piece(.storage) { r in
            ctx.fill(Path(roundedRect: r, cornerRadius: 0.1 * u), with: .color(c(0x8b5a33)))
            ctx.fill(Path(roundedRect: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.38), cornerRadius: 0.1 * u), with: .color(c(0xa06a3d)))
            ctx.fill(Path(CGRect(x: r.minX, y: r.minY + r.height * 0.36, width: r.width, height: 3)), with: .color(c(0x4a2e1c)))
            for x in [0.18, 0.78] as [CGFloat] { ctx.fill(Path(CGRect(x: r.minX + r.width * x, y: r.minY, width: r.width * 0.06, height: r.height)), with: .color(c(0xc79a4a))) }
            ctx.fill(Path(roundedRect: CGRect(x: r.midX - 6, y: r.minY + r.height * 0.3, width: 12, height: 13), cornerRadius: 3), with: .color(c(0xe0b45a)))
        }
        // GARDEN: a raised bed with one row per plot, sprouts by growth
        piece(.garden) { r in
            ctx.fill(Path(roundedRect: r, cornerRadius: 0.12 * u), with: .color(c(0x8b5a33)))
            let n = max(1, g.quarters.plots.count)
            let rh = (r.height - 10) / CGFloat(n)
            for i in 0..<n {
                let p = g.quarters.plots[i]
                let row = CGRect(x: r.minX + 5, y: r.minY + 5 + CGFloat(i) * rh, width: r.width - 10, height: rh - 3)
                let dry = g.plotDry(i, now: date)
                ctx.fill(Path(roundedRect: row, cornerRadius: 4), with: .color(dry ? c(0x8a6a4a) : c(0x4a3020)))
                guard p.crop != nil else {
                    for k in 0..<3 { ctx.fill(Path(ellipseIn: CGRect(x: row.minX + row.width * (0.2 + CGFloat(k) * 0.3) - 2, y: row.midY - 2, width: 4, height: 4)), with: .color(c(0x2e1d12))) }
                    continue
                }
                let grow = CGFloat(min(1, p.grown / Quarters.growMinutes))
                let ready = g.plotReady(i)
                let glow = p.crop == .spores
                for k in 0..<3 {
                    let cx = row.minX + row.width * (0.2 + CGFloat(k) * 0.3)
                    let hgt = row.height * (0.25 + 0.65 * grow)
                    let sway = CGFloat(sin(t * 1.5 + Double(k + i))) * 2
                    ctx.fill(Path(CGRect(x: cx - 1, y: row.maxY - hgt, width: 2, height: hgt)), with: .color(c(0x4f8a3a)))
                    let leaf = max(4, row.height * 0.35 * (0.4 + grow))
                    let lc = glow ? c(0x8ff0c0) : c(ready ? 0x7fd35a : 0x63b048)
                    ctx.fill(Path(ellipseIn: CGRect(x: cx - leaf + sway, y: row.maxY - hgt - leaf * 0.4, width: leaf, height: leaf * 0.7)), with: .color(lc))
                    ctx.fill(Path(ellipseIn: CGRect(x: cx + sway, y: row.maxY - hgt - leaf * 0.55, width: leaf, height: leaf * 0.7)), with: .color(lc))
                    if ready { ctx.fill(Path(ellipseIn: CGRect(x: cx - 3 + sway, y: row.maxY - hgt - leaf * 0.9, width: 6, height: 6)), with: .color(glow ? c(0xd2fff0) : c(0xffd166))) }
                }
            }
        }

        // MAX, from above
        let mp = CGPoint(x: o.x + maxPos.x * u, y: o.y + maxPos.y * u)
        let s = u * 0.95
        let bob = walking ? CGFloat(abs(sin(t * 12))) * 0.06 : CGFloat(sin(t * 2)) * 0.012
        ctx.fill(Path(ellipseIn: CGRect(x: mp.x - s * 0.34, y: mp.y - s * 0.02, width: s * 0.68, height: s * 0.26)), with: .color(.black.opacity(0.3)))
        let bodyR = CGRect(x: mp.x - s * 0.28, y: mp.y - s * 0.62 - bob * s, width: s * 0.56, height: s * 0.6)
        // legs while walking
        if walking {
            let st = CGFloat(sin(t * 12)) * s * 0.08
            ctx.fill(Path(roundedRect: CGRect(x: mp.x - s * 0.16, y: mp.y - s * 0.12 + st, width: s * 0.12, height: s * 0.16), cornerRadius: 3), with: .color(c(0x3b2a26)))
            ctx.fill(Path(roundedRect: CGRect(x: mp.x + s * 0.04, y: mp.y - s * 0.12 - st, width: s * 0.12, height: s * 0.16), cornerRadius: 3), with: .color(c(0x3b2a26)))
        }
        ctx.fill(Path(roundedRect: bodyR, cornerRadius: s * 0.22), with: .color(c(0xeedcbd)))
        ctx.fill(Path(roundedRect: CGRect(x: bodyR.minX + (facing > 0 ? -s * 0.06 : bodyR.width - s * 0.16), y: bodyR.minY + s * 0.18, width: s * 0.22, height: s * 0.28), cornerRadius: 4), with: .color(c(0x7a4e2c)))
        let head = CGRect(x: mp.x - s * 0.24, y: bodyR.minY - s * 0.4, width: s * 0.48, height: s * 0.46)
        ctx.fill(Path(roundedRect: CGRect(x: mp.x - s * 0.24, y: bodyR.minY - s * 0.02, width: s * 0.48, height: s * 0.1), cornerRadius: 3), with: .color(c(0xc6452e)))
        ctx.fill(Path(ellipseIn: head), with: .color(c(0xf3d2b5)))
        ctx.fill(Path(ellipseIn: CGRect(x: head.minX - 1, y: head.minY - s * 0.04, width: head.width + 2, height: head.height * 0.6)), with: .color(c(0x4a3a5c)))
        ctx.fill(Path(ellipseIn: CGRect(x: head.midX + facing * s * 0.1 - 2, y: head.midY + s * 0.02, width: 4, height: 4)), with: .color(c(0x2a1d1c)))
        ctx.fill(Path(ellipseIn: CGRect(x: head.midX - facing * s * 0.2 - s * 0.07, y: head.minY - s * 0.1, width: s * 0.14, height: s * 0.14)), with: .color(c(0xe9a23b)))

        // light: warm when the shelter's lit and the lamps are charged, dim otherwise
        let bright = lit ? 0.25 + 0.75 * charge : 0.1
        ctx.drawLayer { l in
            l.fill(Path(R(-0.4, -0.4, W + 0.8, H + 0.8)), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.75 - 0.5 * bright)]),
                   center: CGPoint(x: o.x + W * u / 2, y: o.y + H * u * 0.45), startRadius: u * CGFloat(1 + 3 * bright), endRadius: u * 7))
        }
        // dust motes in the lamplight
        for i in 0..<14 {
            let fi = Double(i)
            let x = o.x + CGFloat((fi * 1.37 + sin(t * 0.3 + fi) * 0.4).truncatingRemainder(dividingBy: Double(W))) * u
            let y = o.y + CGFloat(1 + (fi * 0.43 + t * 0.05 * (1 + fi.truncatingRemainder(dividingBy: 3))).truncatingRemainder(dividingBy: Double(H - 1.2))) * u
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)), with: .color(c(0xfff2d6, 0.25 * bright)))
        }
    }
}
