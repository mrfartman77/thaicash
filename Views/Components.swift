import SwiftUI

// MARK: - Design tokens ("Private Bank" palette — champagne + sage on near-black)

extension Color {
    /// Champagne gold — the brand accent (baht symbol, best cost, chart, controls).
    static let bahtGold = Color(red: 0.83, green: 0.74, blue: 0.51)
    /// Muted sage — positive deltas and savings.
    static let sage = Color(red: 0.50, green: 0.75, blue: 0.58)
    /// Muted red — the costly outlier.
    static let lossRed = Color(red: 0.79, green: 0.44, blue: 0.44)
    /// Muted amber — warnings, text-only.
    static let warnAmber = Color(red: 0.76, green: 0.60, blue: 0.38)
    /// Card surface and app background.
    static let cardSurface = Color(red: 0.086, green: 0.086, blue: 0.102)   // #16161A
    static let appBackground = Color(red: 0.043, green: 0.043, blue: 0.051) // #0B0B0D
    /// Section/card outline — gilded gradient edge: lit from above (top), but the
    /// frame stays present at the bottom. Between "gradient edge" and "gilded strong".
    static let cardBorderTop = Color(red: 0.83, green: 0.74, blue: 0.51).opacity(0.75)
    static let cardBorderBottom = Color(red: 0.83, green: 0.74, blue: 0.51).opacity(0.30)
}

/// Display formatting — NumberFormatter/`String(format:)` based (no FormatStyle ambiguity).
enum Fmt {
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 0; return f
    }()
    static func num(_ d: Decimal) -> String { grouped.string(from: NSDecimalNumber(decimal: d)) ?? "0" }
    static func baht(_ d: Decimal) -> String { "฿" + num(d) }
    static func usd(_ d: Decimal) -> String { "$" + num(d) }
    static func rate(_ d: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: d).doubleValue)
    }
    static func pct(_ d: Decimal) -> String {
        "+" + String(format: "%.1f", NSDecimalNumber(decimal: d).doubleValue) + "%"
    }
}

/// Rounded grouped-style card container (semantic colors → light + dark for free).
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.cardBorderTop, .cardBorderBottom],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2
                    )
            )
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .kerning(1.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 18)
            .padding(.bottom, 8)
    }
}

struct BestBadge: View {
    var body: some View {
        Text("BEST")
            .font(.system(size: 9, weight: .bold))
            .kerning(1.2)
            .foregroundStyle(Color.sage)
            .padding(.horizontal, 8).padding(.vertical, 2.5)
            .overlay(Capsule().strokeBorder(Color.sage.opacity(0.5), lineWidth: 0.5))
    }
}

struct WarningChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.warnAmber)
    }
}
