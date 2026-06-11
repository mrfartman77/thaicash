import SwiftUI

struct MethodDetailView: View {
    @EnvironmentObject var model: AppModel
    let legID: String

    private var r: MethodResult? { model.result(id: legID) }
    private var leg: Leg? { model.corridor?.legs.first { $0.id == legID } }
    private var base: String { model.corridor?.base ?? "USD" }
    private var baseSymbol: String { model.corridor?.baseSymbol ?? "$" }

    var body: some View {
        Group {
            if let r {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TRUE COST").font(.system(size: 10.5, weight: .semibold)).kerning(1.4).foregroundStyle(.secondary)
                            Text(Fmt.baht(r.costThb)).font(.system(size: 36, weight: .semibold)).monospacedDigit()
                            Text(summary(r)).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                            if leg?.rateSource == .quoted {
                                Text(boothSourceText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                            if leg?.group == .cryptoThb {
                                Text(cryptoSourceText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            }
                        }
                        .padding(.vertical, 4)
                    }

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

                    if let urlString = leg?.linkURL, let url = URL(string: urlString) {
                        Section {
                            Link(destination: url) {
                                HStack {
                                    Text(linkHost(urlString)).font(.subheadline).fontWeight(.medium)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundStyle(Color.bahtGold).font(.subheadline)
                                }
                                .foregroundStyle(Color.primary)   // Link would tint the text gold
                            }
                        } header: {
                            Text("Get started")
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
        guard let booths = model.corridor?.booths, !booths.isEmpty else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: model.boothRates.live(base: base).map { ($0.id, $0) })
        let all = booths.map { BoothDisplay(info: $0, live: byID[$0.id]) }
        let rated = all.filter { $0.live != nil }
            .sorted { ($0.live?.buyRate(base) ?? 0) > ($1.live?.buyRate(base) ?? 0) }
        let pending = all.filter { $0.live == nil && $0.info.quality != "avoid" }
        let avoid = all.filter { $0.live == nil && $0.info.quality == "avoid" }
        return rated + pending + avoid
    }

    private var bestLiveID: String? {
        boothDisplays.first(where: { $0.live != nil })?.id
    }

    /// Whose rate is the headline using? quote > live best board > estimate.
    /// The named booth is the directory winner (bestLiveID) — same rate-then-
    /// catalog-order tie-break as the BEST RATES tag, so the two always agree.
    private var boothSourceText: String {
        if model.profile.boothQuote != nil {
            return "Using the board rate you entered — exact for that booth."
        }
        if model.boothRates.isFreshEnoughForEngine,
           let best = boothDisplays.first(where: { $0.live != nil }),
           let r = best.live?.buyRate(base) {
            let age = model.boothRates.ageText.map { ", updated \($0)" } ?? ""
            return "Using today's best board rate — \(best.info.name), \(Fmt.rate(r)) ฿/\(baseSymbol)\(age)."
        }
        return "Estimated — the typical margin at the chains below."
    }

    /// Whose USDT/THB price is the headline using? live venue bid > mid assumption.
    private var cryptoSourceText: String {
        if let r = model.cryptoRates.liveRates[legID] {
            let age = model.cryptoRates.ageText.map { ", updated \($0)" } ?? ""
            return "Using the venue's live bid — \(Fmt.rate(r)) ฿ per USDT\(age)."
        }
        return "No fresh board data — assuming the pair trades at the mid-market rate."
    }

    private var boothFooter: String {
        var s = "Live large-note \(base) board rates, refreshed hourly"
        if let age = model.boothRates.ageText { s += " · updated \(age)" }
        return s + ". Well-known chains only — tap to open in Maps."
    }

    private func boothRow(_ d: BoothDisplay) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(d.info.name).font(.subheadline).fontWeight(.medium).foregroundStyle(.primary)
                    if let tag = tagQuality(for: d) { BoothQualityTag(quality: tag) }
                }
                Text(d.info.areas).font(.caption).foregroundStyle(.secondary)
                if let n = d.info.note { Text(n).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if let r = d.live?.buyRate(base) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.rate(r))
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(d.id == bestLiveID ? Color.sage : .primary)
                    Text("฿/\(baseSymbol) BOARD").font(.system(size: 8, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(.secondary)
                    if let src = d.live?.source {
                        Text(src).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
            if d.info.mapsURL != nil {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Color.bahtGold).font(.subheadline)
            }
        }
        // Pin the row to label colors: Link tints its label gold, and
        // hierarchical .primary/.secondary would inherit it. Explicit colors
        // inside (gold arrow, sage rate, tags) still win.
        .foregroundStyle(Color.primary)
    }

    /// Measured booths: only the winner gets a tag (the rate speaks for the rest).
    /// Unmeasured: grey RATES PENDING, except the avoid row.
    private func tagQuality(for d: BoothDisplay) -> String? {
        if d.live != nil { return d.id == bestLiveID ? "best" : nil }
        return d.info.quality == "avoid" ? "avoid" : "pending"
    }

    /// "https://www.schwab.com/checking" → "schwab.com/checking" — short, honest.
    private func linkHost(_ urlString: String) -> String {
        urlString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "www.", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func summary(_ r: MethodResult) -> String {
        var s = "\(Fmt.rate(r.effectiveRate)) ฿/\(baseSymbol) · \(Fmt.pct(r.costVsMidPct)) vs rate"
        if r.withdrawals > 1 { s += " · \(r.withdrawals) withdrawals" }
        if let t = r.speed { s += " · arrives \(t)" }
        return s
    }
}

/// Rollup detail — the legs that share one Home row (e.g. the three ATM
/// cards), re-ranked live for the current amount; each opens its own detail.
struct SubgroupDetailView: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let subgroupKey: String
    let memberIDs: [String]

    private var members: [MethodResult] {
        var ms = memberIDs.compactMap { model.result(id: $0) }
                          .sorted { $0.effectiveRate > $1.effectiveRate }
        for i in ms.indices { ms[i].isBest = (i == 0) }   // best within this screen
        return ms
    }
    private var worstCost: Decimal { members.map(\.costThb).max() ?? 0 }

    /// Catalog-supplied footer (any member's), so the copy updates remotely.
    private var footnote: String {
        let legs = model.corridor?.legs ?? []
        return memberIDs.compactMap { id in legs.first { $0.id == id }?.subgroupNote }.first
            ?? "Same machine, different card — the card decides the cost."
    }

    private var directory: SubgroupDirectory? {
        model.corridor?.directories?[subgroupKey]
    }

    var body: some View {
        List {
            Section {
                ForEach(members) { r in
                    NavigationLink {
                        MethodDetailView(legID: r.id)
                    } label: {
                        MethodRow(result: r, savings: r.isBest ? worstCost - r.costThb : nil,
                                  inList: true,
                                  rateSymbol: model.corridor?.baseSymbol ?? "$")
                    }
                }
            } footer: {
                Text(footnote)
            }

            if let dir = directory, !dir.entries.isEmpty {
                Section {
                    ForEach(dir.entries) { e in
                        if let url = e.mapsURL {
                            Link(destination: url) { directoryRow(e, in: dir) }
                        } else {
                            directoryRow(e, in: dir)
                        }
                    }
                } header: {
                    Text(dir.title)
                } footer: {
                    dir.footer.map(Text.init)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func directoryRow(_ e: DirectoryEntry, in dir: SubgroupDirectory) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).font(.subheadline).fontWeight(.medium)
                Text(e.areas).font(.caption).foregroundStyle(.secondary)
                if let n = e.note { Text(n).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if let fee = e.feeThb {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.baht(fee))
                        .font(.system(size: 16, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(feeColor(fee, in: dir))
                    Text("FEE").font(.system(size: 8, weight: .semibold)).kerning(0.6)
                        .foregroundStyle(.secondary)
                }
            }
            if e.mapsURL != nil {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Color.bahtGold).font(.subheadline)
            }
        }
        .foregroundStyle(Color.primary)   // Link would tint hierarchical styles gold
    }

    /// Cheapest machine fee = green, the priciest = red, the rest neutral.
    private func feeColor(_ fee: Decimal, in dir: SubgroupDirectory) -> Color {
        let fees = dir.entries.compactMap(\.feeThb)
        guard let lo = fees.min(), let hi = fees.max(), lo != hi else { return .primary }
        if fee == lo { return .sage }
        if fee == hi { return .lossRed }
        return .primary
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
        case "best":    return .sage    // green = the chosen/best booth
        case "good":    return .sage
        case "pending": return Color(white: 0.55)
        default:        return .lossRed
        }
    }
}
