import SwiftUI
import AfterlightCore

/// Bottom cards for the workbench, storage, pack, journal and daily mission.
struct SheetHost: View {
    @EnvironmentObject var model: GameModel
    let sheet: Sheet

    var body: some View {
        switch sheet {
        case .pack: BagSheet()
        case .journal: ScrollJournal()
        case .workbench: BuildSheet()
        default: card
        }
    }

    private var card: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.4).ignoresSafeArea().onTapGesture { model.sheet = nil }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title).font(.avenir(22, "DemiBold")).foregroundStyle(Color.cream)
                    Spacer()
                    Button { model.sheet = nil } label: { Image(systemName: "xmark").foregroundStyle(Color.cream).frame(width: 44, height: 44) }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        switch sheet {
                        case .workbench: EmptyView()
                        case .storage: StorageView()
                        case .pack, .journal: EmptyView()
                        case .mission: MissionView()
                        case .camp: CampView()
                        case .pantry: PantryView()
                        case .loot: LootView()
                        case .checkpoints: CheckpointsView()
                        case .map: MapView()
                        }
                    }
                }
                .frame(maxHeight: 440)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.1, green: 0.06, blue: 0.08).opacity(0.96)))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.12)))
            .padding(10)
        }
        .transition(.move(edge: .bottom))
    }

    var title: String {
        switch sheet {
        case .workbench: return "Build"
        case .storage: return "Workshop storage"
        case .pack: return "Belt and pack"
        case .journal: return "Journal"
        case .mission: return "Today’s job for Max"
        case .camp: return model.game.openCamp.flatMap { id in model.game.world.prop(id)?.flags.first { $0.hasPrefix("name:") }.map { String($0.dropFirst(5)) } } ?? "Camp crate"
        case .map: return "Map"
        case .pantry: return "Pantry"
        case .loot: return LootView.title(model.game)
        case .checkpoints: return "Checkpoints"
        }
    }
}

struct Row<Right: View>: View {
    var title: String
    var detail: String
    @ViewBuilder var right: Right
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream)
                Text(detail).font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            right
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
    }
}

/// Build: every recipe Max knows, with its art, what it takes, and what's missing.
struct WorkbenchView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0
    var body: some View {
        let g = model.game
        Text(g.atBench ? "At a workbench: everything can be built here." : "Away from a workbench: only field builds. The rest need a bench.")
            .font(.avenir(13)).foregroundStyle(g.atBench ? Color.amber : Color.cream.opacity(0.7))
        HStack(spacing: 6) {
            WoodIcon().frame(width: 18, height: 14)
            Text("\(g.inv.wood) wood").font(.avenir(13, "DemiBold")).foregroundStyle(Color.cream)
        }
        if g.knownRecipes.isEmpty {
            Text("Nothing to build yet. Ideas come once Max has seen the problem they solve.").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.8))
        }
        ForEach(g.knownRecipes, id: \.id) { r in
            RecipeCard(recipe: r, blocker: g.buildBlocker(r), game: g) { g.craft(r.id); flush(); tick += 1 }
        }
        Text("At home, the bench pulls parts from storage as well as your bag.").font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.5))
            .id(tick)
    }
    private func flush() { for e in model.game.drainEvents() { model.handleExternal(e) } }
}

/// One thing to build: drawn on leather, with its parts in pockets underneath.
struct RecipeCard: View {
    var recipe: Recipe
    var blocker: String?
    var game: Game
    var build: () -> Void
    var body: some View {
        let ok = blocker == nil
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.2, green: 0.13, blue: 0.09))
                RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.85, green: 0.68, blue: 0.45).opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                ItemArt(recipe: recipe).padding(10)
            }
            .frame(width: 74, height: 74)
            .saturation(ok ? 1 : 0.2).opacity(ok ? 1 : 0.6)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(recipe.name).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream)
                    if !recipe.bench { Text("FIELD").font(.avenir(9, "Bold")).tracking(1).foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(Color.amber)) }
                }
                Text(recipe.note).font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                // the parts, each in a little pocket
                FlowRow {
                    if recipe.wood > 0 { part(icon: AnyView(WoodIcon()), name: "Wood", have: game.inv.wood, need: recipe.wood) }
                    ForEach(recipe.inputs, id: \.self) { s in
                        part(icon: AnyView(Image(systemName: s.id.symbol).resizable().scaledToFit().foregroundStyle(s.id.tint)), name: s.id.name, have: game.available(s.id), need: s.count)
                    }
                }
                HStack {
                    if let b = blocker { Text(b).font(.avenir(12, "DemiBold")).foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.45)) }
                    Spacer()
                    Button("Build") { build() }.buttonStyle(PillStyle(prominent: true)).disabled(!ok).opacity(ok ? 1 : 0.35)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [Color(red: 0.27, green: 0.17, blue: 0.11), Color(red: 0.17, green: 0.1, blue: 0.07)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.4)))
    }
    private func part(icon: AnyView, name: String, have: Int, need: Int) -> some View {
        let enough = have >= need
        return HStack(spacing: 4) {
            icon.frame(width: 14, height: 14)
            Text("\(min(have, need))/\(need)").font(.avenir(11, "DemiBold")).monospacedDigit()
        }
        .foregroundStyle(enough ? Color.cream : Color(red: 0.95, green: 0.55, blue: 0.45))
        .padding(.horizontal, 7).frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.3)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(enough ? Color.amber.opacity(0.4) : Color.red.opacity(0.4)))
        .accessibilityLabel("\(name) \(have) of \(need)")
    }
}

/// Wraps its children onto new lines when they run out of width.
struct FlowRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews { let s = v.sizeThatFits(.unspecified); if x + s.width > w { x = 0; y += row + 6; row = 0 }; x += s.width + 6; row = max(row, s.height) }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for v in subviews { let s = v.sizeThatFits(.unspecified); if x + s.width > b.maxX { x = b.minX; y += row + 6; row = 0 }; v.place(at: CGPoint(x: x, y: y), proposal: .unspecified); x += s.width + 6; row = max(row, s.height) }
    }
}

