import Foundation

/// Date helpers for the API's plain `yyyy-MM-dd` date strings. We treat those as
/// calendar days in the user's current time zone for display and grouping.
enum DateUtil {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_GB")
        return c
    }()

    private static let apiParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    static func date(from apiString: String?) -> Date? {
        guard let s = apiString, !s.isEmpty else { return nil }
        // Some date fields may include a time component; keep just the date part.
        let dayPart = String(s.prefix(10))
        return apiParser.date(from: dayPart)
    }

    static func todayString() -> String {
        apiParser.string(from: Date())
    }

    /// Format a Date as the API's `yyyy-MM-dd` day string.
    static func apiString(from date: Date) -> String {
        apiParser.string(from: date)
    }

    static func addingDays(_ days: Int, to apiString: String) -> String? {
        guard let d = date(from: apiString),
              let next = calendar.date(byAdding: .day, value: days, to: d) else { return nil }
        return apiParser.string(from: next)
    }

    // MARK: Display

    private static let weekdayDay: DateFormatter = make("EEE d MMM")
    private static let fullDate: DateFormatter = make("EEEE d MMMM yyyy")
    private static let whatsAppDateFmt: DateFormatter = make("EEE d MMM yyyy")

    /// Matches the web's WhatsApp message date ("Mon 30 Jun 2026").
    static func whatsAppDate(from apiString: String?) -> String {
        guard let d = date(from: apiString) else { return "" }
        return whatsAppDateFmt.string(from: d)
    }

    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = format
        f.timeZone = TimeZone.current
        return f
    }

    /// e.g. "Today", "Tomorrow", "Yesterday", or "Mon 8 Sep".
    static func relativeLabel(from apiString: String?) -> String {
        guard let d = date(from: apiString) else { return "No date" }
        if calendar.isDateInToday(d) { return "Today" }
        if calendar.isDateInTomorrow(d) { return "Tomorrow" }
        if calendar.isDateInYesterday(d) { return "Yesterday" }
        return weekdayDay.string(from: d)
    }

    static func weekdayDayLabel(from apiString: String?) -> String {
        guard let d = date(from: apiString) else { return "No date" }
        return weekdayDay.string(from: d)
    }

    static func fullLabel(from apiString: String?) -> String {
        guard let d = date(from: apiString) else { return "Date TBC" }
        return fullDate.string(from: d)
    }

    static func isToday(_ apiString: String?) -> Bool {
        guard let d = date(from: apiString) else { return false }
        return calendar.isDateInToday(d)
    }
}

extension String {
    /// Trim and return nil when empty — handy for optional API strings.
    var nilIfBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Keep only digits and a leading-plus set, nil if nothing usable remains.
    /// Shared by Job (site contact) and Haulier phone handling.
    var phoneDigits: String? {
        let allowed = filter { "+0123456789".contains($0) }
        return allowed.isEmpty ? nil : allowed
    }
}
