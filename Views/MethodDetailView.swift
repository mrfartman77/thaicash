import SwiftUI

struct MethodDetailView: View {
    @EnvironmentObject var model: AppModel
    let legID: String

    private var r: MethodResult? { model.result(id: legID) }
    private var leg: Leg? { model.catalog.data.legs.first { $0.id == legID } }

    var body: some View {
        Group {
            if let r {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ALL-IN COST").font(.system(size: 10.5, weight: .semibold)).kerning(1.4).foregroundStyle(.secondary)
                            Text(Fmt.baht(r.costThb)).font(.system(size: 36, weight: .semibold)).monospacedDigit()
                            Text(summary(r)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            if leg?.rateSource == .quoted {
                                Text(boothSourceText)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Where it goes") {
                        ForEach(r.lines) { line in
                            HStack {
                                Text(line.label)
                                Spacer()
                                Text(Fmt.baht(line.thb)).monospacedDigit()
                            }
                            .foregroundStyle(line.isZero ? .secondary : .primary)
                        }
                        HStack {
                            Text("Total").fontWeight(.bold)
                            Spacer()
                            Text(Fmt.baht(r.costThb)).fontWeight(.bold).monospacedDigit()
                        }
                    }

                    AdjustSection(result: r)

                    if leg?.rateSource == .quoted, !boothDisplays.isEmpty {
                        Section {
                            ForEach(boothDisplays) { d in
                                if let url = d.info.mapsURL {
                                    Link(destination: url) { boothRow(d) }
                                } else {
                                    boothRow(d)
                                }
                            }
                        } header: {
                            Text("Find a booth")
                        } footer: {
                            Text(boothFooter)
                        }
                    }

                    if !r.warnings.isEmpty {
                        Section {
                            ForEach(r.warnings, id: \.self) { w in
                                Label(w, systemImage: "exclamationmark.triangle").font(.subheadline)
                            }
                        }
                    }

                    if let n = leg?.notes {
                        Section { Text(n).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                .navigationTitle(r.label)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Unavailable", systemImage: "questionmark")
            }
        }
    }

    /// Catalog directory entry joined with its live scraped board rate (if any).
    private struct BoothDisplay: Identifiable {
        let info: BoothInfo
        let live: BoothRateEntry?
        var id: String { info.id }
    }

    /// Measured booths first (best board on top), then pending, AVOID last.
    private var boothDisplays: [BoothDisplay] {
        guard let booths = model.catalog.data.booths, !booths.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: model.boothRates.live.map { ($0.id, $0) })
        let all = booths.map { BoothDisplay(info: $0, live: byID[$0.id]) }
        let rated = all.filter { $0.live != nil }
            .sorted { ($0.live?.usd100Buy ?? 0) > ($1.live?.usd100Buy ?? 0) }
        let pending = all.filter { $0.live == nil && $0.info.quality != "avoid" }
        let avoid = all.filter { $0.live == nil && $0.info.quality == "avoid" }
        return rated + pending + avoid
    }

    private var bestLiveID: String? {
        boothDisplays.first(where: { $0.live != nil })?.id
    }

    /// Whose rate is the headline using? quote > live best board > estimate.
    private var boothSourceText: String {
        if model.profile.boothQuote != nil {
            return "Using the board rate you entered — exact for that booth."
        }
        if let best = model.boothRates.bestUsable, let r = best.usd100Buy {
            let age = model.boothRates.ageText.map { ", updated \($0)" } ?? ""
            return "Using today's best board rate — \(best.name), \(Fmt.rate(r)) ฿/$\(age)."
        }
        return "Estimated — the typical margin at the chains below. Type a board rate into Adjust for exact numbers."
    }

    private var boothFooter: String {
        var s = "Live USD-100 board rates, refreshed every ~2h"
        if let age = model.boothRates.ageText { s += " · updated \(age)" }
        return s + ". Well-known chains only — tap to open in Maps. Type a board rate into Adjust to override."
    }

    private func boothRow(_ d: BoothDisplay) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(d.info.name).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                    if let tag = tagQuality(for: d) { BoothQualityTag(quality: tag) }
                }
                Text(d.info.areas).font(.caption).foregroundStyle(.secondary)
                if let n = d.info.note { Text(n).font(.caption2).foregroundStyle(.tertiary) }
            }
            Spacer()
            if let r = d.live?.usd100Buy {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.rate(r))
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(d.id == bestLiveID ? Color.bahtGold : .primary)
                    Text("฿/$ BOARD").font(.system(size: 8, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(.tertiary)
                    if let src = d.live?.source {
                        Text(src).font(.system(size: 8)).foregroundStyle(.tertiary)
                    }
                }
            }
            if d.info.mapsURL != nil {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Color.bahtGold).font(.subheadline)
            }
        }
    }

    /// Measured booths: only the winner gets a tag (the rate speaks for the rest).
    /// Unmeasured: grey RATES PENDING, except the avoid row.
    private func tagQuality(for d: BoothDisplay) -> String? {
        if d.live != nil { return d.id == bestLiveID ? "best" : nil }
        return d.info.quality == "avoid" ? "avoid" : "pending"
    }

    private func summary(_ r: MethodResult) -> String {
        var s = "\(Fmt.rate(r.effectiveRate)) ฿/$ · \(Fmt.pct(r.costVsMidPct)) vs rate"
        if r.withdrawals > 1 { s += " · \(r.withdrawals) withdrawals" }
        return s
    }
}

