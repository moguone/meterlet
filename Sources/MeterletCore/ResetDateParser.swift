import Foundation

/// Parses the official CLI's English reset labels. Unknown formats remain visible as source text.
public enum ResetDateParser {
    public static func parse(_ description: String, now: Date, timeZone: TimeZone = .current) -> Date? {
        var raw = description.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = raw.replacingOccurrences(of: #"(?i)^resets?\s*:?\s*"#, with: "", options: .regularExpression)
        var zone = timeZone
        if let range = raw.range(of: #"\s*\(([^)]+)\)\s*$"#, options: .regularExpression) {
            let name = raw[range].trimmingCharacters(in: CharacterSet(charactersIn: " ()"))
            guard let explicitZone = TimeZone(identifier: name) ?? TimeZone(abbreviation: name) else { return nil }
            zone = explicitZone
            raw.removeSubrange(range)
        }
        raw = raw.replacingOccurrences(of: #"(?i)\s+at\s+"#, with: " ", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.isLenient = false
        // Hour-only labels ("4pm") must not inherit the current minute or second.
        formatter.defaultDate = calendar.startOfDay(for: now)
        let timeFormats = ["h:mma", "h:mm a", "ha", "h a", "HH:mm"]
        func date(_ value: String, formats: [String]) -> Date? {
            for format in formats {
                formatter.dateFormat = format
                if let parsed = formatter.date(from: value) { return parsed }
            }
            return nil
        }
        // Explicit dates are authoritative, including already-passed resets.
        let fullFormats = timeFormats.flatMap { ["MMM d, yyyy \($0)", "MMM d yyyy \($0)", "yyyy-MM-dd \($0)"] }
        if let parsed = date(raw, formats: fullFormats) { return parsed }
        let yearlessFormats = timeFormats.flatMap { ["MMM d, \($0)", "MMM d \($0)"] }
        if let parsed = date(raw, formats: yearlessFormats) {
            var parts = calendar.dateComponents([.month, .day, .hour, .minute], from: parsed)
            parts.year = calendar.component(.year, from: now)
            guard let thisYear = calendar.date(from: parts) else { return nil }
            // Only roll over across New Year, never turn yesterday into a year-long countdown.
            if thisYear.timeIntervalSince(now) < -180 * 86_400 { return calendar.date(byAdding: .year, value: 1, to: thisYear) }
            return thisYear
        }
        let lower = raw.lowercased()
        var explicitDay: Int?
        if lower.hasPrefix("today ") { raw = String(raw.dropFirst(6)); explicitDay = 0 }
        if lower.hasPrefix("tomorrow ") { raw = String(raw.dropFirst(9)); explicitDay = 1 }
        if let parsed = date(raw, formats: timeFormats) {
            let clock = calendar.dateComponents([.hour, .minute], from: parsed)
            guard let day = calendar.date(byAdding: .day, value: explicitDay ?? 0, to: now),
                  let candidate = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: day) else { return nil }
            if explicitDay != nil || candidate > now { return candidate }
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }
        // Some CLI versions use a weekday instead of a month/day.
        let weekdayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        if parts.count == 2, let weekday = weekdayNames.firstIndex(of: String(parts[0].lowercased().prefix(3))),
           let parsed = date(parts[1], formats: timeFormats) {
            let clock = calendar.dateComponents([.hour, .minute], from: parsed)
            return calendar.nextDate(after: now, matching: DateComponents(hour: clock.hour, minute: clock.minute, second: 0, weekday: weekday + 1), matchingPolicy: .nextTime)
        }
        return nil
    }
}
