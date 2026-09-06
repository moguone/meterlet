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
    public func isStale(at now: Date, after interval: TimeInterval = 900) -> Bool {
        now.timeIntervalSince(fetchedAt) >= interval || fetchedAt.timeIntervalSince(now) > 60
    }
    public func menuText(at now: Date, staleAfter: TimeInterval = 900) -> String {
        guard !isStale(at: now, after: staleAfter), let primary, !primary.isExpired(at: now) else { return "—" }
        return primary.percentText
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

    public var messageKey: String {
        switch self {
        case .cliNotFound: "error.cliNotFound"
        case .signInRequired: "error.signIn"
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
