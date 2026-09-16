import Foundation
import Testing
@testable import MeterletCore

private let now = ISO8601DateFormatter().date(from: "2026-09-06T05:20:00Z")!

private func fixture(_ file: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures")!)
}

@Test func codexPrefersWeeklyBucketOverLegacyLimits() throws {
    let snapshot = try CodexLimitsParser.parse(fixture("codex.json"), now: now)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.primary?.usedPercent == 28)
    #expect(snapshot.primary?.durationMinutes == 10080)
    #expect(snapshot.windows.first?.id == "codex.primary")
    #expect(L10n(.en).windowTitle(snapshot.primary!) == "Weekly usage")
}

@Test func codexFallbackAndMissingValues() throws {
    let data = Data(#"{"rateLimits":{"primary":{"usedPercent":0,"resetsAt":null,"windowDurationMins":null}},"rateLimitsByLimitId":null}"#.utf8)
    let snapshot = try CodexLimitsParser.parse(data)
    #expect(snapshot.primary?.percentText == "0%")
    #expect(snapshot.primary?.resetsAt == nil)
    #expect(throws: UsageError.noUsage(.codex)) {
        try CodexLimitsParser.parse(Data(#"{"rateLimits":{"primary":null}}"#.utf8))
    }
    #expect(throws: UsageError.invalidResponse(.codex)) { try CodexLimitsParser.parse(Data("bad".utf8)) }
}

@Test func expiredAndStaleDataNeverLooksLive() {
    let window = UsageWindow(id: "codex.primary", durationMinutes: 10_080, usedPercent: 100, resetsAt: now, isPrimary: true)
    var snapshot = UsageSnapshot(provider: .codex, windows: [window], fetchedAt: now)
    #expect(snapshot.menuText(at: now) == "—")
    snapshot.windows[0].resetsAt = now.addingTimeInterval(10000)
    #expect(snapshot.menuText(at: now) == "100%")
    #expect(snapshot.menuText(at: now.addingTimeInterval(900)) == "—")
    #expect(L10n(.ja).countdown(to: now, now: now) == "最新の使用量を確認中")
}

@Test func refreshBackoffIsBoundedAndPowerAware() {
    let policy = RefreshPolicy()
    #expect(policy.delay(failures: 0, lowPower: false) == 300)
    #expect(policy.delay(failures: 0, lowPower: true) == 600)
    #expect(policy.delay(failures: 1, lowPower: false) == 600)
    #expect(policy.delay(failures: 100, lowPower: true) == 3600)
}

@Test func cachePersistsOnlyNormalizedUsageAndPreservesAge() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = SnapshotCache(directory: directory)
    let snapshot = try CodexLimitsParser.parse(fixture("codex.json"), now: now)
    try cache.save(snapshot)
    #expect(cache.load(.codex) == snapshot)
    #expect(cache.load(.claude) == nil)
    let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("codex.json").path)
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
}

@Test func languagesHaveMatchingTranslations() {
    for key in ["settings.menuWindow", "settings.menu", "usage.title", "status.fableMissing", "error.signIn", "settings.privacy", "window.weekly", "error.codexNotFound", "error.claudeNotFound", "error.claudeSignIn", "error.updateCLI"] {
        #expect(L10n(.en).text(key) != key)
        #expect(L10n(.ja).text(key) != key)
        #expect(L10n(.en).text(key) != L10n(.ja).text(key))
    }
    #expect(L10n(.ja).format("settings.minutes", 5) == "5分")
    #expect(L10n(.en).format("window.hours", 24) == "24-hour usage")
}

