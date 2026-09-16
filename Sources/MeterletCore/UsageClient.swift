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
        let cli = try CLIProcess(executable: executable, arguments: [
            "-p", "/usage", "--output-format", "stream-json", "--verbose", "--no-session-persistence",
            "--strict-mcp-config", "--safe-mode", "--tools", "", "--no-chrome",
        ], directory: directory, environment: env, mergeStandardError: true, nullStandardInput: true,
           cancellation: cancellation)
        defer { cli.stop() }
        let deadline = Date().addingTimeInterval(20)
        var data = Data()
        var lineStart = 0
        while Date() < deadline {
            if let chunk = try cli.read() {
                if chunk.isEmpty { return try ClaudeUsageParser.parse(data) }
                data.append(chunk)
                guard data.count < 1_048_576 else { throw UsageError.invalidResponse(.claude) }
                // A descendant may keep the output pipe open after the final event.
                // Inspect only complete lines, including events split across reads.
                while let end = data[lineStart...].firstIndex(of: 10) {
                    let line = Data(data[lineStart..<end])
                    lineStart = end + 1
                    if let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                       event["type"] as? String == "result" {
                        return try ClaudeUsageParser.parse(data)
                    }
                }
            }
        }
        throw UsageError.timedOut(.claude)
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