/// Small drawings of the things Max builds.
struct ItemArt: View {
    var recipe: Recipe
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x * s, y: y * s, width: w * s, height: h * s) }
            func fill(_ p: Path, _ c: Color) { ctx.fill(p, with: .color(c)) }
            let wood = Color(red: 0.62, green: 0.42, blue: 0.26), dark = Color(red: 0.25, green: 0.17, blue: 0.12), steel = Color(red: 0.62, green: 0.65, blue: 0.7)
            switch recipe.id {
            case "lamp":
                fill(Path(roundedRect: R(0.3, 0.08, 0.4, 0.1), cornerRadius: 3), dark)
                ctx.stroke(Path(ellipseIn: R(0.4, 0.0, 0.2, 0.14)), with: .color(dark), lineWidth: 2)
                fill(Path(roundedRect: R(0.28, 0.18, 0.44, 0.58), cornerRadius: 6), dark)
                fill(Path(roundedRect: R(0.34, 0.24, 0.32, 0.46), cornerRadius: 4), Color(red: 1, green: 0.82, blue: 0.45))
                fill(Path(ellipseIn: R(0.43, 0.36, 0.14, 0.22)), Color(red: 1, green: 0.95, blue: 0.75))
                fill(Path(roundedRect: R(0.24, 0.76, 0.52, 0.1), cornerRadius: 3), dark)
            case "ladder":
                fill(Path(R(0.25, 0.05, 0.08, 0.9)), steel); fill(Path(R(0.67, 0.05, 0.08, 0.9)), steel)
                for i in 0..<5 { fill(Path(R(0.25, 0.15 + CGFloat(i) * 0.17, 0.5, 0.06)), steel.opacity(0.8)) }
            case "camp":
                fill(Path(roundedRect: R(0.1, 0.4, 0.8, 0.5), cornerRadius: 4), wood)
                for i in 0..<2 { fill(Path(R(0.1, 0.55 + CGFloat(i) * 0.15, 0.8, 0.03)), dark) }
                fill(Path(roundedRect: R(0.18, 0.22, 0.64, 0.2), cornerRadius: 8), Color(red: 0.35, green: 0.43, blue: 0.42))
            case "fieldBench":
                fill(Path(roundedRect: R(0.05, 0.35, 0.9, 0.12), cornerRadius: 3), wood)
                fill(Path(R(0.12, 0.47, 0.08, 0.45)), dark); fill(Path(R(0.8, 0.47, 0.08, 0.45)), dark)
                fill(Path(R(0.15, 0.7, 0.7, 0.05)), dark)
                fill(Path(roundedRect: R(0.55, 0.18, 0.08, 0.18), cornerRadius: 2), steel)
                fill(Path(roundedRect: R(0.25, 0.25, 0.2, 0.1), cornerRadius: 2), Color(red: 0.8, green: 0.6, blue: 0.3))
            case "cot":
                fill(Path(roundedRect: R(0.05, 0.45, 0.9, 0.14), cornerRadius: 5), Color(red: 0.42, green: 0.5, blue: 0.48))
                fill(Path(roundedRect: R(0.08, 0.38, 0.22, 0.12), cornerRadius: 5), Color(red: 0.88, green: 0.82, blue: 0.7))
                fill(Path(R(0.1, 0.59, 0.06, 0.25)), wood); fill(Path(R(0.84, 0.59, 0.06, 0.25)), wood)
            case "cell":
                fill(Path(roundedRect: R(0.25, 0.15, 0.5, 0.72), cornerRadius: 6), Color(red: 0.3, green: 0.55, blue: 0.5))
                fill(Path(R(0.4, 0.07, 0.2, 0.09)), steel)
                fill(Path(R(0.32, 0.35, 0.36, 0.06)), Color(red: 0.85, green: 0.95, blue: 1))
                fill(Path(R(0.32, 0.55, 0.36, 0.06)), Color(red: 0.85, green: 0.95, blue: 1))
            case "pick":
                var p = Path(); p.move(to: CGPoint(x: 0.2 * s, y: 0.9 * s)); p.addLine(to: CGPoint(x: 0.62 * s, y: 0.3 * s))
                ctx.stroke(p, with: .color(wood), lineWidth: 0.09 * s)
                var h = Path(); h.move(to: CGPoint(x: 0.35 * s, y: 0.15 * s)); h.addQuadCurve(to: CGPoint(x: 0.92 * s, y: 0.45 * s), control: CGPoint(x: 0.75 * s, y: 0.12 * s))
                ctx.stroke(h, with: .color(steel), lineWidth: 0.11 * s)
            case "rope":
                for i in 0..<3 { ctx.stroke(Path(ellipseIn: R(0.15 + CGFloat(i) * 0.04, 0.25 + CGFloat(i) * 0.04, 0.7 - CGFloat(i) * 0.08, 0.5 - CGFloat(i) * 0.08)), with: .color(Color(red: 0.85, green: 0.7, blue: 0.5)), lineWidth: 0.06 * s) }
            case "tank":
                fill(Path(roundedRect: R(0.2, 0.1, 0.6, 0.8), cornerRadius: 10), Color(red: 0.25, green: 0.4, blue: 0.48))
                fill(Path(R(0.2, 0.35, 0.6, 0.05)), dark); fill(Path(R(0.2, 0.65, 0.6, 0.05)), dark)
                fill(Path(ellipseIn: R(0.62, 0.5, 0.1, 0.1)), Color(red: 0.6, green: 0.85, blue: 1))
            case "meal":
                fill(Path(roundedRect: R(0.15, 0.35, 0.7, 0.45), cornerRadius: 8), Color(red: 0.75, green: 0.62, blue: 0.45))
                ctx.stroke(Path(R(0.15, 0.5, 0.7, 0.01)), with: .color(dark), lineWidth: 2)
                fill(Path(ellipseIn: R(0.35, 0.2, 0.3, 0.2)), Color(red: 0.55, green: 0.8, blue: 0.4))
            case "flashlight":
                fill(Path(roundedRect: R(0.1, 0.4, 0.55, 0.2), cornerRadius: 4), dark)
                fill(Path(R(0.65, 0.33, 0.12, 0.34)), steel)
                var beam = Path(); beam.move(to: CGPoint(x: 0.77 * s, y: 0.38 * s)); beam.addLine(to: CGPoint(x: s, y: 0.2 * s)); beam.addLine(to: CGPoint(x: s, y: 0.8 * s)); beam.addLine(to: CGPoint(x: 0.77 * s, y: 0.62 * s))
                fill(beam, Color(red: 1, green: 0.9, blue: 0.6).opacity(0.6))
            case "breaker":
                fill(Path(roundedRect: R(0.44, 0.3, 0.1, 0.65), cornerRadius: 3), wood)
                fill(Path(roundedRect: R(0.18, 0.12, 0.62, 0.22), cornerRadius: 4), Color(red: 0.55, green: 0.3, blue: 0.22))
                var wedge = Path(); wedge.move(to: CGPoint(x: 0.8 * s, y: 0.12 * s)); wedge.addLine(to: CGPoint(x: 0.96 * s, y: 0.23 * s)); wedge.addLine(to: CGPoint(x: 0.8 * s, y: 0.34 * s)); fill(wedge, steel)
                fill(Path(R(0.18, 0.12, 0.62, 0.05)), Color.white.opacity(0.25))
            case "woodLadder":
                fill(Path(R(0.25, 0.05, 0.09, 0.9)), wood); fill(Path(R(0.66, 0.05, 0.09, 0.9)), wood)
                for i in 0..<5 { fill(Path(R(0.25, 0.14 + CGFloat(i) * 0.17, 0.5, 0.07)), Color(red: 0.75, green: 0.53, blue: 0.33)) }
            case "torch":
                fill(Path(roundedRect: R(0.44, 0.4, 0.12, 0.55), cornerRadius: 3), wood)
                fill(Path(ellipseIn: R(0.3, 0.1, 0.4, 0.42)), Color(red: 1, green: 0.55, blue: 0.2))
                fill(Path(ellipseIn: R(0.38, 0.2, 0.24, 0.28)), Color(red: 1, green: 0.88, blue: 0.5))
            case "plot":
                fill(Path(roundedRect: R(0.08, 0.5, 0.84, 0.36), cornerRadius: 4), wood)
                fill(Path(R(0.14, 0.52, 0.72, 0.14)), Color(red: 0.3, green: 0.2, blue: 0.14))
                for i in 0..<3 {
                    let x = 0.25 + CGFloat(i) * 0.25
                    fill(Path(R(x - 0.015, 0.32, 0.03, 0.22)), Color(red: 0.4, green: 0.7, blue: 0.35))
                    fill(Path(ellipseIn: R(x - 0.1, 0.24, 0.1, 0.1)), Color(red: 0.5, green: 0.85, blue: 0.4))
                    fill(Path(ellipseIn: R(x, 0.28, 0.1, 0.1)), Color(red: 0.45, green: 0.78, blue: 0.38))
                }
            case "barrel":
                fill(Path(roundedRect: R(0.22, 0.12, 0.56, 0.8), cornerRadius: 12), wood)
                for y in [0.25, 0.75] as [CGFloat] { fill(Path(R(0.2, y, 0.6, 0.06)), steel) }
                fill(Path(ellipseIn: R(0.26, 0.1, 0.48, 0.12)), Color(red: 0.55, green: 0.8, blue: 1))
            case "table":
                fill(Path(roundedRect: R(0.08, 0.38, 0.62, 0.12), cornerRadius: 3), wood)
                fill(Path(R(0.14, 0.5, 0.07, 0.4)), dark); fill(Path(R(0.57, 0.5, 0.07, 0.4)), dark)
                fill(Path(roundedRect: R(0.72, 0.5, 0.2, 0.08), cornerRadius: 2), wood)
                fill(Path(R(0.74, 0.25, 0.05, 0.65)), dark); fill(Path(R(0.86, 0.58, 0.05, 0.32)), dark)
                fill(Path(ellipseIn: R(0.3, 0.27, 0.18, 0.11)), Color(red: 0.9, green: 0.85, blue: 0.75))
            default:
                if case .tool(let t) = recipe.output {
                    ctx.draw(Text(Image(systemName: t == .shortPick ? "hammer.fill" : "wrench.and.screwdriver.fill")).font(.system(size: s * 0.55)).foregroundColor(steel), at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
                if case .item(let it, _) = recipe.output {
                    ctx.draw(Text(Image(systemName: it.symbol)).font(.system(size: s * 0.6)).foregroundColor(it.tint), at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
            }
        }
    }
}

/// The pantry: eat now, or pack food for the road.
struct PantryView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0
    var body: some View {
        let g = model.game
        let tins = g.world.prop("pantry")?.stock.first { $0.id == .ration }?.count ?? 0
        Text("Hunger drops slowly while you work. Eat here, or pack food and eat it from the bag when you’re out digging.")
            .font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.8))
        Text("\(tins) tins left · hunger \(Int(g.max.hunger))").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
        HStack {
            Button("Eat now") { g.eatAndDrink(); flush(); tick += 1 }.buttonStyle(PillStyle(prominent: true))
            Button("Pack a ration") { g.packRation(); flush(); tick += 1 }.buttonStyle(PillStyle(prominent: false)).disabled(tins == 0)
        }
        Text("Packed in your bag: \(g.inv.count(.ration)) ration\(g.inv.count(.ration) == 1 ? "" : "s"), \(g.inv.count(.trailMeal)) trail meal\(g.inv.count(.trailMeal) == 1 ? "" : "s")")
            .font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7)).id(tick)
    }
    private func flush() { for e in model.game.drainEvents() { model.handleExternal(e) } }
}

