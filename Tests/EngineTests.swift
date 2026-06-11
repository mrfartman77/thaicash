import XCTest
@testable import ThaiCash

/// Engine.evaluate / Engine.compare — pure Decimal math against hand-computed
/// expectations. Legs are built inline so each test pins one rule; the bundled
/// seed gets its own suite in CatalogSeedTests.
final class EngineTests: XCTestCase {

    // MARK: - Helpers

    /// Exact decimal from a string — float literals round-trip through Double
    /// and would poison hand-computed expectations.
    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    private func assertEqual(_ actual: Decimal, _ expected: Decimal,
                             accuracy: Decimal = Decimal(string: "0.000000001")!,
                             _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(abs(actual - expected) <= accuracy,
                      "\(actual) ≠ \(expected) ±\(accuracy) \(message)", file: file, line: line)
    }

    private func fee(_ kind: FeeKind, _ value: Decimal,
                     minUsd: Decimal? = nil, maxUsd: Decimal? = nil,
                     per: FeeScope? = nil, feeOn: FeeBasis? = nil,
                     when: FeeCondition? = nil, source: FeeOrigin? = nil,
                     profileKey: String? = nil, interestBase: Bool? = nil,
                     label: String = "Fee") -> FeeComponent {
        FeeComponent(kind: kind, value: value, minUsd: minUsd, maxUsd: maxUsd,
                     per: per, feeOn: feeOn, when: when, source: source,
                     profileKey: profileKey, interestBase: interestBase, label: label)
    }

    private func leg(id: String = "test", group: OutputGroup = .cashInHand,
                     rateSource: RateSource = .midMarket,
                     fxMarginPct: Decimal? = nil, typicalBoothMargin: Decimal? = nil,
                     amountCapThb: Decimal? = nil, freeAtmAmountThb: Decimal? = nil,
                     freeAtmWithdrawals: Int? = nil,
                     acceptance: String? = nil, acceptanceNote: String? = nil,
                     taxFlag: String? = nil, volatility: String? = nil,
                     interest: InterestModel? = nil,
                     fees: [FeeComponent] = [], speed: String? = nil) -> Leg {
        Leg(id: id, label: id, group: group, rateSource: rateSource,
            fxMarginPct: fxMarginPct, typicalBoothMargin: typicalBoothMargin,
            amountCapThb: amountCapThb, freeAtmAmountThb: freeAtmAmountThb,
            freeAtmWithdrawals: freeAtmWithdrawals,
            acceptance: acceptance, acceptanceNote: acceptanceNote,
            taxFlag: taxFlag, volatility: volatility,
            interest: interest, fees: fees, speed: speed)
    }

    // MARK: - Rate sources

    func testMidMarketNoFees() {
        let r = Engine.evaluate(leg: leg(), profile: Profile(), targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_000)
        assertEqual(r.effectiveRate, 35)
        assertEqual(r.costThb, 0)
        assertEqual(r.costVsMidPct, 0)
        XCTAssertEqual(r.withdrawals, 1)
        XCTAssertEqual(r.netThb, 35_000)
        XCTAssertEqual(r.lines.count, 1)
        XCTAssertEqual(r.lines[0].label, "Exchange rate · at market")
        XCTAssertTrue(r.lines[0].isZero)
    }

