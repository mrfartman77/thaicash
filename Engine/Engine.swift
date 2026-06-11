import Foundation

/// Pure, dependency-free comparison engine. Works in THB-target mode:
/// given the baht you want, compute the all-in USD cost per method.
enum Engine {

    static func compare(catalog: Catalog,
                        profile: Profile,
                        targetThb: Decimal,
                        rMid: Decimal,
                        liveBoothRate: Decimal? = nil,
                        liveRates: [String: Decimal] = [:]) -> [OutputGroup: [MethodResult]] {

        var byGroup: [OutputGroup: [MethodResult]] = [:]
        for leg in catalog.legs {
            let result = evaluate(leg: leg, profile: profile, targetThb: targetThb, rMid: rMid,
                                  liveBoothRate: liveBoothRate, liveRates: liveRates)
            byGroup[leg.group, default: []].append(result)
        }

        var out: [OutputGroup: [MethodResult]] = [:]
        for (group, results) in byGroup {
            var sorted = results.sorted { $0.effectiveRate > $1.effectiveRate }   // higher rate = cheaper
            if !sorted.isEmpty { sorted[0].isBest = true }
            out[group] = sorted
        }
        return out
    }

    static func evaluate(leg: Leg,
                         profile: Profile,
                         targetThb: Decimal,
                         rMid: Decimal,
                         liveBoothRate: Decimal? = nil,
                         liveRates: [String: Decimal] = [:]) -> MethodResult {

        // ---- number of withdrawals (cap-driven) ----
        let withdrawals: Int = {
            guard let cap = leg.amountCapThb, cap > 0 else { return 1 }
            let ratio = (targetThb as NSDecimalNumber).doubleValue / (cap as NSDecimalNumber).doubleValue
            return max(1, Int(ratio.rounded(.up)))
        }()

        // ---- runtime condition context ----
        let overFreeAtm: Bool = {
            let overAmount = leg.freeAtmAmountThb.map { targetThb > $0 } ?? false
            let overCount  = leg.freeAtmWithdrawals.map { withdrawals > $0 } ?? false
            return overAmount || overCount
        }()

        func active(_ c: FeeComponent) -> Bool {
            guard let w = c.when else { return true }
            if let v = w.dccAccepted,   v != profile.toggles.dccAccepted { return false }
            if let v = w.isWeekend,     v != profile.toggles.isWeekend   { return false }
            if let v = w.overFxLimit,   v != profile.toggles.overFxLimit { return false }
            if let v = w.overFreeAtm,   v != overFreeAtm                 { return false }
            if let v = w.fundingSource, v != profile.fundingSource       { return false }
            return true
        }
        func resolved(_ c: FeeComponent) -> Decimal {
            if c.source == .user, let key = c.profileKey, let v = profile.value(for: key) { return v }
            return c.value
        }

        // ---- applied & effective rate ----
        var rApplied: Decimal
        switch leg.rateSource {
        case .midMarket:
            // A live measured rate for this leg (e.g. a venue's USDT/THB bid)
            // beats the mid-rate assumption.
            rApplied = liveRates[leg.id] ?? rMid
        case .quoted:
            // precedence: the user's typed quote > today's best scraped board > the estimate
            rApplied = profile.boothQuote
                ?? liveBoothRate
                ?? (rMid * (1 - (leg.typicalBoothMargin ?? profile.boothMarginOffMid)))
        case .midMarketMargin:
            rApplied = rMid * (1 - (leg.fxMarginPct ?? 0))
        }
        var rEff = rApplied
        for c in leg.fees where c.kind == .rateMargin && active(c) {
            rEff *= (1 - resolved(c))
        }
        guard rEff > 0 else {
            return MethodResult(id: leg.id, label: leg.label, group: leg.group,
                                netThb: targetThb, usdCost: 0,
                                effectiveRate: 0, costThb: 0, costVsMidPct: 0, withdrawals: withdrawals,
                                lines: [], warnings: ["Rate unavailable"], speed: leg.speed)
        }

        // ---- fold fee components ----
        let baseUsd = targetThb / rEff
        let freeAllowanceUsd = (leg.freeAtmAmountThb ?? 0) / rEff

        var usdFees: Decimal = 0
        var thbFees: Decimal = 0
        var interestBaseUsd = baseUsd
        var lines: [CostLine] = []

        // exchange-rate line — contextual label, ฿0 when converting at market
        let rateLoss = baseUsd * (rMid - rEff)
        lines.append(CostLine(label: rateLoss <= 0 ? "Exchange rate · at market" : "Exchange-rate markup",
                              thb: max(0, rateLoss)))

        for c in leg.fees {
            guard active(c) else { continue }
            switch c.kind {
            case .rateMargin:
                continue   // already folded into rEff

            case .pctUsd:
                // .send is approximated as .base in v1 (the circular term is sub-0.01%)
                let basis = (c.feeOn == .overAllowance) ? max(0, baseUsd - freeAllowanceUsd) : baseUsd
                var amt = basis * resolved(c)
                if let mn = c.minUsd, amt > 0 { amt = max(amt, mn) }   // floor applies per-component
                if let mx = c.maxUsd { amt = min(amt, mx) }
                guard amt > 0 else { continue }
                usdFees += amt
                if c.interestBase == true { interestBaseUsd += amt }
                lines.append(CostLine(label: c.label, thb: amt * rMid))

            case .flatUsd:
                let mult = Decimal((c.per == .withdrawal) ? withdrawals : 1)
                let amt = resolved(c) * mult
                guard amt > 0 else { continue }
                usdFees += amt
                lines.append(CostLine(label: c.label, thb: amt * rMid))

            case .flatThb:
                let mult = Decimal((c.per == .withdrawal) ? withdrawals : 1)
                let amt = resolved(c) * mult
                guard amt > 0 else { continue }
                thbFees += amt
                let suffix = (withdrawals > 1 && c.per == .withdrawal) ? " ×\(withdrawals)" : ""
                lines.append(CostLine(label: c.label + suffix, thb: amt))
            }
        }

        // ---- cash-advance interest (future USD liability, valued at mid) ----
        var interestUsd: Decimal = 0
        if let im = leg.interest {
            let base = im.accruesOnFees ? interestBaseUsd : baseUsd
            interestUsd = base * im.apr * Decimal(profile.daysToPayoff) / 365
            if interestUsd > 0 {
                lines.append(CostLine(label: "Interest ~\(profile.daysToPayoff)d", thb: interestUsd * rMid))
            }
        }

        // ---- totals ----
        let usdCost = baseUsd + usdFees + interestUsd + (thbFees / rEff)
        let effectiveRate = usdCost > 0 ? targetThb / usdCost : 0
        let costThb = usdCost * (rMid - effectiveRate)
        let costVsMidPct = rMid > 0 ? (rMid - effectiveRate) / rMid * 100 : 0

        // ---- warnings ----
        var warnings: [String] = []
        if leg.acceptance == "limited" || leg.acceptance == "poor" {
            warnings.append(leg.acceptanceNote ?? "Limited acceptance at Thai ATMs")
        }
        if leg.volatility == "high" { warnings.append("Thai ATM fee drifts — verify at the machine") }
        if leg.taxFlag != nil && profile.daysInThailand >= 180 {
            warnings.append("180+ days: money sent to a Thai bank may be taxable")
        }
        if profile.toggles.dccAccepted && leg.fees.contains(where: { $0.kind == .rateMargin }) {
            warnings.append("You're losing money to DCC — decline it at the machine")
        }

        return MethodResult(
            id: leg.id, label: leg.label, group: leg.group,
            netThb: targetThb, usdCost: usdCost, effectiveRate: effectiveRate,
            costThb: costThb, costVsMidPct: costVsMidPct, withdrawals: withdrawals,
            lines: lines, warnings: warnings, speed: leg.speed
        )
    }
}