/// Quality tag for the booth directory (BEST RATES / GOOD / AVOID).
struct BoothQualityTag: View {
    let quality: String
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .kerning(1.0)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(color.opacity(0.5), lineWidth: 0.5))
    }
    private var label: String {
        switch quality {
        case "best":    return "BEST RATES"
        case "good":    return "GOOD"
        case "pending": return "RATES PENDING"
        default:        return "AVOID"
        }
    }
    private var color: Color {
        switch quality {
        case "best":    return .bahtGold
        case "good":    return .sage
        case "pending": return Color(white: 0.55)
        default:        return .lossRed
        }
    }
}

/// Method-specific live controls — each write routes through `model.update`,
/// so toggling recomputes the engine and the breakdown updates instantly.
struct AdjustSection: View {
    @EnvironmentObject var model: AppModel
    let result: MethodResult
    @State private var quoteText = ""   // string-backed: empty allowed, deletable

    private var leg: Leg? { model.catalog.data.legs.first { $0.id == result.id } }

    private var hasControls: Bool {
        guard let leg else { return false }
        let dcc = leg.fees.contains { $0.kind == .rateMargin && ($0.when?.dccAccepted ?? false) }
        let funding = leg.fees.contains { $0.when?.fundingSource != nil }
        return leg.rateSource == .quoted || dcc || funding || leg.interest != nil
    }

    var body: some View {
        if let leg, hasControls {
            Section("Adjust") {
                if leg.rateSource == .quoted {
                    HStack {
                        Text("Booth's quoted rate")
                        Spacer()
                        TextField("e.g. 32.50", text: $quoteText)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 110)
                            .onChange(of: quoteText) { _, v in
                                var clean = ""; var dot = false
                                for ch in v {
                                    if ch.isNumber { clean.append(ch) }
                                    else if ch == "." && !dot { clean.append(ch); dot = true }
                                }
                                if clean != v { quoteText = clean }
                                model.update { $0.boothQuote = clean.isEmpty ? nil : Decimal(string: clean) }
                            }
                            .onAppear { quoteText = model.profile.boothQuote.map { Fmt.rate($0) } ?? "" }
                    }
                }
                if leg.fees.contains(where: { $0.kind == .rateMargin && ($0.when?.dccAccepted ?? false) }) {
                    Toggle("I accepted DCC (don't!)", isOn: dccBinding)
                }
                if leg.fees.contains(where: { $0.when?.fundingSource != nil }) {
                    Picker("Funding", selection: fundingBinding) {
                        ForEach(FundingSource.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                if leg.interest != nil {
                    Stepper("Pay off in \(model.profile.daysToPayoff) days", value: payoffBinding, in: 1...90)
                }
            }
        }
    }

    private var dccBinding: Binding<Bool> {
        Binding(get: { model.profile.toggles.dccAccepted },
                set: { v in model.update { $0.toggles.dccAccepted = v } })
    }
    private var fundingBinding: Binding<FundingSource> {
        Binding(get: { model.profile.fundingSource },
                set: { v in model.update { $0.fundingSource = v } })
    }
    private var payoffBinding: Binding<Int> {
        Binding(get: { model.profile.daysToPayoff },
                set: { v in model.update { $0.daysToPayoff = v } })
    }
}