/// Tap Max: what he's been thinking, and what's next.
struct ThoughtsCard: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { close() }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Color(red: 0.36, green: 0.28, blue: 0.45), Color(red: 0.2, green: 0.15, blue: 0.26)], startPoint: .top, endPoint: .bottom))
                        Text("M").font(.avenir(18, "DemiBold")).foregroundStyle(Color.cream)
                    }
                    .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Max").font(.avenir(17, "DemiBold")).foregroundStyle(Color.amber)
                        Text("thinking out loud").font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.5))
                    }
                    Spacer()
                    Button { close() } label: { Image(systemName: "xmark").foregroundStyle(Color.cream).frame(width: 40, height: 40) }
                }
                let log = model.thoughtLog.suffix(4)
                if log.isEmpty { Text("Quiet down here.").font(.avenir(17)).italic().foregroundStyle(Color.cream) }
                ForEach(Array(log.enumerated()), id: \.offset) { i, t in
                    Text("“\(t)”").font(.avenir(i == log.count - 1 ? 19 : 15)).italic()
                        .foregroundStyle(Color.cream.opacity(i == log.count - 1 ? 1 : 0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let c = model.ui.clue {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WHAT’S NEXT").font(.avenir(11, "DemiBold")).tracking(1.5).foregroundStyle(Color.amber)
                        Text(c).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.33, green: 0.21, blue: 0.14)))
                }
                HStack {
                    Button("Journal") { close(); model.sheet = .journal }.buttonStyle(PillStyle(prominent: false))
                    Button("Build") { close(); model.sheet = .workbench }.buttonStyle(PillStyle(prominent: false))
                    Button("Bag") { close(); model.sheet = .pack }.buttonStyle(PillStyle(prominent: false))
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [Color(red: 0.13, green: 0.09, blue: 0.1), Color(red: 0.09, green: 0.06, blue: 0.07)], startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.amber.opacity(0.25)))
            .padding(.horizontal, 18)
        }
    }
    private func close() { withAnimation(.easeOut(duration: 0.2)) { model.showThoughts = false } }
}

/// Workshop storage and the bag, side by side. Tap something to move it across.
struct StorageView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0
    var body: some View {
        let g = model.game
        let stored = ItemID.allCases.filter { g.storage.count($0) > 0 }
        Text("Tap an item to move it. Bag holds \(Inventory.capacity) pockets; storage holds everything else.")
            .font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7))
        // The wood pile: wood lashed to the bag on one side, the stack in storage on the other.
        HStack(spacing: 10) {
            WoodIcon().frame(width: 30, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text("Wood").font(.avenir(14, "DemiBold")).foregroundStyle(Color.cream)
                Text("Bag \(g.inv.wood)/\(Inventory.woodCap) · Stored \(g.storage.wood)").font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.65)).monospacedDigit()
            }
            Spacer(minLength: 4)
            Button { g.storeWood(); model.haptics.tap(); tick += 1 } label: { Label("Store", systemImage: "arrow.right").font(.avenir(13, "DemiBold")) }
                .buttonStyle(.plain).foregroundStyle(Color.amber).padding(.horizontal, 10).frame(height: 34)
                .background(Capsule().fill(Color.black.opacity(0.3))).disabled(g.inv.wood == 0).opacity(g.inv.wood == 0 ? 0.4 : 1)
            Button { g.takeWood(); model.haptics.tap(); tick += 1 } label: { Label("Take", systemImage: "arrow.left").font(.avenir(13, "DemiBold")) }
                .buttonStyle(.plain).foregroundStyle(Color.amber).padding(.horizontal, 10).frame(height: 34)
                .background(Capsule().fill(Color.black.opacity(0.3))).disabled(g.storage.wood == 0 || g.inv.wood >= Inventory.woodCap).opacity(g.storage.wood == 0 ? 0.4 : 1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.2, green: 0.13, blue: 0.09)))
        .id(tick)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BAG · \(Inventory.capacity - g.inv.freeSlots)/\(Inventory.capacity)").font(.avenir(11, "DemiBold")).tracking(1.4).foregroundStyle(Color.amber)
                ForEach(Array(g.inv.slots.enumerated()), id: \.offset) { i, s in
                    if let s { tile(s.id, s.count, arrow: "arrow.right") { g.storeSlot(i); tick += 1 } }
                }
                if g.inv.freeSlots == Inventory.capacity { Text("Empty").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.4)) }
                Button("Store all") { g.depositAll(); tick += 1 }.buttonStyle(PillStyle(prominent: false))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text("STORAGE").font(.avenir(11, "DemiBold")).tracking(1.4).foregroundStyle(Color.amber)
                ForEach(stored, id: \.self) { id in
                    tile(id, g.storage.count(id), arrow: "arrow.left") { g.take(id, id.maxStack); tick += 1 }
                }
                if stored.isEmpty { Text("Empty").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.4)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(tick)
    }
    private func tile(_ id: ItemID, _ n: Int, arrow: String, _ act: @escaping () -> Void) -> some View {
        Button(action: { act(); model.haptics.tap() }) {
            HStack(spacing: 8) {
                Image(systemName: id.symbol).foregroundStyle(id.tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(id.name).font(.avenir(13, "DemiBold")).foregroundStyle(Color.cream).lineLimit(1).minimumScaleFactor(0.8)
                    Text("×\(n)").font(.avenir(11)).foregroundStyle(Color.cream.opacity(0.6))
                }
                Spacer(minLength: 2)
                Image(systemName: arrow).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.amber)
            }
            .padding(.horizontal, 10).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.2, green: 0.13, blue: 0.09)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.85, green: 0.68, blue: 0.45).opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }
}

// MARK: the bag

extension ItemID {
    /// A glyph for the bag grid.
    var symbol: String {
        switch self {
        case .chargeCrystal: return "diamond.fill"
        case .liftTooth: return "triangle.fill"
        case .spareGrip: return "capsule.portrait.fill"
        case .fasteners: return "circle.grid.2x2.fill"
        case .pipe: return "cylinder.fill"
        case .wire: return "point.topleft.down.curvedto.point.bottomright.up"
        case .lampCell: return "battery.75"
        case .seedTin: return "leaf.fill"
        case .pressureGauge: return "gauge.medium"
        case .batteryCell: return "battery.100.bolt"
        case .greens: return "carrot.fill"
        case .trailMeal: return "takeoutbag.and.cup.and.straw.fill"
        case .lamp: return "lightbulb.fill"
        case .ladderSection: return "stairs"
        case .waterTank: return "drop.fill"
        case .pressureValve: return "wrench.adjustable.fill"
        case .rope: return "lasso"
        case .ration: return "fork.knife"
        case .campCrate: return "shippingbox.fill"
        case .glowcap: return "leaf.fill"
        case .workbenchKit: return "hammer.fill"
        case .cotKit: return "bed.double.fill"
        case .woodLadder: return "stairs"
        case .torch: return "flame.fill"
        case .copperOre: return "circle.hexagongrid.fill"
        case .ironOre: return "hexagon.fill"
        case .quartz: return "rhombus.fill"
        case .coin: return "centsign.circle.fill"
        case .photo: return "photo.fill"
        case .toy: return "bird.fill"
        case .spores: return "sparkles"
        }
    }
    var tint: Color {
        switch self {
        case .chargeCrystal: return .violet
        case .copperOre: return Color(red: 0.45, green: 0.85, blue: 0.7)
        case .ironOre: return Color(red: 0.85, green: 0.5, blue: 0.4)
        case .quartz: return Color(red: 0.85, green: 0.95, blue: 1)
        case .coin: return Color(red: 0.95, green: 0.8, blue: 0.4)
        case .spores: return Color(red: 0.6, green: 1, blue: 0.75)
        case .seedTin, .greens: return Color(red: 0.6, green: 0.85, blue: 0.5)
        case .lampCell, .batteryCell, .lamp: return Color(red: 1, green: 0.85, blue: 0.5)
        case .waterTank: return Color(red: 0.55, green: 0.8, blue: 1)
        case .rope, .trailMeal: return Color(red: 0.9, green: 0.75, blue: 0.55)
        default: return Color(red: 0.86, green: 0.88, blue: 0.9)
        }
    }
}

extension Tool {
    var note: String {
        switch self {
        case .shovel: return "Cuts earth sideways and down, hacks roots, digs footholds. Good for beds, too."
        case .flashlight: return "One soft beam. Shows what’s ahead."
        case .shortPick: return "Dig UP to open soft seams overhead, and packed earth too."
        case .hammer: return "For fixing things: seized machines, stuck panels, setting things up."
        case .breaker: return "Swing at bedrock to crack it into rubble, then dig the rubble out."
        }
    }
}

private let leather = Color(red: 0.24, green: 0.15, blue: 0.1)
private let leatherDark = Color(red: 0.15, green: 0.09, blue: 0.06)
private let stitch = Color(red: 0.85, green: 0.68, blue: 0.45)

/// Max's bag, drawn as a bag: a leather flap, ten pockets, tools on the belt, wood strapped on the side.
struct BagSheet: View {
    @EnvironmentObject var model: GameModel
    @State private var picked: Int? = nil
    @State private var shown = false
    @State private var bump = 0

