import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex, claude
    public var id: Self { self }
    public var title: String { self == .codex ? "Codex" : "Claude Code" }
    public var usageURL: URL {
        URL(string: self == .codex ? "https://chatgpt.com/codex/settings/usage" : "https://claude.ai/settings/usage")!
    }
}

public struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var scope: String?
    public var durationMinutes: Int?
    public var usedPercent: Double
    public var resetsAt: Date?
    /// Retained only when the official CLI's human-readable reset cannot be parsed.
    public var resetDescription: String?
    public var isPrimary: Bool

    public init(id: String, scope: String? = nil, durationMinutes: Int?, usedPercent: Double,
                resetsAt: Date? = nil, resetDescription: String? = nil, isPrimary: Bool = false) {
        self.id = id
        self.scope = scope
        self.durationMinutes = durationMinutes
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.isPrimary = isPrimary
    }

    public var isFable: Bool { scope?.localizedCaseInsensitiveContains("fable") == true }
    public var fraction: Double { min(1, max(0, usedPercent / 100)) }
    public var percentText: String {
        guard usedPercent.isFinite, usedPercent >= 0 else { return "—" }
        return usedPercent >= 1_000 ? "999+" : "\(Int(usedPercent.rounded()))%"
    }
    public func isExpired(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var provider: ProviderID
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(provider: ProviderID, windows: [UsageWindow], fetchedAt: Date = .now) {
        self.provider = provider
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var primary: UsageWindow? { windows.first(where: \.isPrimary) ?? windows.first }
    public func menuWindow(preferring id: String?) -> UsageWindow? {
        if let id, let selected = windows.first(where: { $0.id == id }) { return selected }
        return windows.first(where: { $0.durationMinutes == 10_080 && $0.scope == nil })
            ?? windows.first(where: { $0.durationMinutes == 10_080 })
            ?? primary
    }
    public func isStale(at now: Date, after interval: TimeInterval = 900) -> Bool {
        now.timeIntervalSince(fetchedAt) >= interval || fetchedAt.timeIntervalSince(now) > 60
    }
    public func menuText(at now: Date, staleAfter: TimeInterval = 900, windowID: String? = nil) -> String {
        guard !isStale(at: now, after: staleAfter), let window = menuWindow(preferring: windowID),
              !window.isExpired(at: now) else { return "—" }
        return window.percentText
    }
}

public enum UsageError: Error, Equatable, Sendable {
    case cliNotFound(ProviderID)
    case signInRequired(ProviderID)
    case setupRequired(ProviderID)
    case unsupportedCLI(ProviderID)
    case timedOut(ProviderID)
    case noUsage(ProviderID)
    case invalidResponse(ProviderID)
    case rateLimited(ProviderID)
    case unavailable(ProviderID)
    case cancelled

    static func isAuthenticationFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return containsHTTPError(401, in: lower)
            || ["not logged in", "not signed in", "not authenticated", "unauthenticated", "unauthorized",
                "authentication required", "authentication failed", "authentication_error",
                "please log in", "please login", "please sign in", "login required", "sign in required",
                "token has expired", "token expired", "invalid access token", "invalid token"].contains(where: lower.contains)
    }

    static func isRateLimitFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return containsHTTPError(429, in: lower) || lower.contains("too many requests")
            || lower.contains("rate limit exceeded") || lower.contains("rate limit reached")
    }

    private static func containsHTTPError(_ status: Int, in text: String) -> Bool {
        // Terminal output also includes version numbers such as 2.1.401 and 2.1.429.
        text.range(of: #"\b(?:http|(?:api\s+)?error|status(?:\s+code)?)\s*[:=]?\s*\#(status)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    public var messageKey: String {
        switch self {
        case .cliNotFound(let provider): provider == .codex ? "error.codexNotFound" : "error.claudeNotFound"
        case .signInRequired(let provider): provider == .claude ? "error.claudeSignIn" : "error.signIn"
        case .setupRequired: "error.setup"
        case .unsupportedCLI: "error.updateCLI"
        case .timedOut: "error.timeout"
        case .noUsage: "error.noUsage"
        case .invalidResponse: "error.invalidResponse"
        case .rateLimited: "error.rateLimited"
        case .unavailable: "error.unavailable"
        case .cancelled: "error.cancelled"
        }
    }
}

public struct RefreshPolicy: Sendable {
    public let interval: TimeInterval
    public init(interval: TimeInterval = 300) { self.interval = max(60, interval) }
    public func delay(failures: Int, lowPower: Bool) -> TimeInterval {
        min(3_600, interval * (lowPower ? 2 : 1) * pow(2, Double(min(max(failures, 0), 4))))
    }
    public var staleAfter: TimeInterval { max(900, interval * 3) }
}
