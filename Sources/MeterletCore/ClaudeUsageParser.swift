import Foundation

public enum ClaudeUsageParser {
    public static func cleanTerminal(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\x1B\][^\x07]*(?:\x07|\x1B\\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\x1B[78=>]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    public static func parse(_ text: String, now: Date = .now, timeZone: TimeZone = .current) throws -> UsageSnapshot {
        let clean = cleanTerminal(text)
        let header = try! NSRegularExpression(pattern: #"(?im)^\s*Current\s+(session|week(?:\s*\(([^)]+)\))?)\s*$"#)
        let range = NSRange(clean.startIndex..., in: clean)
        let matches = header.matches(in: clean, range: range)
        var found: [String: UsageWindow] = [:]
        var order: [String] = []
        for (index, match) in matches.enumerated() {
            guard let titleRange = Range(match.range(at: 1), in: clean) else { continue }
            let title = String(clean[titleRange]).lowercased()
            let scope = Range(match.range(at: 2), in: clean).map { String(clean[$0]).trimmingCharacters(in: .whitespaces) }
            let isSession = title == "session"
            let isAll = scope == nil || scope?.lowercased() == "all models"
            let name = isSession || isAll ? nil : scope
            let key = isSession ? "session" : (name.map { "weekly.\($0.lowercased())" } ?? "weekly")
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : (clean as NSString).length
            let body = (clean as NSString).substring(with: NSRange(location: start, length: end - start))
            // A repaint can contain an incomplete newer section. Keep the last complete one.
            guard let used = percent(in: body) else { continue }
            let reset = body.components(separatedBy: .newlines).first {
                $0.range(of: #"(?i)\bresets?\b"#, options: .regularExpression) != nil
            }?.trimmingCharacters(in: .whitespaces)
            let date = reset.flatMap { ResetDateParser.parse($0, now: now, timeZone: timeZone) }
            if found[key] == nil { order.append(key) }
            found[key] = UsageWindow(
                id: key, scope: name, durationMinutes: isSession ? 300 : 10_080,
                usedPercent: used, resetsAt: date, resetDescription: date == nil ? reset : nil,
                isPrimary: isSession
            )
        }
        let windows = order.compactMap { found[$0] }
        guard !windows.isEmpty else { throw classifyFailure(clean) }
        return UsageSnapshot(provider: .claude, windows: windows, fetchedAt: now)
    }

    private static func percent(in body: String) -> Double? {
        let pattern = try! NSRegularExpression(pattern: #"(?i)(\d+(?:[.,]\d+)?)\s*%\s*(used|left|remaining)"#)
        guard let match = pattern.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let valueRange = Range(match.range(at: 1), in: body),
              let typeRange = Range(match.range(at: 2), in: body),
              let number = Double(body[valueRange].replacingOccurrences(of: ",", with: ".")), number.isFinite else { return nil }
        let used = body[typeRange].lowercased() == "used" ? number : 100 - number
        return used >= 0 ? used : nil
    }

    public static func classifyFailure(_ text: String) -> UsageError {
        let lower = text.lowercased()
        if lower.contains("unknown option") || lower.contains("unrecognized option") { return .unsupportedCLI(.claude) }
        if lower.contains("choose the text style") || lower.contains("let's get started") { return .setupRequired(.claude) }
        if UsageError.isAuthenticationFailure(lower) || lower.contains("login method")
            || lower.contains("select login") { return .signInRequired(.claude) }
        if UsageError.isRateLimitFailure(lower) { return .rateLimited(.claude) }
        if lower.contains("failed to load") || lower.contains("error fetching") { return .unavailable(.claude) }
        return .noUsage(.claude)
    }
}