    var body: some View {
        let g = model.game
        let used = Inventory.capacity - g.inv.freeSlots
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.45).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 14) {
                // Flap with buckle
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: 30, bottomLeadingRadius: 46, bottomTrailingRadius: 46, topTrailingRadius: 30)
                        .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.23, blue: 0.15), leather], startPoint: .top, endPoint: .bottom))
                    UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 42, bottomTrailingRadius: 42, topTrailingRadius: 26)
                        .stroke(stitch.opacity(0.55), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).padding(5)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max’s bag").font(.avenir(21, "DemiBold")).foregroundStyle(Color.cream)
                            Text("\(used) of \(Inventory.capacity) pockets used").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7))
                        }
                        Spacer()
                        Button { close() } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6).stroke(Color(red: 0.85, green: 0.72, blue: 0.45), lineWidth: 3).frame(width: 30, height: 24)
                                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.cream)
                            }
                            .frame(width: 44, height: 44)
                        }
                        .accessibilityIdentifier("bag.close")
                    }
                    .padding(.horizontal, 22)
                }
                .frame(height: 82)

                // Pockets
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(0..<Inventory.capacity, id: \.self) { i in
                        pocket(g.inv.slots[i], index: i)
                    }
                }
                .id(bump)
                .padding(.horizontal, 16)

                // Fixed height, so tapping a pocket never makes the bag jump.
                detail(g)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(height: 80, alignment: .center)
                    .padding(.horizontal, 16)
                    .animation(.easeOut(duration: 0.2), value: picked)

                // Wood strap
                HStack(spacing: 10) {
                    WoodIcon().frame(width: 30, height: 22)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Wood, strapped outside").font(.avenir(14, "DemiBold")).foregroundStyle(Color.cream)
                            Spacer()
                            Text("\(g.inv.wood) / \(Inventory.woodCap)").font(.avenir(13, "DemiBold")).monospacedDigit().foregroundStyle(Color.amber)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.black.opacity(0.35))
                                Capsule().fill(Color(red: 0.72, green: 0.5, blue: 0.3)).frame(width: geo.size.width * CGFloat(g.inv.wood) / CGFloat(Inventory.woodCap))
                            }
                        }
                        .frame(height: 7)
                        Text(g.inv.wood > 0 ? "A plank costs \(Inventory.plankCost). Lay them to bridge gaps or cover holes." : "Hack at roots to get wood. A plank costs \(Inventory.plankCost).")
                            .font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.65))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(leatherDark.opacity(0.8)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(stitch.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .padding(.horizontal, 16)

                // Belt
                VStack(alignment: .leading, spacing: 8) {
                    Text("ON THE BELT").font(.avenir(11, "DemiBold")).tracking(1.5).foregroundStyle(stitch)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(g.inv.belt, id: \.self) { t in
                                HStack(spacing: 6) {
                                    toolGlyph(t).frame(width: 20, height: 20)
                                    Text(t.name).font(.avenir(13, "DemiBold"))
                                }
                                .foregroundStyle(Color.cream)
                                .padding(.horizontal, 12).frame(height: 36)
                                .background(Capsule().fill(Color.black.opacity(0.3)))
                                .overlay(Capsule().stroke(stitch.opacity(0.35)))
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)

                Text("Small parts stack up to 6 in a pocket. Bulky things take a whole pocket. At home, storage holds the rest.")
                    .font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.55))
                    .padding(.horizontal, 18).padding(.bottom, 6)
            }
            .padding(.bottom, 16)
            .background(
                RoundedRectangle(cornerRadius: 34)
                    .fill(LinearGradient(colors: [leather, leatherDark], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(Color.black.opacity(0.5), lineWidth: 2))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(stitch.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6, 4])).padding(5))
            .padding(10)
            .offset(y: shown ? 0 : 500)
        }
        .onAppear { withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { shown = true } }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.18)) { shown = false }
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.18)); model.sheet = nil }
    }

    @ViewBuilder private func toolGlyph(_ t: Tool) -> some View {
        switch t {
        case .shovel: DigIcon().rotationEffect(.degrees(-45))
        case .flashlight: Image(systemName: "flashlight.on.fill").resizable().scaledToFit()
        case .shortPick: Image(systemName: "hammer.fill").resizable().scaledToFit()
        case .hammer: Image(systemName: "hammer").resizable().scaledToFit()
        case .breaker: Image(systemName: "wrench.and.screwdriver.fill").resizable().scaledToFit()
        }
    }

    private func pocket(_ s: ItemStack?, index: Int) -> some View {
        let on = picked == index && s != nil
        return Button {
            guard s != nil else { return }
            picked = picked == index ? nil : index
            model.haptics.tap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(s == nil ? Color.black.opacity(0.22) : Color(red: 0.2, green: 0.13, blue: 0.09))
                if s == nil {
                    RoundedRectangle(cornerRadius: 14).stroke(stitch.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    RoundedRectangle(cornerRadius: 14).stroke(on ? Color.amber : stitch.opacity(0.4), lineWidth: on ? 2 : 1)
                }
                if let s {
                    Image(systemName: s.id.symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(s.id.tint)
                        .shadow(color: s.id.tint.opacity(0.35), radius: 6)
                    if s.count > 1 {
                        Text("\(s.count)").font(.avenir(12, "Bold")).foregroundStyle(.black)
                            .padding(.horizontal, 5).background(Capsule().fill(Color.amber))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(4)
                    }
                    if s.id.bulky {
                        Image(systemName: "shippingbox.fill").font(.system(size: 9)).foregroundStyle(Color.cream.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .scaleEffect(on ? 1.06 : 1)
            .animation(.spring(duration: 0.25), value: on)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(s.map { "\($0.id.name) \($0.count)" } ?? "empty pocket")
    }

    @ViewBuilder private func detail(_ g: Game) -> some View {
        if let i = picked, let s = g.inv.slots[i] {
            HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.count > 1 ? "\(s.id.name) ×\(s.count)" : s.id.name).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream)
                Text(s.id.blurb + (s.id.bulky ? " Bulky: takes a whole pocket." : "")).font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.75))
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                if g.atHome {
                    Button("Store") { g.storeSlot(i); picked = nil; model.haptics.tap(); bump += 1 }
                        .font(.avenir(13, "DemiBold")).foregroundStyle(.black)
                        .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(Color.amber))
                }
                if s.id.food != nil {
                    Button("Eat") { g.eat(s.id); picked = g.inv.slots[i] == nil ? nil : i; model.haptics.tap(); bump += 1 }
                        .font(.avenir(13, "DemiBold")).foregroundStyle(.black)
                        .padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(Color(red: 0.7, green: 0.85, blue: 0.45)))
                }
                Button("Drop") { g.dropSlot(i); picked = nil; model.haptics.tap(); bump += 1 }
                    .font(.avenir(13, "DemiBold")).foregroundStyle(Color.cream)
                    .padding(.horizontal, 12).frame(height: 30).background(Capsule().stroke(Color.cream.opacity(0.5)))
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.28)))
            .transition(.opacity)
        } else if let pin = g.pinnedRecipe, let r = Recipes.all.first(where: { $0.id == pin }) {
            Text("Pinned: \(r.name) · " + r.inputs.map { "\($0.id.name) \(min(g.available($0.id), $0.count))/\($0.count)" }.joined(separator: " · "))
                .font(.avenir(13)).foregroundStyle(Color.amber.opacity(0.9)).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(g.inv.freeSlots == Inventory.capacity ? "Empty. Things Max picks up go here." : "Tap a pocket to see what’s in it.")
                .font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.6)).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: the journal

private let parchment = Color(red: 0.93, green: 0.86, blue: 0.71)
private let parchmentEdge = Color(red: 0.8, green: 0.68, blue: 0.5)
private let ink = Color(red: 0.24, green: 0.15, blue: 0.1)

/// A wooden rod with turned ends: the top and bottom of the scroll.
struct ScrollRod: View {
    var body: some View {
        ZStack {
            Capsule().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.35, blue: 0.2), Color(red: 0.3, green: 0.17, blue: 0.1)], startPoint: .top, endPoint: .bottom))
                .frame(height: 20)
            HStack {
                knob; Spacer(); knob
            }
        }
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }
    private var knob: some View {
        Circle().fill(RadialGradient(colors: [Color(red: 0.75, green: 0.55, blue: 0.3), Color(red: 0.35, green: 0.2, blue: 0.1)], center: .topLeading, startRadius: 1, endRadius: 18))
            .frame(width: 28, height: 28)
    }
}

/// The journal as a scroll: it unrolls downward, ink on parchment.
struct ScrollJournal: View {
    @EnvironmentObject var model: GameModel
    @State private var open = false

