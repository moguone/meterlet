import Foundation
import CoreFoundation

public enum ClaudeUsageParser {
    /// Reads stream-json output, which may include non-JSON standard-error lines.
    public static func parse(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        var text: [String] = []
        var hasResponse = false
        var report: Any?
        for line in data.split(separator: 10) {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                text.append(String(decoding: line, as: UTF8.self))
                continue
            }
            switch event["type"] as? String {
            case "assistant":
                hasResponse = true
                if let value = event["usage_report"] { report = value }
                if let message = event["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    text += content.compactMap { $0["text"] as? String }
                }
            case "result":
                hasResponse = true
                if let result = event["result"] as? String { text.append(result) }
            default: break
            }
        }
        let failure = classifyFailure(text.joined(separator: "\n"))
        guard let report else {
            if failure != .noUsage(.claude) { throw failure }
            throw hasResponse ? UsageError.unsupportedCLI(.claude) : UsageError.noUsage(.claude)
        }
        guard let report = report as? [String: Any],
              let rateLimits = report["rate_limits"] as? [String: Any],
              let limits = rateLimits["limits"] as? [[String: Any]], !limits.isEmpty else {
            throw failure == .noUsage(.claude) ? UsageError.unavailable(.claude) : failure
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let seconds = ISO8601DateFormatter()
        var found: [String: UsageWindow] = [:]
        var order: [String] = []
        for limit in limits {
            guard let percent = limit["percent"] as? NSNumber,
                  CFGetTypeID(percent) != CFBooleanGetTypeID(),
                  let kind = limit["kind"] as? String else { continue }
            let model = (limit["scope"] as? [String: Any])?["model"] as? [String: Any]
            let name = (model?["display_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let id: String
            switch kind {
            case "session": id = "session"
            case "weekly_all": id = "weekly"
            case "weekly_scoped": id = "weekly.\(name?.lowercased() ?? "scoped")"
            default: id = name.map { "\(kind).\($0.lowercased())" } ?? kind
            }
            let group = limit["group"] as? String
            let resetsAt = (limit["resets_at"] as? String).flatMap {
                fractional.date(from: $0) ?? seconds.date(from: $0)
            }
            if found[id] == nil { order.append(id) }
            found[id] = UsageWindow(
                id: id, scope: kind == "weekly_all" ? nil : name,
                durationMinutes: group == "session" ? 300 : (group == "weekly" ? 10_080 : nil),
                usedPercent: percent.doubleValue, resetsAt: resetsAt, isPrimary: kind == "session"
            )
        }
        let windows = order.compactMap { found[$0] }
        guard !windows.isEmpty else {
            throw failure == .noUsage(.claude) ? UsageError.unavailable(.claude) : failure
        }
        return UsageSnapshot(provider: .claude, windows: windows, fetchedAt: now)
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
