import Foundation
import Testing
@testable import MeterletCore

private let now = ISO8601DateFormatter().date(from: "2026-09-06T05:20:00Z")!
private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

private func fixture(_ file: String) throws -> Data {
    try Data(contentsOf: Bundle.module.url(forResource: file, withExtension: nil, subdirectory: "Fixtures")!)
}

@Test func codexPrefersBucketsAndDoesNotAssumeFiveHours() throws {
    let snapshot = try CodexLimitsParser.parse(fixture("codex.json"), now: now)
    #expect(snapshot.windows.count == 2)
    #expect(snapshot.primary?.usedPercent == 28)
    #expect(snapshot.primary?.durationMinutes == 10080)
    #expect(snapshot.windows.last?.scope == "Codex Spark")
    #expect(snapshot.windows.last?.usedPercent == 0)
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

@Test func claudeParsesScopedLimitsIndependently() throws {
    let snapshot = try ClaudeUsageParser.parse(String(decoding: fixture("claude.txt"), as: UTF8.self), now: now, timeZone: tokyo)
    #expect(snapshot.windows.count == 4)
    #expect(snapshot.primary?.usedPercent == 55)
    #expect(snapshot.windows.first(where: \.isFable)?.usedPercent == 68)
    #expect(snapshot.windows.last?.usedPercent == 20)
    #expect(snapshot.windows.allSatisfy { $0.resetsAt != nil })
    #expect(snapshot.windows[1].resetsAt == snapshot.windows[2].resetsAt)
}

@Test func claudeDoesNotInventFableOrMissingQuota() throws {
    let snapshot = try ClaudeUsageParser.parse("Current session\n0% used\nResets eventually", now: now)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows.first?.usedPercent == 0)
    #expect(snapshot.windows.first?.resetsAt == nil)
    #expect(snapshot.windows.first?.resetDescription == "Resets eventually")
    #expect(!snapshot.windows.contains { $0.isFable })
    #expect(throws: UsageError.noUsage(.claude)) { try ClaudeUsageParser.parse("Current session\nLoading…") }
}

@Test func terminalRepaintsDoNotDuplicateWindows() throws {
    let text = "\u{1b}[32mCurrent session\u{1b}[0m\r\n10% used\nResets 4pm\nCurrent session\n12% used\nResets 4pm\nCurrent session\n"
    let snapshot = try ClaudeUsageParser.parse(text, now: now, timeZone: tokyo)
    #expect(snapshot.windows.count == 1)
    #expect(snapshot.primary?.usedPercent == 12)
}

@Test func claudeErrorsDoNotBecomeZeroUsage() {
    #expect(throws: UsageError.signInRequired(.claude)) { try ClaudeUsageParser.parse("Not logged in") }
    #expect(throws: UsageError.setupRequired(.claude)) { try ClaudeUsageParser.parse("Choose the text style") }
    #expect(throws: UsageError.rateLimited(.claude)) { try ClaudeUsageParser.parse("Error: 429 Too many requests") }
}

@Test func resetDatesRespectTimezoneMidnightAndYearBoundary() {
    #expect(ResetDateParser.parse("Resets 4:30pm (Asia/Tokyo)", now: now)?.timeIntervalSince(now) == 7800)
    #expect(ResetDateParser.parse("Resets 1am (Asia/Tokyo)", now: now)?.timeIntervalSince(now) == 38400)
    #expect(ResetDateParser.parse("Resets tomorrow at 1am (Asia/Tokyo)", now: now)?.timeIntervalSince(now) == 38400)
    let december = ISO8601DateFormatter().date(from: "2026-12-31T10:00:00Z")!
    let january = ResetDateParser.parse("Resets Jan 1 at 4pm (Asia/Tokyo)", now: december)!
    #expect(january == ISO8601DateFormatter().date(from: "2027-01-01T07:00:00Z")!)
    #expect(ResetDateParser.parse("Resets 4pm (Unknown/Timezone)", now: now) == nil)
    #expect(ResetDateParser.parse("Resets Sep 1, 2026 4pm (Asia/Tokyo)", now: now)! < now)
}

@Test func expiredAndStaleDataNeverLooksLive() {
    let window = UsageWindow(id: "session", durationMinutes: 300, usedPercent: 100, resetsAt: now, isPrimary: true)
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
    for key in ["usage.title", "status.fableMissing", "error.signIn", "settings.privacy", "window.weekly"] {
        #expect(L10n(.en).text(key) != key)
        #expect(L10n(.ja).text(key) != key)
        #expect(L10n(.en).text(key) != L10n(.ja).text(key))
    }
    #expect(L10n(.ja).format("settings.minutes", 5) == "5分")
    #expect(L10n(.en).format("window.hours", 24) == "24-hour usage")
}