    var body: some View {
        let g = model.game
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { close() }
            VStack(spacing: 0) {
                ScrollRod().padding(.horizontal, -8)
                ZStack(alignment: .top) {
                    Rectangle().fill(LinearGradient(colors: [parchmentEdge, parchment, parchment, parchmentEdge], startPoint: .leading, endPoint: .trailing))
                    Rectangle().fill(LinearGradient(colors: [.black.opacity(0.18), .clear, .clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Journal").font(.system(size: 28, weight: .semibold, design: .serif)).italic().foregroundStyle(ink)
                                Spacer()
                                Button { close() } label: {
                                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink.opacity(0.7)).frame(width: 44, height: 44)
                                }
                                .accessibilityIdentifier("journal.close")
                            }
                            HStack {
                                Text("Chapter \(min(g.story.chapter, 4))").font(.system(size: 13, weight: .semibold, design: .serif)).tracking(2).foregroundStyle(ink.opacity(0.6))
                                Spacer()
                                Button { model.sheet = .checkpoints } label: {
                                    Label("Checkpoints", systemImage: "clock.arrow.circlepath").font(.system(size: 14, weight: .semibold, design: .serif)).foregroundStyle(ink)
                                        .padding(.horizontal, 10).frame(height: 32).overlay(Capsule().stroke(ink.opacity(0.4)))
                                }
                                .accessibilityIdentifier("journal.checkpoints")
                            }
                            ForEach(g.story.quests.reversed()) { q in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text((q.side ? "Side · " : "") + q.title).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(ink.opacity(q.done ? 0.45 : 1))
                                    ForEach(q.steps, id: \.id) { s in
                                        HStack(alignment: .top, spacing: 10) {
                                            InkMark(done: s.done).frame(width: 18, height: 18).padding(.top, 2)
                                            Text(s.text).font(.system(size: 16, design: .serif)).foregroundStyle(ink.opacity(s.done ? 0.45 : 0.9))
                                                .strikethrough(s.done, color: ink.opacity(0.35))
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    if let o = q.outcome { Text(o).font(.system(size: 15, design: .serif)).italic().foregroundStyle(Color(red: 0.5, green: 0.25, blue: 0.12)) }
                                }
                                Rectangle().fill(ink.opacity(0.15)).frame(height: 1).padding(.vertical, 2)
                            }
                        }
                        .padding(.horizontal, 26).padding(.vertical, 18)
                    }
                }
                .frame(maxHeight: open ? 470 : 0)
                .clipped()
                ScrollRod().padding(.horizontal, -8)
            }
            .padding(.horizontal, 26)
        }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { open = true } }
    }

    private func close() {
        withAnimation(.easeIn(duration: 0.22)) { open = false }
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.22)); model.sheet = nil }
    }
}

/// A hand-inked circle, ticked when done.
struct InkMark: View {
    var done: Bool
    var body: some View {
        Canvas { ctx, size in
            let s = size.width
            var c = Path(); c.addEllipse(in: CGRect(x: 1.5, y: 1.5, width: s - 3, height: s - 3))
            ctx.stroke(c, with: .color(ink.opacity(0.7)), lineWidth: 1.3)
            if done {
                var t = Path()
                t.move(to: CGPoint(x: s * 0.2, y: s * 0.52)); t.addQuadCurve(to: CGPoint(x: s * 0.42, y: s * 0.78), control: CGPoint(x: s * 0.32, y: s * 0.62))
                t.addQuadCurve(to: CGPoint(x: s * 0.95, y: s * 0.05), control: CGPoint(x: s * 0.6, y: s * 0.35))
                ctx.stroke(t, with: .color(Color(red: 0.55, green: 0.18, blue: 0.1)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
    }
}

struct MissionView: View {
    @EnvironmentObject var model: GameModel
    @State private var meals = 0
    var body: some View {
        let g = model.game
        if g.activeJob != nil {
            Text("Max is already out on a job.").font(.avenir(15)).foregroundStyle(Color.cream)
        } else {
            Text("Pick one job before you head off. Max works through it on his own, even with the game closed, and stops if he reaches something you should see first.")
                .font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.85))
            let mealCount = g.available(.trailMeal)
            if mealCount > 0 {
                Stepper("Pack trail meals: \(meals)", value: $meals, in: 0...min(3, mealCount)).font(.avenir(15)).foregroundStyle(Color.cream)
            }
            let jobs = g.availableJobs(meals: meals)
            if jobs.isEmpty {
                Text("No jobs yet. Dig a tunnel, plant a bed, or find salvage first.").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.7))
            }
            ForEach(jobs) { j in
                Row(title: j.title, detail: j.summary) {
                    Button("Start") { model.startJob(j) }.buttonStyle(PillStyle(prominent: true))
                }
            }
        }
    }
}

struct ConversationCard: View {
    @EnvironmentObject var model: GameModel
    let convo: Conversation
    var body: some View {
        let last = model.lineIndex >= convo.lines.count - 1
        TalkStage(speaker: convo.speaker,
                  line: convo.lines[min(model.lineIndex, convo.lines.count - 1)],
                  progress: (model.lineIndex + 1, convo.lines.count),
                  choices: last ? convo.choices.map { TalkStage.Choice(id: $0.id, label: $0.label, detail: nil, enabled: true, primary: false) } : [],
                  ledger: [],
                  onChoose: { model.choose($0) },
                  onAdvance: last ? nil : { model.advanceConversation() },
                  onClose: nil)
    }
}

/// A person's panel (agreements, trades, asks) shown as a conversation.
struct TalkPanel: View {
    @EnvironmentObject var model: GameModel
    let panel: Panel
    var body: some View {
        let actions = panel.rows.filter { $0.style == .action || $0.style == .primary }
        let ledger = panel.rows.filter { $0.style == .info || $0.style == .done }
        ZStack {
            TalkStage(speaker: panel.speaker ?? panel.title,
                      line: panel.lines.joined(separator: " "),
                      progress: nil,
                      choices: actions.map { TalkStage.Choice(id: $0.id, label: $0.label, detail: $0.detail, enabled: $0.enabled, primary: $0.style == .primary) } + [TalkStage.Choice(id: "__bye", label: "That’s all for now.", detail: nil, enabled: true, primary: false)],
                      ledger: ledger,
                      onChoose: { id in
                          if id == "__bye" { model.closePanel(); return }
                          if let r = panel.rows.first(where: { $0.id == id }) { model.tapRow(r) }
                      },
                      onAdvance: nil,
                      onClose: { model.closePanel() })
            if let c = model.confirming {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Are you sure?").font(.avenir(19, "Bold")).foregroundStyle(Color.cream)
                    Text(c.confirm ?? "").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.85)).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Back") { model.confirming = nil }.buttonStyle(PillStyle(prominent: false))
                        Spacer()
                        Button("Do it") { model.tapRow(c) }.buttonStyle(PillStyle(prominent: true))
                    }
                }
                .padding(20)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.2, green: 0.08, blue: 0.07)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.red.opacity(0.4)))
                .padding(24)
            }
        }
    }
}

/// Conversation mode: the world dims, the speaker's portrait comes up, their words type out,
/// and Max's replies are numbered choices underneath.
struct TalkStage: View {
    struct Choice: Identifiable { var id: String; var label: String; var detail: String?; var enabled: Bool; var primary: Bool }
    let speaker: String
    let line: String
    let progress: (Int, Int)?
    let choices: [Choice]
    let ledger: [PanelRow]
    let onChoose: (String) -> Void
    let onAdvance: (() -> Void)?
    let onClose: (() -> Void)?
    @State private var shown = 0
    @State private var showLedger = false
    @State private var appeared = false

    var body: some View {
        let typing = shown < line.count
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color.black.opacity(0.2), Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .onTapGesture { tapLine() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom, spacing: 12) {
                    Portrait(name: speaker).frame(width: 96, height: 112)
                        .offset(y: appeared ? 0 : 30).opacity(appeared ? 1 : 0)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(speaker.uppercased()).font(.avenir(13, "Bold")).tracking(2.5).foregroundStyle(Color.black)
                            .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(Color.amber))
                        if let p = progress, p.1 > 1 {
                            Text("\(p.0) / \(p.1)").font(.avenir(11, "DemiBold")).foregroundStyle(Color.cream.opacity(0.5)).padding(.leading, 6)
                        }
                    }
                    .padding(.bottom, 10)
                    Spacer()
                    if let onClose {
                        Button { onClose() } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.cream).frame(width: 38, height: 38).background(Circle().fill(Color.white.opacity(0.1))) }
                            .padding(.bottom, 10)
                    }
                }
                .padding(.horizontal, 6)
                // the speech bubble
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(line.prefix(shown))).font(.avenir(19, "Medium")).foregroundStyle(Ink.main)
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .topLeading) { Text(line).font(.avenir(19, "Medium")).opacity(0) }   // holds the full height while typing
                    if onAdvance != nil && !typing {
                        HStack { Spacer(); Image(systemName: "arrowtriangle.down.fill").font(.system(size: 11)).foregroundStyle(Ink.accent) }
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.98, green: 0.93, blue: 0.83)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color(red: 0.78, green: 0.6, blue: 0.4), lineWidth: 3))
                .contentShape(Rectangle())
                .onTapGesture { tapLine() }
                // Max's replies
                if !typing && !choices.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(Array(choices.enumerated()), id: \.element.id) { i, c in
                            Button { onChoose(c.id) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(i + 1)").font(.avenir(13, "Bold")).foregroundStyle(Color.black)
                                        .frame(width: 24, height: 24).background(Circle().fill(c.primary ? Color.amber : Color.cream.opacity(0.85)))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(c.label).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream).multilineTextAlignment(.leading)
                                        if let d = c.detail { Text(d).font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.65)).multilineTextAlignment(.leading) }
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.amber.opacity(0.7)).padding(.top, 5)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 16).fill(c.primary ? Color.amber.opacity(0.2) : Color.white.opacity(0.07)))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(c.primary ? Color.amber.opacity(0.6) : Color.white.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .disabled(!c.enabled).opacity(c.enabled ? 1 : 0.4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 12)
                }
                if !ledger.isEmpty && !typing {
                    Button { withAnimation(.spring(duration: 0.3)) { showLedger.toggle() } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.plaintext")
                            Text(showLedger ? "Hide what you’ve agreed" : "What you’ve agreed (\(ledger.count))")
                            Image(systemName: showLedger ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .font(.avenir(13, "DemiBold")).foregroundStyle(Color.amber)
                        .frame(maxWidth: .infinity).frame(height: 36)
                    }
                    .buttonStyle(.plain)
                    if showLedger {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(ledger) { r in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: r.style == .done ? "checkmark.circle.fill" : "circle").font(.system(size: 12))
                                            .foregroundStyle(r.style == .done ? Color.green.opacity(0.8) : Color.cream.opacity(0.5)).padding(.top, 2)
                                        Text(r.label).font(.avenir(13)).foregroundStyle(Color.cream.opacity(r.style == .done ? 0.5 : 0.85))
                                            .strikethrough(r.style == .done, color: Color.cream.opacity(0.4))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            .padding(12)
                        }
                        .frame(maxHeight: 170)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.4)))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 18)
            .animation(.spring(duration: 0.3), value: typing)
        }
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true } }
        .task(id: line) {
            shown = 0
            for i in 0...line.count {
                shown = i
                try? await Task.sleep(for: .milliseconds(18))
                if Task.isCancelled { break }
            }
        }
    }

    private func tapLine() {
        if shown < line.count { shown = line.count } else { onAdvance?() }
    }
}