@Test func codexExcludesSparkByIDOrNameAndKeepsOtherBuckets() throws {
    let data = Data(#"{"rateLimitsByLimitId":{"codex_sPaRk":{"primary":{"usedPercent":1}},"other":{"limitName":"Codex SPARK","primary":{"usedPercent":2}},"alias":{"limitId":"SPARK_preview","primary":{"usedPercent":3}},"future":{"limitName":"Future","primary":{"usedPercent":4}}}}"#.utf8)
    let snapshot = try CodexLimitsParser.parse(data)
    #expect(snapshot.windows.map(\.id) == ["future.primary"])
    #expect(snapshot.windows.first?.scope == "Future")
}

@Test func menuWindowDefaultsToWeeklyAndRespectsProviderSelection() throws {
    let claude = try ClaudeUsageParser.parse(fixture("claude-usage.jsonl"), now: now)
    #expect(claude.primary?.id == "session")
    #expect(claude.menuWindow(preferring: nil)?.id == "weekly")
    #expect(claude.menuWindow(preferring: "session")?.id == "session")
    #expect(claude.menuWindow(preferring: "weekly.fable")?.id == "weekly.fable")
    #expect(claude.menuWindow(preferring: "missing")?.id == "weekly")
    #expect(claude.menuText(at: now) == "11%")
    #expect(claude.menuText(at: now, windowID: "session") == "6%")
    #expect(claude.menuText(at: now, windowID: "weekly.fable") == "19%")
    #expect(claude.menuText(at: now, windowID: "missing") == "11%")
    let codex = try CodexLimitsParser.parse(fixture("codex.json"), now: now)
    #expect(codex.menuWindow(preferring: nil)?.id == "codex.primary")
    #expect(codex.menuText(at: now) == "28%")
}

@Test func menuWindowFallbacksAndExpiryUseTheSelectedWindow() {
    let session = UsageWindow(id: "session", durationMinutes: 300, usedPercent: 10, isPrimary: true)
    let scoped = UsageWindow(id: "weekly.fable", scope: "Fable", durationMinutes: 10_080, usedPercent: 20)
    let weekly = UsageWindow(id: "weekly", durationMinutes: 10_080, usedPercent: 30, resetsAt: now)
    var snapshot = UsageSnapshot(provider: .claude, windows: [session, scoped, weekly], fetchedAt: now)
    #expect(snapshot.menuWindow(preferring: nil)?.id == "weekly")
    #expect(snapshot.menuText(at: now) == "—")
    #expect(snapshot.menuText(at: now, windowID: "session") == "10%")
    #expect(snapshot.menuText(at: now.addingTimeInterval(900), windowID: "session") == "—")
    snapshot.windows.removeLast()
    #expect(snapshot.menuWindow(preferring: "missing")?.id == "weekly.fable")
    snapshot.windows.removeLast()
    #expect(snapshot.menuWindow(preferring: nil)?.id == "session")
    snapshot.windows.removeAll()
    #expect(snapshot.menuWindow(preferring: nil) == nil)
    #expect(snapshot.menuText(at: now) == "—")
}

@Test func claudeParsesStructuredLimits() throws {
    let snapshot = try ClaudeUsageParser.parse(fixture("claude-usage.jsonl"), now: now)
    #expect(snapshot.fetchedAt == now)
    #expect(snapshot.windows.map(\.id) == ["session", "weekly", "weekly.fable"])
    #expect(snapshot.windows.map(\.scope) == [nil, nil, "Fable"])
    #expect(snapshot.windows.map(\.durationMinutes) == [300, 10080, 10080])
    #expect(snapshot.windows.map(\.usedPercent) == [6, 11, 19])
    #expect(snapshot.windows.map(\.isPrimary) == [true, false, false])
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    #expect(snapshot.windows.map(\.resetsAt) == [
        "2026-09-16T19:00:00.661315+00:00", "2026-09-20T08:00:00.661340+00:00", "2026-09-20T08:00:00.661585+00:00",
    ].map { formatter.date(from: $0) })
    #expect(snapshot.windows.allSatisfy { $0.resetDescription == nil })
}

