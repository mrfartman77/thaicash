import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let grouped = model.results
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    RateChartView()
                    AmountCard()
                    ForEach(model.groupsInOrder, id: \.self) { group in
                        if let results = grouped[group], !results.isEmpty {
                            GroupCard(group: group, results: results,
                                      rows: model.homeRows(for: group))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 96)   // clear the iOS 26 floating tab bar so the last group scrolls into view
            }
            .background(Color.appBackground)
            .scrollIndicators(.visible)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RateChartView: View {
    @EnvironmentObject var model: AppModel

    private var points: [RatePoint] { model.rates.history }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(freshnessColor).frame(width: 6, height: 6)
                            Text("THB / USD").font(.system(size: 10.5, weight: .semibold)).kerning(1.4).foregroundStyle(.secondary)
                        }
                        Text(currentText).font(.system(size: 26, weight: .semibold)).monospacedDigit()
                    }
                    Spacer()
                    if let ch = weeklyChange {
                        Text(ch.text).font(.footnote).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(ch.up ? Color.sage : Color.lossRed)
                    }
                }

                if points.count >= 2 {
                    Chart(points) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("THB", p.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [Color.bahtGold.opacity(0.12), .clear],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", p.date), y: .value("THB", p.value))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(Color.bahtGold)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    }
                    .chartYScale(domain: yDomain)
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 76)
                } else {
                    Text("Loading 7-day trend…")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 84)
                }
            }
            .padding(16)
        }
        .onTapGesture { Task { await model.rates.refresh() } }
    }

    private var currentText: String {
        guard let v = model.rates.rate?.value else { return "—" }
        return "฿" + Fmt.rate(v)
    }
    private var freshnessColor: Color {
        switch model.rates.freshness {
        case .fresh: return .sage
        case .stale: return .warnAmber
        case .none:  return .gray
        }
    }
    private var weeklyChange: (text: String, up: Bool)? {
        let v = points.map(\.value)
        guard v.count >= 2, let first = v.first, let last = v.last, first > 0 else { return nil }
        let pct = (last - first) / first * 100
        let up = pct >= 0
        return ("\(up ? "▲" : "▼") \(String(format: "%.1f", abs(pct)))% · 7d", up)
    }
    private var yDomain: ClosedRange<Double> {
        let v = points.map(\.value)
        guard let lo = v.min(), let hi = v.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.35, 0.03)
        return (lo - pad)...(hi + pad)
    }
}

enum InputCurrency { case thb, usd }

struct AmountCard: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var focused: Bool
    @State private var currency: InputCurrency = .thb
    @State private var amountText: String = ""

    private let thbPresets: [Decimal] = [10_000, 20_000, 40_000, 60_000]
    private let usdPresets: [Decimal] = [100, 300, 500, 1_000]
    private var rMid: Decimal { model.rates.rate?.value ?? 0 }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                // Centerline lockup: every element vertically centered on one axis
                // (deliberately NOT baseline-aligned — user preference).
                HStack(alignment: .center, spacing: 9) {
                    Text(currency == .thb ? "฿" : "$")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(currency == .thb ? Color.bahtGold : Color.sage)
                        .onTapGesture { toggleCurrency() }
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .onTapGesture { toggleCurrency() }
                    TextField("0", text: $amountText)
                        .font(.system(size: 40, weight: .medium))
                        .monospacedDigit()
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") { focused = false }
                            }
                        }
                        .onChange(of: amountText) { _, newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(9))
                            let grouped = digits.isEmpty ? "" : Fmt.num(Decimal(string: digits) ?? 0)
                            if grouped != newValue { amountText = grouped }   // commas; empty allowed
                            let entered = Decimal(string: digits) ?? 0
                            let thb = currency == .usd ? entered * rMid : entered
                            if model.amountTHB != thb { model.amountTHB = thb }
                        }
                        .onAppear { syncTextFromModel() }
                }

                if rMid > 0 {
                    Text(equivalent).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }

                HStack(spacing: 9) {
                    ForEach(presets, id: \.self) { p in
                        Button { applyPreset(p); focused = false } label: {
                            Text(presetLabel(p))
                                .font(.system(size: 12.5, weight: isSelected(p) ? .semibold : .medium))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(isSelected(p) ? Color.bahtGold.opacity(0.10) : Color.clear, in: Capsule())
                                .overlay(Capsule().strokeBorder(
                                    isSelected(p) ? Color.bahtGold.opacity(0.55) : Color.white.opacity(0.12),
                                    lineWidth: 0.5))
                                .foregroundStyle(isSelected(p) ? Color.bahtGold : Color.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)
        }
    }

    private var presets: [Decimal] { currency == .thb ? thbPresets : usdPresets }


    // String-backed editing: a value-bound numeric TextField refuses to delete the
    // last digit (empty text can't parse, so SwiftUI restores the old value). The
    // string buffer may be empty (grey "0" placeholder); digits parse into the model.
    private func toggleCurrency() {
        currency = (currency == .thb ? .usd : .thb)
        syncTextFromModel()
    }
    private func syncTextFromModel() {
        let v: Decimal = currency == .thb ? model.amountTHB
                                          : (rMid > 0 ? model.amountTHB / rMid : 0)
        amountText = v == 0 ? "" : Fmt.num(v)
    }

    private var equivalent: String {
        switch currency {
        case .thb: return rMid > 0 ? "≈ " + Fmt.usd(model.amountTHB / rMid) : ""
        case .usd: return "≈ " + Fmt.baht(model.amountTHB)
        }
    }

    private func applyPreset(_ p: Decimal) {
        model.amountTHB = (currency == .usd) ? p * rMid : p
        syncTextFromModel()
    }
    private func presetLabel(_ p: Decimal) -> String {
        let symbol = currency == .thb ? "฿" : "$"
        let v = NSDecimalNumber(decimal: p).doubleValue
        if v >= 1000, v.truncatingRemainder(dividingBy: 1000) == 0 {
            return symbol + String(format: "%.0fk", v / 1000)
        }
        return symbol + Fmt.num(p)
    }
    private func isSelected(_ p: Decimal) -> Bool {
        switch currency {
        case .thb: return model.amountTHB == p
        case .usd: return rMid > 0 && (model.amountTHB / rMid) == p
        }
    }
}

