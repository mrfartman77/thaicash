import Foundation

// MARK: - Enums

enum OutputGroup: String, Codable, CaseIterable, Hashable {
    case cashInHand = "cash_in_hand"
    case thbInBank  = "thb_in_bank"
    case cryptoThb  = "crypto_thb_bank"

    var title: String {
        switch self {
        case .cashInHand: return "Get cash"
        case .thbInBank:  return "Bank → Thai bank"
        case .cryptoThb:  return "Crypto → Thai bank"
        }
    }
    /// Display order on the home screen — cash first (the hero, and free),
    /// then crypto (near-instant beats the multi-day bank rails).
    var sortIndex: Int {
        switch self {
        case .cashInHand: return 0
        case .cryptoThb:  return 1
        case .thbInBank:  return 2
        }
    }
}

enum RateSource: String, Codable {
    case midMarket       = "mid_market"
    case quoted          = "quoted"
    case midMarketMargin = "mid_market_margin"
}

enum FeeKind: String, Codable {
    case rateMargin = "rate_margin"
    case pctUsd     = "pct_usd"
    case flatUsd    = "flat_usd"
    case flatThb    = "flat_thb"
}

enum FeeScope: String, Codable { case transaction, withdrawal }

/// What a percentage fee is applied to.
enum FeeBasis: String, Codable {
    case base                              // pct of the USD value of the target
    case send                              // pct of total send (approximated as base in v1)
    case overAllowance = "over_allowance"  // pct of the amount above a free allowance
}

enum FeeOrigin: String, Codable { case stored, user }

enum FundingSource: String, Codable, CaseIterable {
    case bankACH    = "bank_ach"
    case debitCard  = "debit_card"
    case creditCard = "credit_card"

    var label: String {
        switch self {
        case .bankACH:    return "Bank / ACH"
        case .debitCard:  return "Debit"
        case .creditCard: return "Credit"
        }
    }
}

// MARK: - Catalog (runtime / seed schema — flat legs)

/// A condition under which a fee component applies. nil fields = "don't care".
struct FeeCondition: Codable {
    var dccAccepted: Bool?
    var fundingSource: FundingSource?
    var isWeekend: Bool?
    var overFxLimit: Bool?
    var overFreeAtm: Bool?
}

struct FeeComponent: Codable {
    var kind: FeeKind
    var value: Decimal
    var minUsd: Decimal?
    var maxUsd: Decimal?
    var per: FeeScope?            // default .transaction
    var feeOn: FeeBasis?          // default .base
    var when: FeeCondition?       // nil = always applies
    var source: FeeOrigin?        // default .stored
    var profileKey: String?       // for source == .user, the Profile override key
    var interestBase: Bool?       // include this fee in the cash-advance interest base
    var label: String
}

struct InterestModel: Codable {
    var apr: Decimal
    var accruesOnFees: Bool
}

/// One comparison option. Methods, providers, modes and payout legs from the
/// design doc are flattened into a single uniform list here for a clean,
/// directly-decodable runtime schema. `group` is per-leg, so a provider like
/// Wise appears once per product (card_atm = cash, transfer = bank).
struct Leg: Codable, Identifiable {
    var id: String
    var label: String
    var group: OutputGroup
    var subgroup: String?              // legs sharing a key collapse into one Home row…
    var subgroupLabel: String?         // …shown under this label (e.g. "ATM withdrawal")
    var subgroupNote: String?          // footer line on the rollup screen (remote-updatable)
    var rateSource: RateSource
    var fxMarginPct: Decimal?          // for .midMarketMargin
    var typicalBoothMargin: Decimal?   // planning fallback for .quoted
    var amountCapThb: Decimal?         // per-withdrawal dispense cap
    var freeAtmAmountThb: Decimal?     // monthly fee-free allowance (amount)
    var freeAtmWithdrawals: Int?       // monthly fee-free allowance (count)
    var acceptance: String?            // wide | limited | poor
    var acceptanceNote: String?
    var taxFlag: String?               // e.g. "thai_remittance_180d"
    var volatility: String?            // low | medium | high (drives "verify" warning)
    var interest: InterestModel?       // cash advance only
    var fees: [FeeComponent]
    var notes: String?
    var linkURL: String?               // official provider site — "Get started" row
    var speed: String?                 // delivery time ("~4–6 days", "minutes") — nil = in-person/instant
}

