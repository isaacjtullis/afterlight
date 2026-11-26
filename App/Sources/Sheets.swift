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
                        case .workbench: WorkbenchView()
                        case .storage: StorageView()
                        case .pack, .journal: EmptyView()
                        case .mission: MissionView()
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
        case .workbench: return "Workbench"
        case .storage: return "Workshop storage"
        case .pack: return "Belt and pack"
        case .journal: return "Journal"
        case .mission: return "Today’s job for Max"
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

struct WorkbenchView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0
    var body: some View {
        let g = model.game
        if g.knownRecipes.isEmpty {
            Text("Nothing to make yet. Recipes appear once Max has seen the problem they solve.").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.8))
        }
        ForEach(g.knownRecipes, id: \.id) { r in
            let parts = r.inputs.map { "\($0.id.name) \(min(g.available($0.id), $0.count))/\($0.count)" }.joined(separator: " · ")
            Row(title: r.name, detail: r.note + "\n" + parts) {
                VStack(spacing: 6) {
                    Button("Make") { g.craft(r.id); tick += 1 }
                        .buttonStyle(PillStyle(prominent: true)).disabled(!g.canCraft(r)).opacity(g.canCraft(r) ? 1 : 0.4)
                    Button(g.pinnedRecipe == r.id ? "Pinned" : "Pin") { g.pinnedRecipe = r.id; tick += 1 }
                        .font(.avenir(13)).foregroundStyle(Color.amber)
                }
            }
        }
        Text("At home, the bench pulls parts from storage as well as your pack.").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.55))
            .id(tick)
    }
}

struct StorageView: View {
    @EnvironmentObject var model: GameModel
    @State private var tick = 0
    var body: some View {
        let g = model.game
        Button("Put everything from the pack away") { g.depositAll(); tick += 1 }.buttonStyle(PillStyle(prominent: true))
        let items = ItemID.allCases.filter { g.storage.count($0) > 0 }
        if items.isEmpty { Text("Empty.").font(.avenir(15)).foregroundStyle(Color.cream.opacity(0.7)) }
        ForEach(items, id: \.self) { id in
            Row(title: "\(id.name) ×\(g.storage.count(id))", detail: id.blurb) {
                Button("Take") { g.take(id, id.maxStack); tick += 1 }.buttonStyle(PillStyle(prominent: false))
            }
        }
        .id(tick)
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
        }
    }
    var tint: Color {
        switch self {
        case .chargeCrystal: return .violet
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
                            Text("Chapter \(min(g.story.chapter, 4))").font(.system(size: 13, weight: .semibold, design: .serif)).tracking(2).foregroundStyle(ink.opacity(0.6))
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
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Text(convo.speaker).font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
                Text(convo.lines[min(model.lineIndex, convo.lines.count - 1)]).font(.avenir(18)).foregroundStyle(Color.cream)
                    .fixedSize(horizontal: false, vertical: true)
                if model.lineIndex >= convo.lines.count - 1 {
                    ForEach(convo.choices) { c in
                        Button { model.choose(c.id) } label: {
                            Text(c.label).font(.avenir(16, "DemiBold")).foregroundStyle(Color.cream)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).frame(minHeight: 46)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        }
                    }
                } else {
                    Text("Tap to continue").font(.avenir(13)).foregroundStyle(Color.cream.opacity(0.5))
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color(red: 0.1, green: 0.06, blue: 0.08).opacity(0.95)))
            .padding(12)
            .onTapGesture { model.advanceConversation() }
        }
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
