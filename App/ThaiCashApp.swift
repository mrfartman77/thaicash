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
    let cryptoRates = CryptoRatesService()

    @Published var profile = Profile.load()
    @Published var amountTHB: Decimal = 40_000
    @Published var corridorID: String = "usd_thb"

    private var bag = Set<AnyCancellable>()

    init() {
        // Forward child ObservableObject changes up so `results` recomputes and views refresh.
        for child in [rates.objectWillChange, catalog.objectWillChange,
                      boothRates.objectWillChange, cryptoRates.objectWillChange] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }
    }

    // MARK: corridors

    var corridors: [Corridor] { catalog.data.corridors }
    var corridor: Corridor? { corridors.first { $0.id == corridorID } ?? corridors.first }

    func select(_ c: Corridor) {
        corridorID = c.id
        Task { await rates.loadAndRefreshIfNeeded(base: c.base) }
    }

    func boot() async {
        await catalog.refresh()
        await rates.loadAndRefreshIfNeeded(base: corridor?.base ?? "USD")
        await boothRates.refresh()
        await cryptoRates.refresh()
        for c in corridors where rates.rate(for: c.base) == nil {   // menu teaser mids
            await rates.loadAndRefreshIfNeeded(base: c.base)
        }
    }

    /// THB per 1 unit of the selected corridor's base currency.
    var rMid: Decimal? { corridor.flatMap { rates.rate(for: $0.base)?.value } }

    /// Crypto venue bids are THB-per-USDT. For non-USD corridors, convert to
    /// THB-per-base via the mid cross (1 base ≈ baseMid/usdMid USDT, USDT≈$1)
    /// so every corridor compares apples to apples. Internal so the detail
    /// screen can disclose the cross math.
    var liveRatesForCorridor: [String: Decimal] {
        let raw = cryptoRates.liveRates
        guard !raw.isEmpty, let c = corridor else { return [:] }
        if c.base == "USD" { return raw }
        guard let baseMid = rates.rate(for: c.base)?.value,
              let usdMid = rates.rate(for: "USD")?.value, usdMid > 0 else { return [:] }
        let cross = baseMid / usdMid
        return raw.mapValues { $0 * cross }
    }

    /// Grouped, ranked results for the current corridor + amount + profile.
    var results: [OutputGroup: [MethodResult]] {
        guard let c = corridor, let rMid else { return [:] }
        return Engine.compare(legs: c.legs, profile: profile,
                              targetThb: amountTHB, rMid: rMid,
                              liveBoothRate: boothRates.bestLiveRate(base: c.base),
                              liveRates: liveRatesForCorridor)
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
        let legByID = Dictionary(uniqueKeysWithValues: (corridor?.legs ?? []).map { ($0.id, $0) })
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
            NavigationStack { CorridorListView() }
                .tabItem { Label("Compare", systemImage: "arrow.left.arrow.right") }
            ProfileView()
                .tabItem { Label("Setup", systemImage: "gearshape") }
        }
    }

    #if DEBUG
    // Launch directly into a screen for headless screenshots, e.g.
    // SIMCTL_CHILD_UITEST_SCREEN=detail xcrun simctl launch booted com.thaicash.app
    @ViewBuilder private func screenshotRoot(_ screen: String) -> some View {
        Group {
            switch screen {
            case "detail":  NavigationStack { MethodDetailView(legID: ProcessInfo.processInfo.environment["UITEST_LEG"] ?? "wise_card_atm") }
            case "atm":     NavigationStack { SubgroupDetailView(title: "ATM withdrawal", subgroupKey: "atm_cash", memberIDs: ["schwab_debit_atm", "wise_card_atm", "revolut_card_atm", "atm_debit", "cc_advance"]) }
            case "home":    NavigationStack { corridorHome }
            case "setup":   ProfileView()
            default:        mainTabs
            }
        }
        .onAppear {
            if let cid = ProcessInfo.processInfo.environment["UITEST_CORRIDOR"] {
                model.corridorID = cid
            }
        }
    }

    @ViewBuilder private var corridorHome: some View {
        if let c = model.corridors.first(where: { $0.id == (ProcessInfo.processInfo.environment["UITEST_CORRIDOR"] ?? "usd_thb") }) {
            HomeView(corridor: c)
        } else {
            ContentUnavailableView("No corridor", systemImage: "questionmark")
        }
    }
    #endif
}

/// The corridor menu — one row per corridor, live mid as the teaser.
struct CorridorListView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SectionLabel(text: "Corridors")
                    .padding(.top, 8)
                Card {
                    ForEach(Array(model.corridors.enumerated()), id: \.element.id) { idx, c in
                        if idx > 0 { Divider().padding(.leading, 16) }
                        NavigationLink {
                            HomeView(corridor: c)
                        } label: {
                            corridorRow(c)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .background(Color.appBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    Image("Emblem")
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                    Text("ThaiCash").font(.headline)
                }
            }
        }
    }

    private func corridorRow(_ c: Corridor) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(c.label).font(.system(size: 16, weight: .medium))
                Text(freshnessCaption(c))
                    .font(.caption)
                    .foregroundStyle(captionColor(c))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(midText(c)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Text("THB / \(c.base)").font(.system(size: 9, weight: .semibold)).kerning(0.8)
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private func midText(_ c: Corridor) -> String {
        model.rates.rate(for: c.base).map { Fmt.rate($0.value) } ?? "—"
    }

    /// Honest freshness: the mid is a DAILY rate — never claim "now".
    private func freshnessCaption(_ c: Corridor) -> String {
        switch model.rates.freshness(for: c.base) {
        case .fresh:            return "Mid-market · today"
        case .stale(let days):  return "Mid-market · \(days)d old"
        case .none:             return "Mid-market · no rate yet"
        }
    }
    private func captionColor(_ c: Corridor) -> Color {
        if case .stale = model.rates.freshness(for: c.base) { return .warnAmber }
        return Color.secondary
    }
}
