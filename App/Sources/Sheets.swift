import SwiftUI
import AfterlightCore

/// Bottom cards for the workbench, storage, pack, journal and daily mission.
struct SheetHost: View {
    @EnvironmentObject var model: GameModel
    let sheet: Sheet

    var body: some View {
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
                        case .pack: PackView()
                        case .journal: JournalView()
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

struct PackView: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        let g = model.game
        Text("Belt").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
        ForEach(g.inv.belt, id: \.self) { t in Row(title: t.name, detail: toolNote(t)) { EmptyView() } }
        Text("Pack · \(Inventory.capacity - g.inv.freeSlots) of \(Inventory.capacity) slots").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
        ForEach(Array(g.inv.slots.enumerated()), id: \.offset) { _, s in
            if let s { Row(title: s.count > 1 ? "\(s.id.name) ×\(s.count)" : s.id.name, detail: s.id.blurb + (s.id.bulky ? " Bulky: takes a whole slot." : "")) { EmptyView() } }
        }
        if let pin = g.pinnedRecipe, let r = Recipes.all.first(where: { $0.id == pin }) {
            Text("Pinned: \(r.name)").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
            Text(r.inputs.map { "\($0.id.name) \(min(g.available($0.id), $0.count))/\($0.count)" }.joined(separator: " · ")).font(.avenir(14)).foregroundStyle(Color.cream.opacity(0.8))
        }
    }
    func toolNote(_ t: Tool) -> String {
        switch t {
        case .shovel: return "Cuts loose earth sideways and down. Good for beds, too."
        case .flashlight: return "One soft beam. Shows what’s ahead."
        case .shortPick: return "Hold ▲ and DIG to open soft seams overhead. ▲ at a ledge cuts footholds."
        }
    }
}

struct JournalView: View {
    @EnvironmentObject var model: GameModel
    var body: some View {
        let g = model.game
        Text("Chapter \(min(g.story.chapter, 4))").font(.avenir(14, "DemiBold")).foregroundStyle(Color.amber)
        ForEach(g.story.quests.reversed()) { q in
            VStack(alignment: .leading, spacing: 6) {
                Text((q.side ? "Side · " : "") + q.title).font(.avenir(17, "DemiBold")).foregroundStyle(q.done ? Color.cream.opacity(0.5) : Color.cream)
                ForEach(q.steps, id: \.id) { s in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: s.done ? "checkmark.circle.fill" : "circle").foregroundStyle(s.done ? Color.amber : Color.cream.opacity(0.5))
                        Text(s.text).font(.avenir(15)).foregroundStyle(Color.cream.opacity(s.done ? 0.55 : 0.9))
                    }
                }
                if let o = q.outcome { Text(o).font(.avenir(14)).italic().foregroundStyle(Color.amber.opacity(0.9)) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.05)))
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
