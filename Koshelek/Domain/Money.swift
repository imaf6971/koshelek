import Foundation

struct Currency: Codable, Hashable, Identifiable {
    var code: String
    var symbol: String
    var id: String { code }

    static let rub = Currency(code: "RUB", symbol: "₽")
    static let presets: [Currency] = [
        rub,
        Currency(code: "USD", symbol: "$"), Currency(code: "EUR", symbol: "€"),
        Currency(code: "KZT", symbol: "₸"), Currency(code: "BYN", symbol: "Br"),
        Currency(code: "UAH", symbol: "₴"), Currency(code: "GEL", symbol: "₾"),
        Currency(code: "TRY", symbol: "₺"), Currency(code: "GBP", symbol: "£"),
        Currency(code: "CNY", symbol: "¥"),
    ]
}

/// Formats amounts using ru_RU conventions: non-breaking space grouping, comma decimals.
struct MoneyFormatter: Equatable {
    var symbol: String

    private static let locale = Locale(identifier: "ru_RU")
    private static let whole = make(digits: 0)
    private static let fractional = make(digits: 2)

    private static func make(digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f
    }

    /// Number without a currency symbol; fraction digits shown only when needed.
    func number(_ value: Decimal) -> String {
        let r = value.rounded(2)
        let hasFraction = r != r.rounded(0, .down)
        let f = hasFraction ? Self.fractional : Self.whole
        return f.string(from: NSDecimalNumber(decimal: r)) ?? "\(r)"
    }

    func string(_ value: Decimal, signed: Bool = false) -> String {
        var s = number(value.magnitude) + "\u{00A0}" + symbol
        if value < 0 { s = "−" + s } else if signed && value > 0 { s = "+" + s }
        return s
    }
}

enum MoneyParser {
    /// Parses user input such as "1 234,50" or "1234.5"; returns nil for empty or invalid text.
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard !cleaned.isEmpty else { return nil }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension MoneyParser {
    /// Keeps digits and a single decimal comma (a dot becomes a comma), with at most ten integer and two fraction digits.
    static func sanitize(_ text: String) -> String {
        var result = "", seenSeparator = false, fraction = 0, integer = 0
        for ch in text {
            if ch.isASCII, ch.isNumber {
                if seenSeparator { guard fraction < 2 else { continue }; fraction += 1 }
                else { guard integer < 10 else { continue }; integer += 1 }
                result.append(ch)
            } else if (ch == "," || ch == "."), !seenSeparator {
                seenSeparator = true
                result.append(",")
            }
        }
        return result
    }
}

enum PercentFormatter {
    private static let f: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .percent
        f.maximumFractionDigits = 0
        return f
    }()
    static func string(_ fraction: Double) -> String { f.string(from: NSNumber(value: fraction)) ?? "" }
    static func signed(_ fraction: Double) -> String {
        let s = string(abs(fraction))
        return fraction > 0 ? "+" + s : (fraction < 0 ? "−" + s : s)
    }
}
