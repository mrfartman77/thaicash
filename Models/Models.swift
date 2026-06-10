import Foundation

// MARK: - Enums

enum OutputGroup: String, Codable, CaseIterable, Hashable {
    case cashInHand = "cash_in_hand"
    case thbInBank  = "thb_in_bank"

    var title: String {
        switch self {
        case .cashInHand: return "Get cash"
        case .thbInBank:  return "To Thai bank"
        }
    }
    /// Display order on the home screen — cash first (the hero, and free).
    var sortIndex: Int {
        switch self {
        case .cashInHand: return 0
        case .thbInBank:  return 1
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
}

/// A curated, well-known exchange chain. Lives in the remote catalog so the
/// directory updates without an app release. Taps deep-link into Apple Maps —
/// Maps does "near me"/directions with ITS location permission, so the app
/// itself never has to ask for location.
struct BoothInfo: Codable, Identifiable {
    var id: String
    var name: String
    var quality: String        // best | good | avoid
    var areas: String          // human description of where to find it
    var note: String?
    var mapsQuery: String?     // address-anchored search; nil = no map link
    var mapsPlaceId: String?   // exact Apple Maps place — beats any search query

    var mapsURL: URL? {
        if let pid = mapsPlaceId {
            return URL(string: "https://maps.apple.com/place?place-id=\(pid)")
        }
        guard let q = mapsQuery?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(q)")
    }
}

struct Catalog: Codable {
    var schemaVersion: Int
    var catalogUpdated: String         // "yyyy-MM-dd" — lexicographic compare works
    var atmHostFeeThb: Decimal
    var atmCapThb: Decimal
    var legs: [Leg]
    var booths: [BoothInfo]?           // optional: old cached catalogs still decode
}

// MARK: - Profile (local, persisted on every change)

struct Toggles: Codable, Equatable {
    var dccAccepted = false
    var isWeekend   = false
    var overFxLimit = false
}

struct Profile: Codable, Equatable {
    var overrides: [String: Decimal] = [:]   // profileKey -> user value (else catalog default)
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
    var isBest: Bool = false
}