private func structuredUsage(_ limits: String) -> Data {
    Data(#"{"type":"assistant","usage_report":{"rate_limits":{"limits":\#(limits.replacingOccurrences(of: "\n", with: ""))}}}"#.utf8)
}

@Test func claudeKeepsUnknownKindsAndOptionalDates() throws {
    let snapshot = try ClaudeUsageParser.parse(structuredUsage("""
    [
      {"kind":"monthly_all","group":"monthly","percent":3,"resets_at":null},
      {"kind":"monthly_scoped","group":"monthly","percent":4,"scope":{"model":{"display_name":"Future"}},"resets_at":"bad"},
      {"kind":"weekly_scoped","group":"weekly","percent":5,"scope":{"model":{"display_name":""}},"resets_at":"2026-09-20T08:00:00Z"}
    ]
    """))
    #expect(snapshot.windows.map(\.id) == ["monthly_all", "monthly_scoped.future", "weekly.scoped"])
    #expect(snapshot.windows.map(\.durationMinutes) == [nil, nil, 10080])
    #expect(snapshot.windows.map(\.resetsAt) == [nil, nil, ISO8601DateFormatter().date(from: "2026-09-20T08:00:00Z")])
    #expect(!snapshot.windows.contains { $0.isFable })
}

@Test func claudeUsesLastReportAndLastDuplicateInFirstSeenOrder() throws {
    var data = try fixture("claude-usage.jsonl")
    data.append(structuredUsage("""
    [
      {"kind":"weekly_all","group":"weekly","percent":1,"scope":{"model":{"display_name":"ignored"}}},
      {"kind":"session","group":"session","percent":2},
      {"kind":"weekly_all","group":"weekly","percent":3},
      {"kind":"weekly_scoped","group":"weekly","percent":"19"},
      {"kind":"weekly_scoped","group":"weekly","percent":true}
    ]
    """.replacingOccurrences(of: "\n", with: "")))
    let snapshot = try ClaudeUsageParser.parse(data)
    #expect(snapshot.windows.map(\.id) == ["weekly", "session"])
    #expect(snapshot.windows.map(\.usedPercent) == [3, 2])
    #expect(snapshot.windows.first?.scope == nil)
}

@Test(arguments: ["[]", #"[{"kind":"session","percent":"invalid"}]"#])
func claudeMissingLimitsAreUnavailable(limits: String) throws {
    let data = structuredUsage(limits)
    #expect(throws: UsageError.unavailable(.claude)) { try ClaudeUsageParser.parse(data) }
    var withError = data
    withError.append(Data("\n".utf8))
    withError.append(Data(#"{"type":"result","result":"Failed to load usage data","is_error":true}"#.utf8))
    #expect(throws: UsageError.unavailable(.claude)) { try ClaudeUsageParser.parse(withError) }
}

@Test func claudeIgnoresNonJSONNoiseAndInitMetadata() throws {
    var data = Data("arbitrary hook output\n".utf8)
    data.append(try fixture("claude-usage.jsonl"))
    #expect(try ClaudeUsageParser.parse(data).windows.count == 3)
    let initOnly = Data(#"{"type":"system","slash_commands":["not logged in","unknown option"],"cwd":"/error fetching"}"#.utf8)
    #expect(throws: UsageError.noUsage(.claude)) { try ClaudeUsageParser.parse(initOnly) }
    var oldCLI = initOnly
    oldCLI.append(Data("\n{\"type\":\"assistant\"}".utf8))
    #expect(throws: UsageError.unsupportedCLI(.claude)) { try ClaudeUsageParser.parse(oldCLI) }
}

@Test(arguments: [
    ("Not logged in", UsageError.signInRequired(.claude)),
    ("Choose the text style", UsageError.setupRequired(.claude)),
    ("Error: 429 Too many requests", UsageError.rateLimited(.claude)),
    ("error: unknown option", UsageError.unsupportedCLI(.claude)),
    ("Failed to load usage data", UsageError.unavailable(.claude)),
])
func claudeErrorsDoNotBecomeZeroUsage(text: String, error: UsageError) throws {
    #expect(throws: error) { try ClaudeUsageParser.parse(Data(text.utf8)) }
    let result = try JSONSerialization.data(withJSONObject: ["type": "result", "is_error": true, "result": text] as [String: Any])
    #expect(throws: error) { try ClaudeUsageParser.parse(result) }
    let assistant = try JSONSerialization.data(withJSONObject: ["type": "assistant", "message": ["content": [["text": text]]]])
    #expect(throws: error) { try ClaudeUsageParser.parse(assistant) }
}
