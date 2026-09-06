import Foundation

public struct UsageClient: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

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
            "clientInfo": ["name": "token_viewer", "title": "Token Viewer", "version": "0.1.0"],
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
                    if message.contains("auth") || message.contains("log in") || message.contains("login") || message.contains("401") {
                        throw UsageError.signInRequired(.codex)
                    }
                    if message.contains("429") || message.contains("too many") { throw UsageError.rateLimited(.codex) }
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
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env.removeValue(forKey: "CLAUDECODE")
        // This viewer targets CLI subscription auth, not API-key billing inherited from a launching shell.
        for key in Array(env.keys) where key.hasPrefix("ANTHROPIC_") || key == "CLAUDE_CODE_OAUTH_TOKEN" {
            env.removeValue(forKey: key)
        }
        try checkClaudeAuth(executable, environment: env, cancellation: cancellation)
        let cli = try CLIProcess(executable: executable, arguments: [
            "--safe-mode", "--tools", "", "--strict-mcp-config", "--no-chrome", "--ax-screen-reader",
            "--settings", "{\"disableDeepLinkRegistration\":\"disable\",\"disableAllHooks\":true}",
        ], directory: directory, environment: env, pty: true, cancellation: cancellation)
        defer { cli.stop() }
        let started = Date()
        var data = Data(), lastChange = Date(), sentAt: Date?, confirmedPalette = false, trusted = false
        var lastSnapshot: UsageSnapshot?
        while Date().timeIntervalSince(started) < 25 {
            if let chunk = try cli.read() {
                if chunk.isEmpty { break }
                data.append(chunk)
                lastChange = Date()
                guard data.count < 1_048_576 else { throw UsageError.invalidResponse(.claude) }
            }
            let text = ClaudeUsageParser.cleanTerminal(String(decoding: data, as: UTF8.self))
            let failure = ClaudeUsageParser.classifyFailure(text)
            if [.setupRequired(.claude), .signInRequired(.claude), .unsupportedCLI(.claude), .rateLimited(.claude)].contains(failure) {
                throw failure
            }
            if !trusted && text.contains("Yes, I trust this folder") {
                // Only our own empty probe folder is accepted, with hooks/MCP/tools disabled.
                try cli.send(Data("\r".utf8))
                trusted = true
                data.removeAll(keepingCapacity: true)
                continue
            }
            if sentAt == nil && Date().timeIntervalSince(started) >= 2 && !text.lowercased().contains("trust") {
                try cli.send(Data("/usage\r".utf8))
                sentAt = Date()
                data.removeAll(keepingCapacity: true)
                continue
            }
            if let sentAt, !confirmedPalette, Date().timeIntervalSince(sentAt) > 1,
               text.contains("Show plan usage"), !text.contains("Current session") {
                try cli.send(Data("\r".utf8))
                confirmedPalette = true
            }
            if sentAt != nil, let snapshot = try? ClaudeUsageParser.parse(text) { lastSnapshot = snapshot }
            if let snapshot = lastSnapshot, Date().timeIntervalSince(lastChange) >= 0.8,
               !text.lowercased().hasSuffix("loading usage data…") {
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
