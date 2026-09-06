import Foundation

public enum CodexLimitsParser {
    private struct Response: Decodable {
        var rateLimits: Bucket?
        var rateLimitsByLimitId: [String: Bucket]?
    }
    private struct Bucket: Decodable {
        var limitId: String?
        var limitName: String?
        var primary: Window?
        var secondary: Window?
    }
    private struct Window: Decodable {
        var usedPercent: Double
        var windowDurationMins: Int?
        var resetsAt: Double?
    }

    public static func parse(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw UsageError.invalidResponse(.codex) }
        var buckets = response.rateLimitsByLimitId ?? [:]
        if buckets.isEmpty, let legacy = response.rateLimits {
            buckets[legacy.limitId ?? "codex"] = legacy
        }
        var windows: [UsageWindow] = []
        let keys = buckets.keys.sorted { a, b in
            if (a == "codex") != (b == "codex") { return a == "codex" }
            return a < b
        }
        for key in keys {
            guard let bucket = buckets[key] else { continue }
            for (name, value) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let value, value.usedPercent.isFinite, value.usedPercent >= 0 else { continue }
                let scope = key == "codex" ? nil : (bucket.limitName ?? key)
                windows.append(UsageWindow(
                    id: "\(key).\(name)", scope: scope,
                    durationMinutes: value.windowDurationMins.flatMap { $0 > 0 ? $0 : nil },
                    usedPercent: value.usedPercent,
                    resetsAt: value.resetsAt.flatMap { $0 > 0 && $0.isFinite ? Date(timeIntervalSince1970: $0) : nil },
                    isPrimary: key == "codex" && name == "primary"
                ))
            }
        }
        guard !windows.isEmpty else { throw UsageError.noUsage(.codex) }
        return UsageSnapshot(provider: .codex, windows: windows, fetchedAt: now)
    }
}