/// Tallest natural row height inside a card — every sibling stretches to match.
private struct RowHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct GroupCard: View {
    let group: OutputGroup
    let results: [MethodResult]          // every leg — "the priciest" stays honest even when rows fold
    let rows: [AppModel.HomeRow]

    @State private var rowMinHeight: CGFloat = 0

    private var worstCost: Decimal { results.map(\.costThb).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: group.title)
            Card {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                    if idx > 0 { Divider().padding(.leading, 16) }
                    rowView(row)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: RowHeightKey.self, value: g.size.height)
                        })
                        .frame(minHeight: rowMinHeight > 0 ? rowMinHeight : nil)
                }
            }
            .onPreferenceChange(RowHeightKey.self) { rowMinHeight = $0 }
        }
    }

    @ViewBuilder private func rowView(_ row: AppModel.HomeRow) -> some View {
        switch row {
        case .method(let r):
            NavigationLink {
                MethodDetailView(legID: r.id)
            } label: {
                MethodRow(result: r, savings: r.isBest ? worstCost - r.costThb : nil,
                          showsWarning: false)
            }
            .buttonStyle(.plain)
        case .rollup(let key, let label, let best, let memberIDs):
            NavigationLink {
                SubgroupDetailView(title: label, subgroupKey: key, memberIDs: memberIDs)
            } label: {
                MethodRow(result: best,
                          savings: best.isBest ? worstCost - best.costThb : nil,
                          titleOverride: label,
                          subtitleTag: best.label.components(separatedBy: " · ").first,
                          showsWarning: false)
            }
            .buttonStyle(.plain)
        }
    }
}

struct MethodRow: View {
    let result: MethodResult
    var savings: Decimal? = nil
    var titleOverride: String? = nil    // rollup rows show the subgroup label…
    var subtitleTag: String? = nil      // …and name the winning member up front
    var inList: Bool = false            // List rows: the List supplies insets + chevron
    var showsWarning: Bool = true       // Home rows hide chips — the detail screen carries them

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(titleOverride ?? result.label).font(.system(size: 15.5, weight: .medium)).foregroundStyle(.primary)
                    if result.isBest { BestBadge() }
                }
                Text(subtitle).font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                if let s = savings, s > 0 {
                    Text("Saves \(Fmt.baht(s)) vs the priciest")
                        .font(.caption).monospacedDigit().foregroundStyle(Color.sage)
                }
                if showsWarning, let w = result.warnings.first {
                    WarningChip(text: w)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.baht(result.costThb))
                    .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(costColor)
                Text("TRUE COST").font(.system(size: 9, weight: .semibold)).kerning(0.8).foregroundStyle(.tertiary)
            }
            if !inList {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, inList ? 0 : 18)
        .padding(.vertical, inList ? 4 : 14)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        // Rollup rows name the winning member instead of the ฿/$ figure —
        // the exact rate lives one tap deeper, and both don't fit one line.
        var s = subtitleTag.map { "\($0) · " } ?? "\(Fmt.rate(result.effectiveRate)) ฿/$ · "
        s += "\(Fmt.pct(result.costVsMidPct)) vs rate"
        if result.withdrawals > 1 { s += " · ×\(result.withdrawals)" }
        if let t = result.speed { s += " · \(t)" }
        return s
    }
    private var costColor: Color {
        if result.isBest { return .sage }          // green = the best (cheapest) option
        if result.costVsMidPct >= 8 { return .lossRed }
        return .primary
    }
}
