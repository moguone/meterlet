import Foundation

public struct UsageClient: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// Try another installation only when authentication failed. Do not hide other errors.
    public func fetch(_ provider: ProviderID, executables: [URL], cancellation: ProbeCancellation) throws -> UsageSnapshot {
        for (index, executable) in executables.enumerated() {
            try cancellation.check()
            do {
                return try fetch(provider, executable: executable, cancellation: cancellation)
            } catch let error as UsageError {
                guard error == .signInRequired(provider), index + 1 < executables.count else { throw error }
            }
        }
        throw UsageError.cliNotFound(provider)
    }

    public func fetch(_ provider: ProviderID, executable: URL, cancellation: ProbeCancellation) throws -> UsageSnapshot {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        switch provider {
        case .codex: return try codex(executable, cancellation: cancellation)
        case .claude: return try claude(executable, cancellation: cancellation)
        }
    }

    private func codex(_ executable: URL, cancellation: ProbeCancellation) throws -> UsageSnapshot {
        let cli = try CLIProcess(executable: executable, arguments: ["app-server"], directory: directory,
                                 environment: CLIResolver.environment(), cancellation: cancellation)
        defer { cli.stop() }
        try cli.sendJSON(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "meterlet", "title": "Meterlet", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"],
        ]])
        var buffer = Data()
        _ = try response(id: 1, cli: cli, buffer: &buffer)
        try cli.sendJSON(["method": "initialized"])
        try cli.sendJSON(["id": 2, "method": "account/rateLimits/read"])
        let result = try response(id: 2, cli: cli, buffer: &buffer)
        return try CodexLimitsParser.parse(result)
    }

    private func response(id: Int, cli: CLIProcess, buffer: inout Data) throws -> Data {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end])
                buffer.removeSubrange(...end)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (object["id"] as? Int) == id else { continue }
                if let error = object["error"] as? [String: Any] {
                    // Never display raw CLI errors: they can contain account identifiers or local paths.
                    let message = (error["message"] as? String ?? "").lowercased()
                    if (error["code"] as? Int) == 401 || UsageError.isAuthenticationFailure(message) {
                        throw UsageError.signInRequired(.codex)
                    }
                    if (error["code"] as? Int) == 429 || UsageError.isRateLimitFailure(message) {
                        throw UsageError.rateLimited(.codex)
                    }
                    throw UsageError.unavailable(.codex)
                }
                guard let result = object["result"], JSONSerialization.isValidJSONObject(result) else {
                    throw UsageError.invalidResponse(.codex)
                }
                return try JSONSerialization.data(withJSONObject: result)
            }
            if let chunk = try cli.read() {
                if chunk.isEmpty { throw UsageError.unavailable(.codex) }
                buffer.append(chunk)
                guard buffer.count < 1_048_576 else { throw UsageError.invalidResponse(.codex) }
            }
        }
        throw UsageError.timedOut(.codex)
    }

    private func claude(_ executable: URL, cancellation: ProbeCancellation) throws -> UsageSnapshot {
        var env = CLIResolver.environment()
        env["TERM"] = "xterm-256color"
        env["NO_COLOR"] = "1"
        env["DISABLE_AUTOUPDATER"] = "1"
        // DISABLE_TELEMETRY also hides the model-scoped rows in /usage, even when inherited.
        env.removeValue(forKey: "DISABLE_TELEMETRY")
        env["DISABLE_ERROR_REPORTING"] = "1"
        env["DISABLE_BUG_COMMAND"] = "1"
        // Essential-traffic mode also blocks the usage API, including when inherited from a shell.
        env.removeValue(forKey: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")
        env.removeValue(forKey: "CLAUDECODE")
        // This viewer targets CLI subscription auth, not API-key billing inherited from a launching shell.
        for key in Array(env.keys) where key.hasPrefix("ANTHROPIC_") || key == "CLAUDE_CODE_OAUTH_TOKEN" {
            env.removeValue(forKey: key)
        }
        try checkClaudeAuth(executable, environment: env, cancellation: cancellation)
        // --settings triggers onboarding; safe mode already disables hooks/MCP.
        // Allow deep-link registration rather than overriding settings.
        let cli = try CLIProcess(executable: executable, arguments: [
            "--safe-mode", "--tools", "", "--strict-mcp-config", "--no-chrome", "--ax-screen-reader",
        ], directory: directory, environment: env, pty: true, cancellation: cancellation)
        defer { cli.stop() }
        let started = Date()
        var data = Data(), lastChange = Date(), sentAt: Date?, confirmedPalette = false
        var trustResponses = 0, usageAttempts = 0
        var lastSnapshot: UsageSnapshot?
        var firstSnapshotAt: Date?
        while Date().timeIntervalSince(started) < 25 {
            if let chunk = try cli.read() {
                if chunk.isEmpty { break }
                data.append(chunk)
                lastChange = Date()
                guard data.count < 1_048_576 else { throw UsageError.invalidResponse(.claude) }
            }
            let text = ClaudeUsageParser.cleanTerminal(String(decoding: data, as: UTF8.self))
            let lower = text.lowercased()
            let failure = ClaudeUsageParser.classifyFailure(text)
            if [.setupRequired(.claude), .signInRequired(.claude), .unsupportedCLI(.claude), .rateLimited(.claude)].contains(failure) {
                throw failure
            }
            if trustResponses < 3 && (text.contains("Yes, I trust this folder") || text.contains("Enter y/n")
                || text.contains("Please answer y or n")) {
                // Only our own empty probe folder is accepted, with hooks/MCP/tools disabled.
                try cli.send(Data("y\r".utf8))
                trustResponses += 1
                // A late trust prompt can consume /usage; retry it only once after accepting.
                sentAt = nil
                confirmedPalette = false
                lastSnapshot = nil
                firstSnapshotAt = nil
                data.removeAll(keepingCapacity: true)
                lastChange = Date()
                continue
            }
            if sentAt == nil && usageAttempts < 2, Date().timeIntervalSince(started) >= 2,
               Date().timeIntervalSince(lastChange) >= 0.8,
               !lower.contains("trust"), !lower.contains("y/n"), !lower.contains("please answer y or n") {
                try cli.send(Data("/usage\r".utf8))
                usageAttempts += 1
                sentAt = Date()
                data.removeAll(keepingCapacity: true)
                continue
            }
            if let sentAt, !confirmedPalette, Date().timeIntervalSince(sentAt) > 1,
               text.contains("Show plan usage"), !text.contains("Current session") {
                try cli.send(Data("\r".utf8))
                confirmedPalette = true
            }
            if sentAt != nil, let snapshot = try? ClaudeUsageParser.parse(text) {
                lastSnapshot = snapshot
                if firstSnapshotAt == nil { firstSnapshotAt = Date() }
            }
            let tail = lower.trimmingCharacters(in: .whitespacesAndNewlines)
            if let snapshot = lastSnapshot, let firstSnapshotAt,
               Date().timeIntervalSince(lastChange) >= 0.8,
               !tail.hasSuffix("loading usage data…"), !tail.hasSuffix("refreshing…"),
               Date().timeIntervalSince(firstSnapshotAt) >= 1.5 || snapshot.windows.contains(where: { $0.scope != nil }) {
                return snapshot
            }
        }
        if let lastSnapshot { return lastSnapshot }
        let failure = ClaudeUsageParser.classifyFailure(String(decoding: data, as: UTF8.self))
        throw failure == .noUsage(.claude) ? UsageError.timedOut(.claude) : failure
    }

    private func checkClaudeAuth(_ executable: URL, environment: [String: String], cancellation: ProbeCancellation) throws {
        let cli = try CLIProcess(executable: executable, arguments: ["auth", "status", "--json"], directory: directory,
                                 environment: environment, cancellation: cancellation)
        defer { cli.stop() }
        let deadline = Date().addingTimeInterval(8)
        var data = Data()
        while Date() < deadline {
            if let chunk = try cli.read() {
                if chunk.isEmpty { break }
                data.append(chunk)
                guard data.count < 65_536 else { throw UsageError.invalidResponse(.claude) }
                if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let loggedIn = result["loggedIn"] as? Bool {
                    guard loggedIn else { throw UsageError.signInRequired(.claude) }
                    if let method = result["authMethod"] as? String, method.lowercased().contains("api") {
                        throw UsageError.noUsage(.claude)
                    }
                    return
                }
            }
        }
        throw UsageError.setupRequired(.claude)
    }
}
