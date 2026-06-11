import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Your bank & cards") {
                    DecimalRow(title: "Foreign-txn fee", suffix: "%", key: "bank_ftf", defaultValue: 0.03, scale: 100)
                    DecimalRow(title: "Your bank's ATM fee", prefix: "$", key: "bank_atm_fee", defaultValue: 5, scale: 1)
                    DecimalRow(title: "Cash-advance fee", suffix: "%", key: "ca_fee", defaultValue: 0.05, scale: 100)
                }

                Section("Transfers") {
                    Picker("Funding source", selection: fundingBinding) {
                        ForEach(FundingSource.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Stepper("Days in Thailand / yr: \(model.profile.daysInThailand)",
                            value: daysBinding, in: 0...365, step: 5)
                } header: {
                    Text("Trip")
                } footer: {
                    Text("180+ days makes you a tax resident — money sent to a Thai bank may become taxable.")
                }
            }
            .navigationTitle("Setup")
        }
    }

    private var fundingBinding: Binding<FundingSource> {
        Binding(get: { model.profile.fundingSource },
                set: { v in model.update { $0.fundingSource = v } })
    }
    private var daysBinding: Binding<Int> {
        Binding(get: { model.profile.daysInThailand },
                set: { v in model.update { $0.daysInThailand = v } })
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
            if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
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
