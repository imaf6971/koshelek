import Foundation

extension Calendar {
    /// Gregorian calendar, ru_RU locale, weeks start on Monday.
    static let app: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "ru_RU")
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        return c
    }()
}

enum PeriodKind: String, CaseIterable, Identifiable, Codable {
    case week, month, year, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: L("Неделя")
        case .month: L("Месяц")
        case .year: L("Год")
        case .custom: L("Период")
        }
    }
}

/// A half-open date interval [start, end) aligned to day boundaries.
struct Period: Equatable {
    var kind: PeriodKind
    var start: Date
    var end: Date

    static func containing(_ date: Date, kind: PeriodKind, calendar: Calendar = .app) -> Period {
        switch kind {
        case .week: return make(kind, .weekOfYear, date, calendar)
        case .month: return make(kind, .month, date, calendar)
        case .year: return make(kind, .year, date, calendar)
        case .custom:
            let s = calendar.startOfDay(for: date)
            return Period(kind: .custom, start: s, end: calendar.date(byAdding: .day, value: 1, to: s)!)
        }
    }

    private static func make(_ kind: PeriodKind, _ comp: Calendar.Component, _ date: Date, _ cal: Calendar) -> Period {
        let i = cal.dateInterval(of: comp, for: date)!
        return Period(kind: kind, start: i.start, end: i.end)
    }

    /// Custom period from first to last day, both inclusive.
    static func custom(from: Date, to: Date, calendar: Calendar = .app) -> Period {
        let s = calendar.startOfDay(for: min(from, to))
        let e = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, to)))!
        return Period(kind: .custom, start: s, end: e)
    }

    func contains(_ d: Date) -> Bool { d >= start && d < end }

    var lastDay: Date { end.addingTimeInterval(-1) }

    func dayCount(calendar: Calendar = .app) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 1
    }

    func shifted(by n: Int, calendar: Calendar = .app) -> Period {
        switch kind {
        case .week: return Period.containing(calendar.date(byAdding: .weekOfYear, value: n, to: start)!, kind: .week, calendar: calendar)
        case .month: return Period.containing(calendar.date(byAdding: .month, value: n, to: start)!, kind: .month, calendar: calendar)
        case .year: return Period.containing(calendar.date(byAdding: .year, value: n, to: start)!, kind: .year, calendar: calendar)
        case .custom:
            let len = dayCount(calendar: calendar)
            let s = calendar.date(byAdding: .day, value: n * len, to: start)!
            let e = calendar.date(byAdding: .day, value: n * len + len, to: start)!
            return Period(kind: .custom, start: s, end: e)
        }
    }

    func previous(calendar: Calendar = .app) -> Period { shifted(by: -1, calendar: calendar) }

    func title(calendar: Calendar = .app) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.calendar = calendar
        switch kind {
        case .month:
            f.setLocalizedDateFormatFromTemplate("LLLL yyyy")
            return f.string(from: start).capitalizedFirst
        case .year:
            f.setLocalizedDateFormatFromTemplate("yyyy")
            return f.string(from: start)
        case .week, .custom:
            let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: lastDay)
            f.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
            let a = f.string(from: start)
            f.setLocalizedDateFormatFromTemplate("d MMM yyyy")
            return "\(a) – \(f.string(from: lastDay))"
        }
    }

    private static let dativeMonths = ["январю", "февралю", "марту", "апрелю", "маю", "июню",
                                       "июлю", "августу", "сентябрю", "октябрю", "ноябрю", "декабрю"]

    /// Short phrase for "compared to the previous period", e.g. "к сентябрю".
    func comparisonLabel(calendar: Calendar = .app) -> String {
        switch kind {
        case .week: return L("к прошлой неделе")
        case .month:
            let m = calendar.component(.month, from: previous(calendar: calendar).start)
            return LF("к %@", Self.dativeMonths[m - 1])
        case .year:
            return LF("к %@ году", String(calendar.component(.year, from: previous(calendar: calendar).start)))
        case .custom: return L("к предыдущему периоду")
        }
    }
}