/// A painted bust of whoever's talking. Mara: grey-streaked hair, green work scarf. Others get their own colours.
struct Portrait: View {
    let name: String
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let pal: (hair: Color, scarf: Color, coat: Color, skin: Color) = {
                    switch name.lowercased() {
                    case "mara": return (Color(red: 0.42, green: 0.38, blue: 0.4), Color(red: 0.32, green: 0.55, blue: 0.42), Color(red: 0.36, green: 0.3, blue: 0.27), Color(red: 0.86, green: 0.68, blue: 0.55))
                    case "odi": return (Color(red: 0.15, green: 0.12, blue: 0.12), Color(red: 0.75, green: 0.5, blue: 0.2), Color(red: 0.25, green: 0.3, blue: 0.38), Color(red: 0.55, green: 0.38, blue: 0.28))
                    default: return (Color(red: 0.29, green: 0.23, blue: 0.36), Color(red: 0.78, green: 0.27, blue: 0.18), Color(red: 0.93, green: 0.86, blue: 0.74), Color(red: 0.95, green: 0.82, blue: 0.7))
                    }
                }()
                let breathe = CGFloat(sin(t * 1.6)) * 1.2
                // glow behind
                ctx.fill(Path(ellipseIn: CGRect(x: -w * 0.1, y: h * 0.05, width: w * 1.2, height: h)), with: .radialGradient(Gradient(colors: [Color.amber.opacity(0.35), .clear]), center: CGPoint(x: w / 2, y: h * 0.5), startRadius: 2, endRadius: w * 0.6))
                // shoulders
                ctx.fill(Path(roundedRect: CGRect(x: w * 0.08, y: h * 0.68 - breathe, width: w * 0.84, height: h * 0.4), cornerRadius: w * 0.3), with: .color(pal.coat))
                ctx.fill(Path(roundedRect: CGRect(x: w * 0.28, y: h * 0.62 - breathe, width: w * 0.44, height: h * 0.14), cornerRadius: w * 0.07), with: .color(pal.scarf))
                // head
                let head = CGRect(x: w * 0.27, y: h * 0.2 - breathe, width: w * 0.46, height: h * 0.46)
                ctx.fill(Path(ellipseIn: head.insetBy(dx: -w * 0.04, dy: -h * 0.02).offsetBy(dx: 0, dy: h * 0.03)), with: .color(pal.hair))
                ctx.fill(Path(ellipseIn: head), with: .color(pal.skin))
                ctx.fill(Path(ellipseIn: CGRect(x: head.minX - w * 0.02, y: head.minY - h * 0.03, width: head.width + w * 0.04, height: head.height * 0.42)), with: .color(pal.hair))
                // eyes (blinking)
                let blink = (t.truncatingRemainder(dividingBy: 4.2)) < 0.12
                for dx in [-0.09, 0.09] as [CGFloat] {
                    let e = CGRect(x: head.midX + w * dx - 3, y: head.midY - 2, width: 6, height: blink ? 1.5 : 6)
                    ctx.fill(Path(ellipseIn: e), with: .color(Color(red: 0.15, green: 0.1, blue: 0.1)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: head.midX - w * 0.17, y: head.midY + 6, width: 7, height: 4)), with: .color(Color(red: 0.9, green: 0.5, blue: 0.45).opacity(0.5)))
                ctx.fill(Path(ellipseIn: CGRect(x: head.midX + w * 0.17 - 7, y: head.midY + 6, width: 7, height: 4)), with: .color(Color(red: 0.9, green: 0.5, blue: 0.45).opacity(0.5)))
                var mouth = Path(); mouth.move(to: CGPoint(x: head.midX - 5, y: head.midY + 12)); mouth.addQuadCurve(to: CGPoint(x: head.midX + 5, y: head.midY + 12), control: CGPoint(x: head.midX, y: head.midY + 15))
                ctx.stroke(mouth, with: .color(Color(red: 0.4, green: 0.2, blue: 0.15)), lineWidth: 1.6)
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.16, green: 0.1, blue: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.amber.opacity(0.6), lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}

struct ReportCard: View {
    @EnvironmentObject var model: GameModel
    let report: JobReport
    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text("While you were away").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
                Text(report.title).font(.avenir(22, "DemiBold")).foregroundStyle(Color.cream)
                ForEach(report.lines, id: \.self) { Text($0).font(.avenir(16)).foregroundStyle(Color.cream) }
                Text(report.stopped).font(.avenir(15)).italic().foregroundStyle(Color.cream.opacity(0.75))
                Button("See it") { model.report = nil }.buttonStyle(PillStyle(prominent: true))
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color(red: 0.1, green: 0.06, blue: 0.08).opacity(0.96)))
            .padding(18)
        }
    }
}


/// A small panel that opens at the person or object it belongs to.
struct PanelCard: View {
    @EnvironmentObject var model: GameModel
    let panel: Panel
    private let width: CGFloat = 300

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.closePanel() }
                card
                    .frame(width: min(width, geo.size.width - 16))
                    .alignmentGuide(.leading) { d in
                        let left = min(max(8, model.panelPoint.x - d.width / 2), geo.size.width - d.width - 8)
                        return -left
                    }
                    .alignmentGuide(.top) { d in
                        // Sit just above the thing it's about; never off the top of the screen.
                        let top = min(max(56, model.panelPoint.y - d.height - 14), geo.size.height - d.height - 8)
                        return -top
                    }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(panel.speaker ?? panel.title).font(.avenir(13, "DemiBold")).foregroundStyle(Color.amber)
                Spacer()
                Button { model.closePanel() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.cream.opacity(0.7))
                        .frame(width: 30, height: 30)
                }
            }
            ForEach(panel.lines, id: \.self) { l in
                Text(l).font(.avenir(15)).foregroundStyle(Color.cream).fixedSize(horizontal: false, vertical: true)
            }
            if let c = model.confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Text(c.confirm ?? "").font(.avenir(14)).foregroundStyle(Color.cream).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Back") { model.confirming = nil }.buttonStyle(PillStyle(prominent: false))
                        Button("Do it") { model.tapRow(c) }.buttonStyle(PillStyle(prominent: true))
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.4, green: 0.12, blue: 0.1).opacity(0.5)))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(panel.rows) { r in row(r) }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.1, green: 0.06, blue: 0.08).opacity(0.95)))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder private func row(_ r: PanelRow) -> some View {
        switch r.style {
        case .info, .done:
            Text(r.label).font(.avenir(13)).foregroundStyle(Color.cream.opacity(r.style == .done ? 0.55 : 0.8))
                .fixedSize(horizontal: false, vertical: true)
        case .action, .primary:
            Button { model.tapRow(r) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.label).font(.avenir(15, "DemiBold")).foregroundStyle(Color.cream)
                    if let d = r.detail { Text(d).font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.7)).fixedSize(horizontal: false, vertical: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 12).fill(r.style == .primary ? Color(red: 1, green: 0.67, blue: 0.4).opacity(0.25) : Color.white.opacity(0.08)))
            }
            .disabled(!r.enabled)
            .opacity(r.enabled ? 1 : 0.45)
        }
    }
}


// MARK: camp crate