    func testMidMarketMargin() {
        let l = leg(rateSource: .midMarketMargin, fxMarginPct: d("0.003"))
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 35_000, rMid: 35)
        // rEff = 35 × 0.997 = 34.895; the rate margin is the entire cost
        assertEqual(r.effectiveRate, d("34.895"))
        assertEqual(r.usdCost, 35_000 / d("34.895"), accuracy: d("0.000001"))
        assertEqual(r.costVsMidPct, d("0.3"), accuracy: d("0.000001"))
        XCTAssertEqual(r.lines[0].label, "Exchange-rate markup")
        // costThb ≡ usdCost·rMid − target, and the itemized lines sum to it
        assertEqual(r.costThb, r.usdCost * 35 - 35_000, accuracy: d("0.000001"))
        assertEqual(r.lines.map(\.thb).reduce(0, +), r.costThb, accuracy: d("0.000001"))
    }

    func testMidMarketMarginNilDefaultsToZero() {
        let l = leg(rateSource: .midMarketMargin)
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, 35)
    }

    func testQuotedPrecedence() {
        let l = leg(rateSource: .quoted, typicalBoothMargin: d("0.005"))
        var p = Profile()

        // 1. the user's typed quote beats everything
        p.boothQuote = d("34.5")
        var r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35, liveBoothRate: d("34.8"))
        assertEqual(r.effectiveRate, d("34.5"))

        // 2. today's scraped board beats the estimate
        p.boothQuote = nil
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35, liveBoothRate: d("34.8"))
        assertEqual(r.effectiveRate, d("34.8"))

        // 3. estimate from the leg's typical margin: 35 × 0.995
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, d("34.825"))

        // 4. no leg margin → the profile's planning default (1% here): 35 × 0.99
        p.boothMarginOffMid = d("0.01")
        r = Engine.evaluate(leg: leg(rateSource: .quoted), profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, d("34.65"))
    }

    // MARK: - pct_usd

    func testPctUsdMinFloor() {
        let l = leg(fees: [fee(.pctUsd, d("0.05"), minUsd: 10)])
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 3_500, rMid: 35)
        // 5% of $100 = $5, floored to the $10 minimum
        assertEqual(r.usdCost, 110)
        assertEqual(r.effectiveRate, 3_500 / 110)
        XCTAssertEqual(r.lines.count, 2)
        assertEqual(r.lines[1].thb, 350)   // the $10 fee valued at mid
    }

    func testPctUsdMaxCap() {
        let l = leg(fees: [fee(.pctUsd, d("0.05"), maxUsd: 10)])
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 35_000, rMid: 35)
        // 5% of $1000 = $50, capped at $10
        assertEqual(r.usdCost, 1_010)
    }

    func testZeroPctFeeProducesNoLineAndSkipsTheMinimum() {
        let l = leg(fees: [fee(.pctUsd, 0, minUsd: 10)])
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_000)
        XCTAssertEqual(r.lines.count, 1)   // just the rate line
    }

    func testPctUsdOverAllowanceBasis() {
        let l = leg(freeAtmAmountThb: 8_000,
                    fees: [fee(.pctUsd, d("0.02"), feeOn: .overAllowance,
                               when: FeeCondition(overFreeAtm: true))])
        // Above the allowance: fee on ($1000 − $200) = $800 → $16
        var r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 40_000, rMid: 40)
        assertEqual(r.usdCost, 1_016)
        // At the boundary the component is inactive (8000 > 8000 is false)
        r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 8_000, rMid: 40)
        assertEqual(r.usdCost, 200)
    }

    // MARK: - flat fees

    func testFlatFeesPerWithdrawalMultiply() {
        let l = leg(amountCapThb: 20_000,
                    fees: [fee(.flatUsd, d("1.95"), per: .withdrawal, label: "Card fixed fee"),
                           fee(.flatThb, 220, per: .withdrawal, label: "Thai ATM fee")])
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 60_000, rMid: 30)
        XCTAssertEqual(r.withdrawals, 3)
        // $2000 base + 3 × $1.95 + 3 × ฿220 valued at the effective rate (660/30 = $22)
        assertEqual(r.usdCost, d("2027.85"))
        XCTAssertEqual(r.lines.last?.label, "Thai ATM fee ×3")
        assertEqual(r.lines.map(\.thb).reduce(0, +), r.costThb, accuracy: d("0.000001"))
    }

    func testFlatFeesPerTransactionDoNotMultiply() {
        let l = leg(amountCapThb: 20_000,
                    fees: [fee(.flatUsd, d("0.8")),
                           fee(.flatThb, 20, label: "Withdrawal fee")])
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 60_000, rMid: 30)
        XCTAssertEqual(r.withdrawals, 3)
        assertEqual(r.usdCost, 2_000 + d("0.8") + 20 / Decimal(30), accuracy: d("0.000001"))
        XCTAssertEqual(r.lines.last?.label, "Withdrawal fee")   // no ×3 suffix
    }

    // MARK: - rate_margin folding + when-clauses

    func testRateMarginDccConditional() {
        let l = leg(fees: [fee(.rateMargin, d("0.05"),
                               when: FeeCondition(dccAccepted: true), label: "DCC markup")])
        var p = Profile()

        var r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, 35)      // DCC declined: clean mid
        XCTAssertTrue(r.warnings.isEmpty)

        p.toggles.dccAccepted = true
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, d("33.25"))   // 35 × 0.95
        assertEqual(r.usdCost, 35_000 / d("33.25"), accuracy: d("0.000001"))
        XCTAssertTrue(r.warnings.contains { $0.contains("DCC") })
    }

    func testRateMarginWeekendConditional() {
        let l = leg(fees: [fee(.rateMargin, d("0.01"), when: FeeCondition(isWeekend: true))])
        var p = Profile()
        var r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, 35)
        p.toggles.isWeekend = true
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, d("34.65"))   // 35 × 0.99
    }

    func testRateMarginsCompoundMultiplicatively() {
        let l = leg(fees: [fee(.rateMargin, d("0.05")), fee(.rateMargin, d("0.01"))])
        let r = Engine.evaluate(leg: l, profile: Profile(), targetThb: 35_000, rMid: 35)
        assertEqual(r.effectiveRate, 35 * d("0.95") * d("0.99"))
    }

    func testFundingSourceConditionalFees() {
        let l = leg(group: .thbInBank,
                    fees: [fee(.pctUsd, d("0.01"), when: FeeCondition(fundingSource: .debitCard)),
                           fee(.pctUsd, d("0.03"), when: FeeCondition(fundingSource: .creditCard))])
        var p = Profile()   // defaults to .bankACH
        var r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_000)
        p.fundingSource = .debitCard
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_010)
        p.fundingSource = .creditCard
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_030)
    }

    func testUserSourcedFeeUsesProfileOverride() {
        let l = leg(fees: [fee(.pctUsd, d("0.03"), source: .user, profileKey: "bank_ftf")])
        var p = Profile()
        var r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_030)              // catalog default 3%
        p.overrides["bank_ftf"] = d("0.01")
        r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_010)              // the user's own 1%
    }

    // MARK: - cash-advance interest

    func testCashAdvanceInterestAccruesOnFees() {
        // 36.5% APR over 30 days = exactly 3%
        let l = leg(interest: InterestModel(apr: d("0.365"), accruesOnFees: true),
                    fees: [fee(.pctUsd, d("0.05"), minUsd: 10, interestBase: true,
                               label: "Cash-advance fee")])
        var p = Profile(); p.daysToPayoff = 30
        let r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        // base $1000 + $50 fee, interest on $1050 → $31.50
        assertEqual(r.usdCost, d("1081.5"))
        XCTAssertEqual(r.lines.last?.label, "Interest ~30d")
        assertEqual(r.lines.last!.thb, d("31.5") * 35)
    }

    func testCashAdvanceInterestOnPrincipalOnly() {
        let l = leg(interest: InterestModel(apr: d("0.365"), accruesOnFees: false),
                    fees: [fee(.pctUsd, d("0.05"), interestBase: true)])
        var p = Profile(); p.daysToPayoff = 30
        let r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_080)   // interest on the $1000 principal only → $30
    }

    func testFeeWithoutInterestBaseFlagStaysOutOfInterestBase() {
        let l = leg(interest: InterestModel(apr: d("0.365"), accruesOnFees: true),
                    fees: [fee(.pctUsd, d("0.05"))])     // no interestBase flag
        var p = Profile(); p.daysToPayoff = 30
        let r = Engine.evaluate(leg: l, profile: p, targetThb: 35_000, rMid: 35)
        assertEqual(r.usdCost, 1_080)
    }

    // MARK: - withdrawals & free-ATM allowance

    func testWithdrawalCountFromCap() {
        let capped = leg(amountCapThb: 20_000)
        let p = Profile()
        XCTAssertEqual(Engine.evaluate(leg: capped, profile: p, targetThb: 20_000, rMid: 35).withdrawals, 1)
        XCTAssertEqual(Engine.evaluate(leg: capped, profile: p, targetThb: 20_001, rMid: 35).withdrawals, 2)
        XCTAssertEqual(Engine.evaluate(leg: capped, profile: p, targetThb: 40_000, rMid: 35).withdrawals, 2)
        XCTAssertEqual(Engine.evaluate(leg: capped, profile: p, targetThb: 60_000, rMid: 35).withdrawals, 3)
        XCTAssertEqual(Engine.evaluate(leg: leg(), profile: p, targetThb: 1_000_000, rMid: 35).withdrawals, 1)
    }

    func testOverFreeAtmByWithdrawalCount() {
        let l = leg(amountCapThb: 20_000, freeAtmWithdrawals: 2,
                    fees: [fee(.flatUsd, d("1.95"), per: .withdrawal,
                               when: FeeCondition(overFreeAtm: true))])
        let p = Profile()
        // 2 pulls → within the free count, fee inactive
        var r = Engine.evaluate(leg: l, profile: p, targetThb: 40_000, rMid: 25)
        assertEqual(r.usdCost, 1_600)
        // 3 pulls → over, $1.95 × 3
        r = Engine.evaluate(leg: l, profile: p, targetThb: 50_000, rMid: 25)
        XCTAssertEqual(r.withdrawals, 3)
        assertEqual(r.usdCost, 2_000 + d("5.85"))
    }

    // MARK: - compare: grouping, sorting, isBest, speed

    func testCompareGroupsSortsAndMarksBest() {
        let catalog = Catalog(schemaVersion: 4, catalogUpdated: "2026-01-01",
                              atmHostFeeThb: 220, atmCapThb: 20_000,
                              legs: [leg(id: "pricey", rateSource: .midMarketMargin, fxMarginPct: d("0.01")),
                                     leg(id: "free"),
                                     leg(id: "mid", rateSource: .midMarketMargin, fxMarginPct: d("0.003")),
                                     leg(id: "bank", group: .thbInBank, speed: "~4–6d")])
        let out = Engine.compare(catalog: catalog, profile: Profile(), targetThb: 35_000, rMid: 35)

        let cash = out[.cashInHand]!
        XCTAssertEqual(cash.map(\.id), ["free", "mid", "pricey"])   // cheapest (highest rate) first
        XCTAssertEqual(cash.map(\.isBest), [true, false, false])

        let bank = out[.thbInBank]!
        XCTAssertEqual(bank.count, 1)
        XCTAssertTrue(bank[0].isBest)
        XCTAssertEqual(bank[0].speed, "~4–6d")                      // speed survives compare
        XCTAssertNil(out[.cryptoThb])
    }

    func testSpeedPassthrough() {
        let p = Profile()
        XCTAssertEqual(Engine.evaluate(leg: leg(speed: "~Instant"), profile: p, targetThb: 1_000, rMid: 35).speed, "~Instant")
        XCTAssertNil(Engine.evaluate(leg: leg(), profile: p, targetThb: 1_000, rMid: 35).speed)
    }

    // MARK: - guards & warnings

    func testZeroRateGuard() {
        var p = Profile(); p.boothQuote = 0
        let r = Engine.evaluate(leg: leg(rateSource: .quoted), profile: p, targetThb: 35_000, rMid: 35)
        XCTAssertEqual(r.warnings, ["Rate unavailable"])
        assertEqual(r.usdCost, 0)
        assertEqual(r.effectiveRate, 0)
        XCTAssertTrue(r.lines.isEmpty)
    }

    func testWarnings() {
        var p180 = Profile(); p180.daysInThailand = 180
        let taxed = leg(group: .thbInBank, taxFlag: "thai_remittance_180d")
        XCTAssertTrue(Engine.evaluate(leg: taxed, profile: p180, targetThb: 1_000, rMid: 35)
            .warnings.contains { $0.contains("180+") })
        XCTAssertTrue(Engine.evaluate(leg: taxed, profile: Profile(), targetThb: 1_000, rMid: 35)
            .warnings.isEmpty)

        let limited = leg(acceptance: "limited", acceptanceNote: "Amex often rejected")
        XCTAssertTrue(Engine.evaluate(leg: limited, profile: Profile(), targetThb: 1_000, rMid: 35)
            .warnings.contains("Amex often rejected"))

        let drifty = leg(volatility: "high")
        XCTAssertTrue(Engine.evaluate(leg: drifty, profile: Profile(), targetThb: 1_000, rMid: 35)
            .warnings.contains { $0.contains("verify") })
    }
}
