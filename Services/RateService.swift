import Foundation

struct Rate: Codable, Equatable {
    var value: Decimal           // THB per 1 unit of the base currency
    var asOf: Date               // when the rate is dated (not fetch time)
    var nextUpdate: Date?        // when to fetch again (provider-given or synthesized)
    var source: Source
    enum Source: String, Codable { case wiseLive, openErApi, frankfurter, manual }
}

enum Freshness: Equatable { case fresh, stale(days: Int), none }

struct RatePoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

protocol RateProvider { func fetch(base: String) async throws -> Rate }
enum RateError: Error { case badStatus, noRate }

/// PRIMARY — Wise's public live mid (the endpoint their own site uses):
/// keyless, updates continuously, timestamped to the minute. Unofficial, so
/// the daily providers below remain as fallbacks; a 15-minute synthesized
/// nextUpdate keeps launches re-fetching while the app is used.
struct WiseLiveProvider: RateProvider {
    func fetch(base: String) async throws -> Rate {
        let url = URL(string: "https://wise.com/rates/live?source=\(base)&target=THB")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RateError.badStatus }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        guard dto.value > 0 else { throw RateError.noRate }
        return Rate(value: Decimal(dto.value),
                    asOf: Date(timeIntervalSince1970: dto.time / 1000),
                    nextUpdate: Date().addingTimeInterval(15 * 60),
                    source: .wiseLive)
    }
    private struct DTO: Decodable { let value: Double; let time: TimeInterval }
}

/// FALLBACK 1 — keyless, updates daily incl. weekends, returns a next-update time.
struct OpenErApiProvider: RateProvider {
    func fetch(base: String) async throws -> Rate {
        let url = URL(string: "https://open.er-api.com/v6/latest/\(base)")!
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

/// FALLBACK 2 — ECB reference (keyless, self-hostable). Lags to last business day.
struct FrankfurterProvider: RateProvider {
    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    func fetch(base: String) async throws -> Rate {
        let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(base)&symbols=THB")! // .dev — .app 301s
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

/// THB mid rates per base currency (USD, EUR, AUD, …) — one cache, one 7-day
/// history series each. Corridors load lazily; everything stays offline-safe.
/// USDT aliases to USD: tether's fair THB value is the USD mid (±~0.1%), the
/// FX APIs don't quote stablecoins, and the alias shares the USD cache.
@MainActor
final class RateService: ObservableObject {
    @Published private(set) var rates: [String: Rate] = [:]
    @Published private(set) var histories: [String: [RatePoint]] = [:]

    private let providers: [RateProvider] =
        [WiseLiveProvider(), OpenErApiProvider(), FrankfurterProvider()] // live → daily → ECB

    private func fiat(_ base: String) -> String { base == "USDT" ? "USD" : base }

    func rate(for base: String) -> Rate? { rates[fiat(base)] }
    func history(for base: String) -> [RatePoint] { histories[fiat(base)] ?? [] }

    func freshness(for base: String) -> Freshness {
        guard let r = rates[fiat(base)] else { return .none }
        let days = Int(Date().timeIntervalSince(r.asOf) / 86_400)
        return days <= 1 ? .fresh : .stale(days: days)
    }

    /// True when the shown mid came from the live provider within the last hour —
    /// lets captions say "live" honestly and fall back to "today" once it ages.
    func isLive(for base: String) -> Bool {
        guard let r = rates[fiat(base)], r.source == .wiseLive else { return false }
        return Date().timeIntervalSince(r.asOf) < 3600
    }

    func loadAndRefreshIfNeeded(base: String) async {
        let base = fiat(base)
        if rates[base] == nil { rates[base] = readCache(base) }   // last-known instantly
        if shouldRefresh(base) { await refresh(base: base) }
        else if histories[base]?.isEmpty != false { await loadHistory(base: base) }
    }

    func refresh(base: String) async {
        let base = fiat(base)
        for provider in providers {
            if let r = try? await provider.fetch(base: base) {
                rates[base] = r; writeCache(r, base: base); break
            }
        }
        await loadHistory(base: base)   // all failed → keep cache, staleness surfaces
    }

    func loadHistory(base: String) async {
        let base = fiat(base)
        if let series = try? await fetchHistory(base: base), !series.isEmpty {
            histories[base] = series
        }
    }

    private func fetchHistory(base: String) async throws -> [RatePoint] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        df.locale = Locale(identifier: "en_US_POSIX")
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        let url = URL(string: "https://api.frankfurter.dev/v1/\(df.string(from: start))..\(df.string(from: end))?base=\(base)&symbols=THB")!
        let (data, resp) = try await URLSession.shared.data(from: url)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw RateError.badStatus }
        let dto = try JSONDecoder().decode(HistoryDTO.self, from: data)
        return dto.rates.compactMap { key, value -> RatePoint? in
            guard let d = df.date(from: key), let thb = value["THB"] else { return nil }
            return RatePoint(date: d, value: thb)
        }.sorted { $0.date < $1.date }
    }

    private struct HistoryDTO: Decodable { let rates: [String: [String: Double]] }

    func setManual(base: String, value: Decimal) { // first-launch-offline escape hatch
        let r = Rate(value: value, asOf: Date(), nextUpdate: nil, source: .manual)
        rates[base] = r; writeCache(r, base: base)
    }

    private func shouldRefresh(_ base: String) -> Bool {
        guard let r = rates[base] else { return true }
        if let next = r.nextUpdate { return Date() >= next }
        return Date().timeIntervalSince(r.asOf) > 12 * 3600
    }
    private func cacheKey(_ base: String) -> String { "thbfx.rate.\(base)" }
    private func readCache(_ base: String) -> Rate? {
        guard let d = UserDefaults.standard.data(forKey: cacheKey(base)) else { return nil }
        return try? JSONDecoder().decode(Rate.self, from: d)
    }
    private func writeCache(_ r: Rate, base: String) {
        if let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: cacheKey(base)) }
    }
}
