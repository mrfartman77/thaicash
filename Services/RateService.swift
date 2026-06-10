import Foundation

struct Rate: Codable, Equatable {
    var value: Decimal           // THB per 1 USD
    var asOf: Date               // when the rate is dated (not fetch time)
    var nextUpdate: Date?        // provider's next scheduled update (open.er-api)
    var source: Source
    enum Source: String, Codable { case openErApi, frankfurter, manual }
}

enum Freshness: Equatable { case fresh, stale(days: Int), none }

struct RatePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

protocol RateProvider { func fetch() async throws -> Rate }
enum RateError: Error { case badStatus, noRate }

/// PRIMARY — keyless, updates daily incl. weekends, returns a next-update time.
struct OpenErApiProvider: RateProvider {
    func fetch() async throws -> Rate {
        let url = URL(string: "https://open.er-api.com/v6/latest/USD")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RateError.badStatus }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        guard dto.result == "success", let thb = dto.rates["THB"] else { throw RateError.noRate }
        return Rate(value: Decimal(thb),
                    asOf: Date(timeIntervalSince1970: dto.time_last_update_unix),
                    nextUpdate: Date(timeIntervalSince1970: dto.time_next_update_unix),
                    source: .openErApi)
    }
    private struct DTO: Decodable {
        let result: String
        let time_last_update_unix: TimeInterval
        let time_next_update_unix: TimeInterval
        let rates: [String: Double]
    }
}

/// FALLBACK — ECB reference (keyless, self-hostable). Lags to last business day.
struct FrankfurterProvider: RateProvider {
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    func fetch() async throws -> Rate {
        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD&symbols=THB")! // .dev — .app 301s
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RateError.badStatus }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        guard let thb = dto.rates["THB"] else { throw RateError.noRate }
        return Rate(value: Decimal(thb),
                    asOf: Self.df.date(from: dto.date) ?? Date(),
                    nextUpdate: nil, source: .frankfurter)
    }
    private struct DTO: Decodable { let date: String; let rates: [String: Double] }
}

@MainActor
final class RateService: ObservableObject {
    @Published private(set) var rate: Rate?
    @Published private(set) var freshness: Freshness = .none
    @Published private(set) var history: [RatePoint] = []   // ~7-day USD→THB series for the chart

    private let providers: [RateProvider] = [OpenErApiProvider(), FrankfurterProvider()] // primary → fallback
    private let cacheKey = "thbfx.rate"

    func loadAndRefreshIfNeeded() async {
        rate = readCache(); recompute()         // show last-known instantly
        if shouldRefresh() { await refresh() } else { await loadHistory() }
    }

    func refresh() async {
        for provider in providers {
            if let r = try? await provider.fetch() { rate = r; writeCache(r); break }
        }
        recompute()                              // all failed → keep cache, surface staleness
        await loadHistory()
    }

    func loadHistory() async {
        if let series = try? await fetchHistory(), !series.isEmpty { history = series }
    }

    private func fetchHistory() async throws -> [RatePoint] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        df.locale = Locale(identifier: "en_US_POSIX")
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        let url = URL(string: "https://api.frankfurter.dev/v1/\(df.string(from: start))..\(df.string(from: end))?base=USD&symbols=THB")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RateError.badStatus }
        let dto = try JSONDecoder().decode(HistoryDTO.self, from: data)
        return dto.rates.compactMap { key, value -> RatePoint? in
            guard let d = df.date(from: key), let thb = value["THB"] else { return nil }
            return RatePoint(date: d, value: thb)
        }.sorted { $0.date < $1.date }
    }

    private struct HistoryDTO: Decodable { let rates: [String: [String: Double]] }

    func setManual(_ value: Decimal) {           // first-launch-offline escape hatch
        let r = Rate(value: value, asOf: Date(), nextUpdate: nil, source: .manual)
        rate = r; writeCache(r); recompute()
    }

    private func shouldRefresh() -> Bool {
        guard let r = rate else { return true }
        if let next = r.nextUpdate { return Date() >= next }
        return Date().timeIntervalSince(r.asOf) > 12 * 3600
    }
    private func recompute() {
        guard let r = rate else { freshness = .none; return }
        let days = Int(Date().timeIntervalSince(r.asOf) / 86_400)
        freshness = days <= 1 ? .fresh : .stale(days: days)
    }
    private func readCache() -> Rate? {
        guard let d = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Rate.self, from: d)
    }
    private func writeCache(_ r: Rate) {
        if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }
}