struct CampView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0
    var body: some View {
        let g = model.game
        let id = g.openCamp ?? ""
        let stock = g.campStock(id)
        Text("In the crate").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
        if stock.isEmpty { Text("Empty. Leave things here to pick up on another trip.").font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.7)) }
        ForEach(stock, id: \.self) { s in
            Row(title: s.count > 1 ? "\(s.id.name) ×\(s.count)" : s.id.name, detail: s.id.bulky ? "Bulky: takes a whole pocket." : s.id.blurb) {
                Button("Take") { g.takeFromCamp(id, item: s.id); tick += 1 }.buttonStyle(PillStyle(prominent: true))
            }
        }
        Text("In your bag · \(Inventory.capacity - g.inv.freeSlots) of \(Inventory.capacity)").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
        ForEach(Array(g.inv.slots.enumerated()), id: \.offset) { i, s in
            if let s {
                Row(title: s.count > 1 ? "\(s.id.name) ×\(s.count)" : s.id.name, detail: s.id.bulky ? "Bulky" : "") {
                    Button("Leave here") { g.stash(slot: i, in: id); tick += 1 }.buttonStyle(PillStyle(prominent: false))
                }
            }
        }
        Color.clear.frame(height: 1).id(tick)
    }
}

// MARK: map

/// Where Max has been: rooms and tunnels he's seen, the ways up, camps, caches and people.
struct MapView: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        let g = model.game
        let seen = g.story.explored
        VStack(alignment: .leading, spacing: 10) {
            Canvas { ctx, size in
                let W = Double(Landmarks.width), H = Double(Landmarks.height)
                // Crop to what's been seen, with a margin, so the map fills the card.
                var minX = W, maxX = 0.0, minY = H, maxY = 0.0
                let b = Double(Game.mapBlock)
                for k in seen { let x = Double(k % Game.mapCols) * b, y = Double(k / Game.mapCols) * b; minX = min(minX, x); maxX = max(maxX, x + b); minY = min(minY, y); maxY = max(maxY, y + b) }
                if seen.isEmpty { minX = 10; maxX = 40; minY = 20; maxY = 34 }
                minX -= 4; maxX += 4; minY -= 3; maxY += 3
                let s = min(size.width / (maxX - minX), size.height / (maxY - minY))
                func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: (x - minX) * s, y: (y - minY) * s) }
                // Seen ground: open space is light, earth dark; unseen stays black.
                for k in seen {
                    let bx = (k % Game.mapCols) * Game.mapBlock, by = (k / Game.mapCols) * Game.mapBlock
                    for dy in 0..<Game.mapBlock {
                        for dx in 0..<Game.mapBlock {
                            let c = bx + dx, r = by + dy
                            let m = g.world.m(c, r)
                            let col: Color = !m.solid ? Color(red: 0.86, green: 0.76, blue: 0.6).opacity(0.55)
                                : (m.hard ? Color(red: 0.25, green: 0.24, blue: 0.28) : Color(red: 0.32, green: 0.22, blue: 0.18))
                            ctx.fill(Path(CGRect(origin: pt(Double(c), Double(r)), size: CGSize(width: s + 0.3, height: s + 0.3))), with: .color(col))
                        }
                    }
                }
                // Ways up and down Max has found.
                for cl in g.world.climbs where seen.contains(Int(cl.top) / Game.mapBlock * Game.mapCols + Int(cl.x) / Game.mapBlock) || seen.contains(Int(cl.bottom - 1) / Game.mapBlock * Game.mapCols + Int(cl.x) / Game.mapBlock) {
                    var p = Path(); p.move(to: pt(cl.x, cl.bottom)); p.addLine(to: pt(cl.x, cl.top))
                    ctx.stroke(p, with: .color(Color.amber.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
                func mark(_ x: Double, _ y: Double, _ symbol: String, _ col: Color, _ label: String? = nil) {
                    let k = Int(y) / Game.mapBlock * Game.mapCols + Int(x) / Game.mapBlock
                    guard seen.contains(k) else { return }
                    let p = pt(x, y - 0.8)
                    ctx.draw(Text(Image(systemName: symbol)).font(.system(size: 13, weight: .bold)).foregroundColor(col), at: p)
                    if let label { ctx.draw(Text(label).font(.avenir(10, "DemiBold")).foregroundColor(Color.cream), at: CGPoint(x: p.x, y: p.y - 13)) }
                }
                mark(25, 30, "house.fill", Color.amber, "Home")
                if g.maraMet { mark(Landmarks.maraHome.x, Landmarks.maraHome.y, "person.fill", Color(red: 0.6, green: 0.85, blue: 0.8), "Mara") }
                if let s = g.world.prop("signal") { mark(s.pos.x, s.pos.y, "light.beacon.max.fill", s.flags.contains("lit") ? Color.amber : Color.gray) }
                if let l = g.world.prop("lantern.clue"), g.story.flags.contains("sawLantern") { mark(l.pos.x, l.pos.y, "questionmark.circle.fill", Color.violet) }
                for c in g.world.props(of: .camp) { mark(c.pos.x, c.pos.y, "tent.fill", Color(red: 0.95, green: 0.55, blue: 0.4), c.flags.first { $0.hasPrefix("name:") }.map { String($0.dropFirst(5)) }) }
                for p in g.world.props(of: .pile) { mark(p.pos.x, p.pos.y, "shippingbox.fill", Color.cream.opacity(0.8)) }
                // Max
                let mp = pt(g.max.pos.x, g.max.pos.y - 0.8)
                ctx.fill(Path(ellipseIn: CGRect(x: mp.x - 5, y: mp.y - 5, width: 10, height: 10)), with: .color(Color.amber))
                ctx.stroke(Path(ellipseIn: CGRect(x: mp.x - 8, y: mp.y - 8, width: 16, height: 16)), with: .color(Color.amber.opacity(0.5)), lineWidth: 1.5)
            }
            .frame(height: 300)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            HStack(spacing: 14) {
                Label("You", systemImage: "circle.fill").foregroundStyle(Color.amber)
                Label("Camp", systemImage: "tent.fill")
                Label("Ladder or rope", systemImage: "line.diagonal")
            }
            .font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.8))
            Text("Max is at \(Depth.label(atY: g.max.pos.y)). Only what he’s seen is on the map.")
                .font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7))
        }
    }
}


/// What's in a locker, crate or wreck: pick what to take, like going through a container.
struct LootView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0

    static func title(_ g: Game) -> String {
        guard let id = g.openLoot, let p = g.world.prop(id) else { return "Search" }
        switch p.kind {
        case .liftCar: return "Wrecked lift car"
        case .drillRig: return "Old drill rig"
        case .gantry: return "Lifting gantry"
        case .locker: return "Locker"
        case .crate: return "Tool crate"
        case .pile: return "Your pile"
        default: return "Search"
        }
    }

    var body: some View {
        let g = model.game
        let id = g.openLoot ?? ""
        let stock = g.world.prop(id)?.stock ?? []
        HStack {
            Text("Bag \(Inventory.capacity - g.inv.freeSlots)/\(Inventory.capacity) pockets").font(.avenir(13, "DemiBold"))
                .foregroundStyle(g.inv.freeSlots == 0 ? Color(red: 0.95, green: 0.55, blue: 0.45) : Color.amber)
            Spacer()
            if stock.count > 1 {
                Button("Take all") { g.takeFrom(propID: id); flush(); tick += 1 }.buttonStyle(PillStyle(prominent: true))
            }
        }
        if stock.isEmpty {
            Text("Nothing left here.").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.7))
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(stock, id: \.self) { s in
                Button { g.takeFrom(propID: id, only: s.id); flush(); model.haptics.tap(); tick += 1 } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.3))
                                Image(systemName: s.id.symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(s.id.tint)
                                    .shadow(color: s.id.tint.opacity(0.4), radius: 6)
                            }
                            .frame(width: 44, height: 44)
                            Spacer()
                            if s.count > 1 {
                                Text("×\(s.count)").font(.avenir(13, "Bold")).foregroundStyle(.black).padding(.horizontal, 6).background(Capsule().fill(Color.amber))
                            }
                        }
                        Text(s.id.name).font(.avenir(14, "DemiBold")).foregroundStyle(Color.cream).lineLimit(1).minimumScaleFactor(0.8)
                        Text(s.id.bulky ? "Bulky · whole pocket" : "Stacks to \(s.id.maxStack)").font(.avenir(11)).foregroundStyle(Color.cream.opacity(0.55))
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.to.line").font(.system(size: 10, weight: .bold))
                            Text("Take").font(.avenir(12, "DemiBold"))
                        }
                        .foregroundStyle(Color.amber)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color(red: 0.27, green: 0.17, blue: 0.11), Color(red: 0.17, green: 0.1, blue: 0.07)], startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.85, green: 0.68, blue: 0.45).opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Take \(s.id.name)")
            }
        }
        .id(tick)
    }
    private func flush() { for e in model.game.drainEvents() { model.handleExternal(e) } }
}


// MARK: build

/// The build screen: a grid of blueprints by category, the selected one large on a lit pedestal,
/// its parts in slots, and one big BUILD button.
struct BuildSheet: View {
    @EnvironmentObject var model: GameModel
    @State private var tab = BuildTab.all
    @State private var selected: String? = nil
    @State private var pop = false
    @State private var flash = 0.0
    @State private var tick = 0

