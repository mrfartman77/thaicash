import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var model: AppModel

    private var homeBase: String { model.profile.homeBase ?? "USD" }
    private var homeCorridor: Corridor? {
        model.corridors.first { $0.base == homeBase } ?? model.corridors.first
    }
    private var symbol: String { homeCorridor?.baseSymbol ?? "$" }

    /// The engine's stored default for a profile key in the home corridor —
    /// what every comparison uses until the user overrides it here.
    private func catalogDefault(_ key: String) -> Decimal? {
        for leg in homeCorridor?.legs ?? [] {
            for fee in leg.fees where fee.profileKey == key {
                return fee.value
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Home currency", selection: homeBinding) {
                        ForEach(model.corridors.filter { $0.base != "USDT" }) { c in
                            Text(c.base).tag(c.base)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Home currency")
                } footer: {
                    Text("Sets the defaults below to your region's typical bank, verified per corridor.")
                }

                Section {
                    DecimalRow(title: "Foreign-txn fee", suffix: "%", key: "bank_ftf",
                               defaultValue: catalogDefault("bank_ftf") ?? 0.03, scale: 100)
                    DecimalRow(title: "Your bank's ATM fee", suffix: symbol, key: "bank_atm_fee",
                               defaultValue: catalogDefault("bank_atm_fee") ?? 5, scale: 1)
                    DecimalRow(title: "Cash-advance fee", suffix: "%", key: "ca_fee",
                               defaultValue: catalogDefault("ca_fee") ?? 0.05, scale: 100)
                } header: {
                    Text("Your bank & cards")
                } footer: {
                    Text("Until you edit them, the \"Your debit/credit card\" rows use these typical-\(homeBase) defaults. Enter your own card's numbers and every comparison becomes exact.")
                }

                Section {
                    Picker("Funding source", selection: fundingBinding) {
                        ForEach(FundingSource.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Transfers")
                } footer: {
                    Text("How you pay the transfer provider — card funding costs more than a bank debit.")
                }
            }
            .navigationTitle("Setup")
        }
    }

    private var homeBinding: Binding<String> {
        Binding(get: { model.profile.homeBase ?? "USD" },
                set: { v in model.update { $0.homeBase = v } })
    }
    private var fundingBinding: Binding<FundingSource> {
        Binding(get: { model.profile.fundingSource },
                set: { v in model.update { $0.fundingSource = v } })
    }
}

/// Edits a `Profile.overrides[key]`, displaying stored value × scale
/// (e.g. 0.03 ↔ "3" for a percent). Falls back to the catalog default until edited.
struct DecimalRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    var prefix: String = ""
    var suffix: String = ""
    let key: String
    let defaultValue: Decimal
    let scale: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if !prefix.isEmpty { Text(prefix).foregroundStyle(.secondary) }
            TextField("", value: binding, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(width: 64)
            if !suffix.isEmpty {
                // Fixed slot so "%", "$" and "A$" all occupy the same width —
                // the value column stays aligned whatever the home currency.
                Text(suffix).foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .leading)
            }
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: {
                let stored = model.profile.value(for: key) ?? defaultValue
                return NSDecimalNumber(decimal: stored).doubleValue * scale
            },
            set: { shown in
                model.update { $0.overrides[key] = Decimal(shown / scale) }
            }
        )
    }
}
