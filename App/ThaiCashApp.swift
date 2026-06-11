import SwiftUI
import Combine

@main
struct ThaiCashApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)   // dark-only — never show light
                .tint(Color.bahtGold)          // champagne accent app-wide (toggles, steppers, links, tabs)
                .task { await model.boot() }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let rates = RateService()
    let catalog = CatalogService()
    let boothRates = BoothRatesService()

    @Published var profile = Profile.load()
    @Published var amountTHB: Decimal = 40_000

    private var bag = Set<AnyCancellable>()

    init() {
        // Forward child ObservableObject changes up so `results` recomputes and views refresh.
        for child in [rates.objectWillChange, catalog.objectWillChange, boothRates.objectWillChange] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
    }

    func boot() async {
        await rates.loadAndRefreshIfNeeded()
        await catalog.refresh()
        await boothRates.refresh()
    }

    /// Grouped, ranked results for the current amount + live rate + profile.
    var results: [OutputGroup: [MethodResult]] {
        guard let rMid = rates.rate?.value else { return [:] }
        return Engine.compare(catalog: catalog.data, profile: profile,
                              targetThb: amountTHB, rMid: rMid,
                              liveBoothRate: boothRates.bestLiveRate)
    }
    var groupsInOrder: [OutputGroup] { OutputGroup.allCases.sorted { $0.sortIndex < $1.sortIndex } }
    func result(id: String) -> MethodResult? { results.values.flatMap { $0 }.first { $0.id == id } }

    /// One Home row per leg — except legs sharing a catalog `subgroup`, which
    /// collapse into a single rollup row represented by their cheapest member
    /// (e.g. the three ATM cards). Rows keep the group's cheapest-first order.
    enum HomeRow: Identifiable {
        case method(MethodResult)
        case rollup(key: String, label: String, best: MethodResult, memberIDs: [String])
        var id: String {
            switch self {
            case .method(let r):            return r.id
            case .rollup(let key, _, _, _): return "subgroup_\(key)"
            }
        }
    }

    func homeRows(for group: OutputGroup) -> [HomeRow] {
        let rs = results[group] ?? []
        let legByID = Dictionary(uniqueKeysWithValues: catalog.data.legs.map { ($0.id, $0) })
        var rows: [HomeRow] = []
        var seen = Set<String>()
        for r in rs {
            guard let sg = legByID[r.id]?.subgroup else { rows.append(.method(r)); continue }
            guard seen.insert(sg).inserted else { continue }   // later members fold into the first
            let members = rs.filter { legByID[$0.id]?.subgroup == sg }
            guard members.count > 1 else { rows.append(.method(r)); continue }
            let label = members.compactMap { legByID[$0.id]?.subgroupLabel }.first ?? "ATM withdrawal"
            rows.append(.rollup(key: sg, label: label, best: r, memberIDs: members.map(\.id)))
        }
        return rows
    }

    /// Every profile write funnels here and persists immediately.
    func update(_ mutate: (inout Profile) -> Void) {
        mutate(&profile)
        profile.save()
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        #if DEBUG
        if let screen = ProcessInfo.processInfo.environment["UITEST_SCREEN"] {
            screenshotRoot(screen)
        } else {
            mainTabs
        }
        #else
        mainTabs
        #endif
    }

    private var mainTabs: some View {
        TabView {
            HomeView()
                .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right") }
            ProfileView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
        }
    }

    #if DEBUG
    // Launch directly into a screen for headless screenshots, e.g.
    // SIMCTL_CHILD_UITEST_SCREEN=detail xcrun simctl launch booted com.thaicash.app
    @ViewBuilder private func screenshotRoot(_ screen: String) -> some View {
        switch screen {
        case "detail":  NavigationStack { MethodDetailView(legID: ProcessInfo.processInfo.environment["UITEST_LEG"] ?? "wise_card_atm") }
        case "atm":     NavigationStack { SubgroupDetailView(title: "ATM withdrawal", memberIDs: ["wise_card_atm", "atm_debit", "cc_advance"]) }
        case "setup":   ProfileView()
        default:        mainTabs
        }
    }
    #endif
}