    enum BuildTab: String, CaseIterable { case all = "All", tools = "Tools", gear = "Gear", field = "Field", home = "Home"
        var icon: String {
            switch self { case .all: return "square.grid.2x2.fill"; case .tools: return "wrench.and.screwdriver.fill"; case .gear: return "shippingbox.fill"; case .field: return "tent.fill"; case .home: return "house.fill" }
        }
    }

    static func tab(of r: Recipe) -> BuildTab {
        switch r.output {
        case .tool: return .tools
        case .upgrade: return .home
        case .item: return r.bench ? .gear : .field
        }
    }

    var body: some View {
        let g = model.game
        let all = g.knownRecipes
        let shown = all.filter { tab == .all || Self.tab(of: $0) == tab }
            .sorted { rank($0, g) < rank($1, g) }
        let sel = shown.first { $0.id == selected } ?? shown.first
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { model.sheet = nil }
            VStack(spacing: 12) {
                header(g)
                tabs(all)
                if let r = sel { detail(r, g) } else {
                    Text("Nothing to build yet. Ideas come once Max has seen the problem they solve.")
                        .font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.8)).padding(.vertical, 30)
                }
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(shown, id: \.id) { r in tile(r, g, on: r.id == sel?.id) }
                    }
                    .padding(.horizontal, 2).padding(.bottom, 6)
                }
                .frame(maxHeight: 220)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.11, blue: 0.1), Color(red: 0.08, green: 0.05, blue: 0.06)], startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.amber.opacity(0.22)))
            .padding(.horizontal, 10).padding(.bottom, 8)
            .id(tick)
        }
        .transition(.move(edge: .bottom))
    }

    private func rank(_ r: Recipe, _ g: Game) -> Int {
        let b = g.buildBlocker(r)
        if b == nil { return 0 }
        if b == "Already made" || b == "Already built" { return 3 }
        if b == "Needs a workbench" { return 1 }
        return 2
    }

    private func header(_ g: Game) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color.amber.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: "hammer.fill").foregroundStyle(Color.amber)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Build").font(.avenir(22, "Bold")).foregroundStyle(Color.cream)
                HStack(spacing: 5) {
                    Circle().fill(g.atBench ? Color.green : Color.amber).frame(width: 7, height: 7)
                    Text(g.atBench ? "At a workbench" : "In the field · bench builds locked").font(.avenir(12, "DemiBold")).foregroundStyle(Color.cream.opacity(0.7))
                }
            }
            Spacer()
            HStack(spacing: 5) {
                WoodIcon().frame(width: 20, height: 15)
                Text("\(g.woodAvailable)").font(.avenir(15, "Bold")).monospacedDigit().foregroundStyle(Color.cream)
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            Button { model.sheet = nil } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.cream).frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.08))) }
        }
    }

    private func tabs(_ all: [Recipe]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(BuildTab.allCases, id: \.self) { t in
                    let n = t == .all ? all.count : all.filter { Self.tab(of: $0) == t }.count
                    if n > 0 || t == .all {
                        Button { withAnimation(.spring(duration: 0.25)) { tab = t; selected = nil }; model.haptics.tap() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: t.icon).font(.system(size: 11, weight: .semibold))
                                Text(t.rawValue).font(.avenir(13, "DemiBold"))
                            }
                            .foregroundStyle(tab == t ? Color.black : Color.cream.opacity(0.8))
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(Capsule().fill(tab == t ? Color.amber : Color.white.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func detail(_ r: Recipe, _ g: Game) -> some View {
        let blocker = g.buildBlocker(r)
        let ok = blocker == nil
        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(RadialGradient(colors: [Color.amber.opacity(ok ? 0.45 : 0.15), Color.black.opacity(0.4)], center: .center, startRadius: 4, endRadius: 70))
                Ellipse().fill(Color.black.opacity(0.35)).frame(width: 80, height: 14).offset(y: 44)
                ItemArt(recipe: r).padding(20)
                    .scaleEffect(pop ? 1.25 : 1)
                    .shadow(color: Color.amber.opacity(ok ? 0.6 : 0), radius: 10)
                    .saturation(ok ? 1 : 0.35)
                RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(flash)).allowsHitTesting(false)
            }
            .frame(width: 124, height: 124)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.amber.opacity(ok ? 0.6 : 0.2), lineWidth: ok ? 1.5 : 1))
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(r.name).font(.avenir(18, "Bold")).foregroundStyle(Color.cream).lineLimit(1).minimumScaleFactor(0.75)
                    if !r.bench { tag("FIELD", Color.amber) }
                }
                Text(r.note).font(.avenir(12)).foregroundStyle(Color.cream.opacity(0.72)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if r.wood > 0 { slot(AnyView(WoodIcon()), have: g.woodAvailable, need: r.wood) }
                    ForEach(r.inputs, id: \.self) { s in
                        slot(AnyView(Image(systemName: s.id.symbol).resizable().scaledToFit().foregroundStyle(s.id.tint)), have: g.available(s.id), need: s.count)
                    }
                }
                Button { build(r, g) } label: {
                    Text(ok ? "BUILD" : (blocker ?? "")).font(.avenir(ok ? 16 : 13, "Bold")).tracking(ok ? 2 : 0)
                        .foregroundStyle(ok ? Color.black : Color(red: 0.95, green: 0.6, blue: 0.5))
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(Capsule().fill(ok ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.86, blue: 0.6), Color.amber], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.06))))
                        .shadow(color: Color.amber.opacity(ok ? 0.5 : 0), radius: 8)
                }
                .buttonStyle(.plain).disabled(!ok)
                .accessibilityIdentifier("build.\(r.id)")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.white.opacity(0.04)))
    }

    private func build(_ r: Recipe, _ g: Game) {
        g.craft(r.id)
        for e in g.drainEvents() { model.handleExternal(e) }
        model.haptics.bite()
        withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { pop = true; flash = 0.5 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { pop = false; flash = 0 }
            tick += 1
        }
    }

    private func tile(_ r: Recipe, _ g: Game, on: Bool) -> some View {
        let b = g.buildBlocker(r)
        let ok = b == nil
        let owned = b == "Already made" || b == "Already built"
        return Button { withAnimation(.spring(duration: 0.25)) { selected = r.id }; model.haptics.tap() } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(on ? Color.amber.opacity(0.22) : Color(red: 0.2, green: 0.14, blue: 0.11))
                ItemArt(recipe: r).padding(12)
                    .saturation(ok || owned ? 1 : 0.15).opacity(ok || owned ? 1 : 0.5)
                if owned {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Color.green, Color.black).padding(4)
                } else if ok {
                    Circle().fill(Color.amber).frame(width: 9, height: 9).padding(6).shadow(color: Color.amber, radius: 4)
                } else if b == "Needs a workbench" {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Color.cream.opacity(0.6)).padding(6)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color.amber : Color.white.opacity(ok ? 0.25 : 0.08), lineWidth: on ? 2 : 1))
            .scaleEffect(on ? 1.04 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(r.name)
    }

    private func slot(_ icon: AnyView, have: Int, need: Int) -> some View {
        let enough = have >= need
        return VStack(spacing: 2) {
            icon.frame(width: 20, height: 20)
            Text("\(min(have, need))/\(need)").font(.avenir(10, "Bold")).monospacedDigit()
                .foregroundStyle(enough ? Color.cream : Color(red: 0.95, green: 0.55, blue: 0.45))
        }
        .frame(width: 42, height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(enough ? Color.green.opacity(0.5) : Color.red.opacity(0.4)))
    }

    private func tag(_ s: String, _ c: Color) -> some View {
        Text(s).font(.avenir(9, "Bold")).tracking(1).foregroundStyle(.black).padding(.horizontal, 5).padding(.vertical, 2).background(Capsule().fill(c))
    }
}


/// Every checkpoint so far, newest first; tap one to go back there.
struct CheckpointsView: View {
    @EnvironmentObject var model: GameModel
    @State private var confirm: String? = nil
    var body: some View {
        let list = model.checkpointsStore.all()
        Text("Each checkpoint is saved as you reach it. Going back replaces your current progress.")
            .font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7))
        if list.isEmpty { Text("No checkpoints yet.").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.7)) }
        ForEach(list) { e in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: e.pinned ? "flag.fill" : "checkmark.seal.fill").foregroundStyle(Color.amber).font(.system(size: 18)).frame(width: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.title).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream)
                        Text(e.text).font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                        Text("\(e.depth) · \(e.date.formatted(date: .abbreviated, time: .shortened))").font(.avenir(11)).foregroundStyle(Color.cream.opacity(0.45))
                    }
                    Spacer(minLength: 4)
                    if confirm != e.id {
                        Button("Go back") { withAnimation { confirm = e.id } }.font(.avenir(13, "DemiBold")).foregroundStyle(Color.amber)
                    }
                }
                if confirm == e.id {
                    HStack {
                        Text("Lose everything since then?").font(.avenir(13, "DemiBold")).foregroundStyle(Color(red: 0.95, green: 0.6, blue: 0.5))
                        Spacer()
                        Button("Cancel") { confirm = nil }.font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.8))
                        Button("Go back") { model.restore(e) }.buttonStyle(PillStyle(prominent: true))
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
        }
    }
}
