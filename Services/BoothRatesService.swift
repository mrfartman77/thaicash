import Foundation

// MARK: - Feed model (mirrors thaicash-data/data/booth-rates.json)

struct BoothRateEntry: Codable, Identifiable {
    var id: String              // matches catalog.booths id
    var name: String
    var ok: Bool
    var usd100Buy: Decimal?     // THB per $1, USD-100 denomination buy rate
    var fetchedAt: String?
    var siteTime: String?
    var source: String?         // e.g. "via CashChanger" when a third party supplies the board
    var reason: String?         // why a booth is pending/stale
}

struct BoothRatesFeed: Codable {
    var version: Int
    var updated: String         // ISO8601 UTC
    var rates: [BoothRateEntry]
}

/// Live booth board rates, scraped by the thaicash-data GitHub Action every ~2h
/// and served as a static JSON. Same pattern as RateService: cache-first,
/// offline-safe, staleness surfaced — a broken feed degrades to the estimate,
/// never blocks the app.
@MainActor
final class BoothRatesService: ObservableObject {
    @Published private(set) var feed: BoothRatesFeed?

    static let maxSupportedVersion = 1
    static let remoteURL = URL(string: "https://raw.githubusercontent.com/mrfartman77/thaicash-data/main/data/booth-rates.json")!

    /// Feeds older than this don't drive the engine (boards reprice daily);
    /// the directory still displays them with an "updated …" age label.
    static let engineMaxAge: TimeInterval = 24 * 3600

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("thaicash_booth_rates.json")
    }

    init() { feed = Self.loadCached() }

    func refresh() async {
        guard let fresh = try? await fetch() else { return }          // offline → keep cache
        guard fresh.version <= Self.maxSupportedVersion else { return }
        feed = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            try? data.write(to: Self.cacheURL)
        }
    }

    // MARK: derived

    var updatedDate: Date? {
        guard let s = feed?.updated else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    var age: TimeInterval? {
        updatedDate.map { Date().timeIntervalSince($0) }
    }

    /// Human age: "just now", "3h ago", "2d ago".
    var ageText: String? {
        guard let age else { return nil }
        if age < 3600 { return "just now" }
        if age < 48 * 3600 { return "\(Int(age / 3600))h ago" }
        return "\(Int(age / 86_400))d ago"
    }

    var isFreshEnoughForEngine: Bool {
        guard let age else { return false }
        return age < Self.engineMaxAge
    }

    /// Live entries, best board first.
    var live: [BoothRateEntry] {
        (feed?.rates ?? [])
            .filter { $0.ok && $0.usd100Buy != nil }
            .sorted { ($0.usd100Buy ?? 0) > ($1.usd100Buy ?? 0) }
    }

    /// The measured best booth — only when fresh enough to trust.
    var bestUsable: BoothRateEntry? {
        isFreshEnoughForEngine ? live.first : nil
    }

    /// What the engine uses as the booth leg's default applied rate.
    var bestLiveRate: Decimal? { bestUsable?.usd100Buy }

    // MARK: cache

    private static func loadCached() -> BoothRatesFeed? {
        guard let d = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(BoothRatesFeed.self, from: d)
    }

    private func fetch() async throws -> BoothRatesFeed {
        let (bytes, resp) = try await URLSession.shared.data(from: Self.remoteURL)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(BoothRatesFeed.self, from: bytes)
    }
}