/// Apple Maps deep links — Maps does "near me"/directions with ITS location
/// permission, so the app itself never has to ask for location.
enum MapsLink {
    /// `near` ("lat,lng") anchors a category search (e.g. "Krungsri ATM") via
    /// sll= — without it Maps searches near the USER, which abroad returns
    /// hometown garbage instead of Thailand.
    static func url(placeId: String?, query: String?, near: String? = nil) -> URL? {
        if let pid = placeId {
            return URL(string: "https://maps.apple.com/place?place-id=\(pid)")
        }
        guard let q = query?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let anchor = near.map { "&sll=\($0)&z=13" } ?? ""
        return URL(string: "https://maps.apple.com/?q=\(q)\(anchor)")
    }
}

/// A curated, well-known exchange chain. Lives in the remote catalog so the
/// directory updates without an app release.
struct BoothInfo: Codable, Identifiable {
    var id: String
    var name: String
    var quality: String        // best | good | avoid
    var areas: String          // human description of where to find it
    var note: String?
    var mapsQuery: String?     // address-anchored search; nil = no map link
    var mapsPlaceId: String?   // exact Apple Maps place — beats any search query

    var mapsURL: URL? { MapsLink.url(placeId: mapsPlaceId, query: mapsQuery) }
}

/// One operator in a subgroup's locator (e.g. ATM operators): who, where,
/// what the machine charges. Data only — the fee figure does the ranking.
struct DirectoryEntry: Codable, Identifiable {
    var id: String
    var name: String
    var areas: String
    var note: String?
    var feeThb: Decimal?       // the machine's per-withdrawal surcharge
    var mapsQuery: String?
    var mapsPlaceId: String?
    var mapsNear: String?      // "lat,lng" search anchor for category queries

    var mapsURL: URL? { MapsLink.url(placeId: mapsPlaceId, query: mapsQuery, near: mapsNear) }
}

/// A "find one" section for a rollup screen, keyed by `Leg.subgroup`.
struct SubgroupDirectory: Codable {
    var title: String
    var footer: String?
    var entries: [DirectoryEntry]
}

/// One conversion corridor (USD→THB, EUR→THB, …): its own method legs, booth
/// directory and locator sections. The Home experience is corridor-scoped;
/// the corridor menu sits one level up.
struct Corridor: Codable, Identifiable, Hashable {
    static func == (a: Corridor, b: Corridor) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var id: String                     // "usd_thb"
    var base: String                   // ISO code of the home currency ("USD")
    var baseSymbol: String             // "$", "€", "A$"
    var label: String                  // "USD → THB"
    var basePresets: [Decimal]?        // amount-card presets in base units (nil = generic 100/300/500/1k)
    var legs: [Leg]
    var booths: [BoothInfo]?
    var directories: [String: SubgroupDirectory]?
}

struct Catalog: Codable {
    var schemaVersion: Int
    var catalogUpdated: String         // ISO date or datetime (UTC) — lexicographic compare works
    var corridors: [Corridor]
}

// MARK: - Profile (local, persisted on every change)

struct Toggles: Codable, Equatable {
    var dccAccepted = false
    var isWeekend   = false
    var overFxLimit = false
}

struct Profile: Codable, Equatable {
    var overrides: [String: Decimal] = [:]   // profileKey -> user value (else catalog default)
    var homeBase: String? = nil              // "USD"/"EUR"/"AUD" — drives Setup defaults/symbol
    var boothQuote: Decimal? = nil           // the rate the booth quoted (overrides typical margin)
    var boothMarginOffMid: Decimal = 0.005   // planning default when no quote entered
    var fundingSource: FundingSource = .bankACH
    var daysInThailand: Int = 90             // ≥180 → tax flag
    var daysToPayoff: Int = 30               // cash-advance interest horizon
    var toggles = Toggles()

    func value(for key: String) -> Decimal? { overrides[key] }

    private static let storeKey = "thbfx.profile"

    static func load() -> Profile {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let p = try? JSONDecoder().decode(Profile.self, from: data) else { return Profile() }
        return p
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }
}

// MARK: - Result (engine output)

struct CostLine: Identifiable {
    let id = UUID()
    var label: String
    var thb: Decimal
    var isZero: Bool { thb == 0 }
}

struct MethodResult: Identifiable {
    var id: String              // == leg id
    var label: String
    var group: OutputGroup
    var netThb: Decimal         // what you walk away with (== target in target mode)
    var usdCost: Decimal        // all-in USD it costs
    var effectiveRate: Decimal  // THB per $1, all-in
    var costThb: Decimal        // total cost vs a costless mid-market conversion
    var costVsMidPct: Decimal   // the "+X% vs rate" headline
    var withdrawals: Int
    var lines: [CostLine]       // itemized "where it goes", sums to costThb
    var warnings: [String]
    var speed: String?          // delivery time, surfaced on rows + detail
    var isBest: Bool = false
}
