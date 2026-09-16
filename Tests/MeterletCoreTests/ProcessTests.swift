import Foundation
import Darwin
import Testing
@testable import MeterletCore

private func withExecutable(_ script: String, body: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meterlet-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-cli")
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    try body(executable, directory)
}

@Test func codexClientPerformsOnlyReadHandshake() throws {
    try withExecutable("""
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
        *'"method":"initialized"'*) ;;
        *rateLimits*read*)
          printf '%s\\n' '{"method":"irrelevant/notification","params":{}}'
          printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":28,"windowDurationMins":10080,"resetsAt":2000000000}}}}' ;;
        *) exit 9 ;;
      esac
    done
    """) { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.codex, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 28)
    }
}

@Test func claudeLoggedOutStopsBeforeUsage() throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
      printf '%s\\n' '{"loggedIn":false,"authMethod":"none"}'
    else
      touch should-not-start
      exit 9
    fi
    """) { executable, directory in
        #expect(throws: UsageError.signInRequired(.claude)) {
            try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("should-not-start").path))
    }
}

@Test func codexNullResponseDoesNotCrash() throws {
    try withExecutable("""
    #!/bin/sh
    IFS= read -r line
    printf '%s\\n' '{"id":1,"result":null}'
    """) { executable, directory in
        #expect(throws: UsageError.invalidResponse(.codex)) {
            try UsageClient(directory: directory).fetch(.codex, executable: executable, cancellation: ProbeCancellation())
        }
    }
}

@Test func cancellingProbeTerminatesItsProcessGroup() throws {
    try withExecutable("""
    #!/bin/sh
    sleep 60 &
    child=$!
    printf '%s\\n' "$child"
    wait
    """) { executable, directory in
        let cancellation = ProbeCancellation()
        let process = try CLIProcess(executable: executable, arguments: [], directory: directory, environment: CLIResolver.environment(), cancellation: cancellation)
        let deadline = Date().addingTimeInterval(3)
        var data = Data()
        while !data.contains(10) && Date() < deadline {
            if let chunk = try process.read() { data.append(chunk) }
        }
        let child = try #require(Int32(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        cancellation.cancel()
        process.stop()
        // SIGTERM stops the child too, not only the wrapper. An adopted zombie may exist briefly.
        let end = Date().addingTimeInterval(2)
        while kill(child, 0) == 0 && Date() < end { usleep(10_000) }
        #expect(kill(child, 0) == -1)
    }
}

private func withClaude(_ output: String, body: (URL, URL) throws -> Void) throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = auth ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    [ "$1" = -p ] || exit 9
    \(output)
    """) { executable, directory in
        let fixture = try #require(Bundle.module.url(forResource: "claude-usage", withExtension: "jsonl", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("usage.jsonl"))
        try body(executable, directory)
    }
}

@Test func claudeClientReturnsStructuredWindows() throws {
    try withClaude("cat usage.jsonl") { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.windows.map(\.usedPercent) == [6, 11, 19])
        #expect(snapshot.primary?.id == "session")
        #expect(snapshot.windows.first(where: \.isFable)?.resetsAt != nil)
    }
}

@Test func claudeClientUsesIsolatedArgumentsAndEnvironment() throws {
    try withClaude("""
    printf '%s\\n' "$@" > args
    IFS= read -r line
    printf 'stdin_eof=%s\\n' "$?" >> args
    printf '%s\\n' \\
      "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY-unset}" \\
      "CLAUDE_CODE_OAUTH_TOKEN=${CLAUDE_CODE_OAUTH_TOKEN-unset}" \\
      "CLAUDECODE=${CLAUDECODE-unset}" \\
      "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-unset}" \\
      "DISABLE_TELEMETRY=${DISABLE_TELEMETRY-unset}" \\
      "DISABLE_ERROR_REPORTING=${DISABLE_ERROR_REPORTING-unset}" \\
      "DISABLE_BUG_COMMAND=${DISABLE_BUG_COMMAND-unset}" \\
      "DISABLE_AUTOUPDATER=${DISABLE_AUTOUPDATER-unset}" \\
      "NO_COLOR=${NO_COLOR-unset}" > environment
    cat usage.jsonl
    """) { executable, directory in
        _ = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        let args = try String(contentsOf: directory.appendingPathComponent("args"), encoding: .utf8)
        #expect(args.components(separatedBy: "\n").dropLast() == [
            "-p", "/usage", "--output-format", "stream-json", "--verbose", "--no-session-persistence",
            "--strict-mcp-config", "--safe-mode", "--tools", "", "--no-chrome", "stdin_eof=1",
        ])
        let environment = try String(contentsOf: directory.appendingPathComponent("environment"), encoding: .utf8)
        #expect(environment == """
        ANTHROPIC_API_KEY=unset
        CLAUDE_CODE_OAUTH_TOKEN=unset
        CLAUDECODE=unset
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=unset
        DISABLE_TELEMETRY=unset
        DISABLE_ERROR_REPORTING=1
        DISABLE_BUG_COMMAND=1
        DISABLE_AUTOUPDATER=1
        NO_COLOR=1

        """)
    }
}

@Test(arguments: [
    (#"printf '%s\n' '{"type":"assistant","message":{"content":[{"text":"Current session: 6% used"}]}}' '{"type":"result","result":"usage"}'"#, UsageError.unsupportedCLI(.claude)),
    (#"printf '%s\n' 'Error: When using --print, --output-format=stream-json requires --verbose' >&2"#, UsageError.noUsage(.claude)),
    (#"printf '%s\n' "error: unknown option '--safe-mode'" >&2"#, UsageError.unsupportedCLI(.claude)),
    (#"printf '%s\n' '{"type":"assistant","usage_report":{"rate_limits":null}}' '{"type":"result","is_error":true,"result":"Failed to load usage data"}'"#, UsageError.unavailable(.claude)),
])
func claudeClientClassifiesFailures(output: String, error: UsageError) throws {
    try withClaude(output) { executable, directory in
        #expect(throws: error) {
            try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        }
    }
}

@Test func claudeClientStopsAtCompleteResultWithoutWaitingForEOF() throws {
    try withClaude("""
    sed '$d' usage.jsonl
    printf '%s' '{"type":"res'
    sleep 0.1
    printf '%s' 'ult","result":"done"}'
    sleep 0.1
    printf '\\n'
    sleep 10 &
    wait
    """) { executable, directory in
        let start = Date()
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.windows.count == 3)
        #expect(Date().timeIntervalSince(start) < 5)
    }
}

@Test func codexPreservesSignInError() throws {
    try withExecutable("""
    #!/bin/sh
    while IFS= read -r line; do
      case "$line" in
        *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
        *rateLimits*read*) printf '%s\\n' '{"id":2,"error":{"code":401,"message":"Not logged in"}}' ;;
      esac
    done
    """) { executable, directory in
        #expect(throws: UsageError.signInRequired(.codex)) {
            try UsageClient(directory: directory).fetch(.codex, executable: executable, cancellation: ProbeCancellation())
        }
    }
}

@Test(arguments: [ProviderID.codex, .claude])
func cancelledProbeDoesNotLaunchCLI(provider: ProviderID) throws {
    try withExecutable("#!/bin/sh\ntouch started\n") { executable, directory in
        let cancellation = ProbeCancellation()
        cancellation.cancel()
        #expect(throws: UsageError.cancelled) {
            try UsageClient(directory: directory).fetch(provider, executable: executable, cancellation: cancellation)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("started").path))
    }
}
