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
          printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":28,"windowDurationMins":300,"resetsAt":2000000000}}}}' ;;
        *) exit 9 ;;
      esac
    done
    """) { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.codex, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 28)
    }
}

@Test func claudeLoggedOutStopsBeforeInteractiveSession() throws {
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

@Test func claudeClientUsesPTYAndReturnsFable() throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = "auth" ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"oauth"}'
      exit 0
    fi
    [ -t 0 ] || exit 7
    printf 'Claude Code ready\\n'
    IFS= read -r command
    case "$command" in *usage*) ;; *) exit 8 ;; esac
    printf '%s\\n' 'Current session' '55% used' 'Resets 4:30pm (Asia/Tokyo)' ''
    printf '%s\\n' 'Current week (all models)' '32% used' 'Resets Sep 11 at 2pm (Asia/Tokyo)' ''
    printf '%s\\n' 'Current week (Fable)' '68% used' 'Resets Sep 11 at 2pm (Asia/Tokyo)'
    IFS= read -r unused
    """) { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 55)
        #expect(snapshot.windows.first { $0.isFable }?.usedPercent == 68)
    }
}

@Test(arguments: [
    "Quick safety check: Is this a project you created or one you trust?\n❯ No, exit\n  Yes, I trust this folder\nEnter y/n:\nEnter to confirm · Esc to cancel",
    "Enter y/n:",
])
func claudeClientAnswersTrustPrompt(prompt: String) throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = "auth" ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    cat prompt.txt
    while IFS= read -r command; do
      printf '%s\\n' "$command" >> commands
      [ "$command" = y ] && break
      printf '%s\\n' 'Please answer y or n.' 'Enter y/n:'
    done
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = /usage ] || exit 8
    cat usage.txt
    IFS= read -r unused
    """) { executable, directory in
        try prompt.write(to: directory.appendingPathComponent("prompt.txt"), atomically: true, encoding: .utf8)
        let fixture = try #require(Bundle.module.url(forResource: "claude", withExtension: "txt", subdirectory: "Fixtures"))
        try FileManager.default.copyItem(at: fixture, to: directory.appendingPathComponent("usage.txt"))
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 55)
        #expect(snapshot.windows.first { $0.isFable }?.usedPercent == 68)
        #expect(try String(contentsOf: directory.appendingPathComponent("commands"), encoding: .utf8) == "y\n/usage\n")
    }
}

@Test(arguments: [false, true])
func claudeClientBoundsTrustRetries(keepsRejecting: Bool) throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = "auth" ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    printf '%s\\n' 'Yes, I trust this folder'
    for attempt in 1 2 3; do
      IFS= read -r command
      printf '%s\\n' "$command" >> commands
      [ "$command" = y ] || exit 8
      if [ "$attempt" -lt 3 ] || [ "\(keepsRejecting)" = true ]; then
        printf '%s\\n' 'Please answer y or n.'
      fi
    done
    if [ "\(keepsRejecting)" = true ]; then
      if IFS= read -r -t 2 command; then
        printf '%s\\n' "$command" >> commands
      fi
      exit 0
    fi
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = /usage ] || exit 8
    printf '%s\\n' 'Current session' '55% used' 'Resets 4:30pm (Asia/Tokyo)'
    IFS= read -r unused
    """) { executable, directory in
        let client = UsageClient(directory: directory)
        if keepsRejecting {
            #expect(throws: UsageError.timedOut(.claude)) {
                try client.fetch(.claude, executable: executable, cancellation: ProbeCancellation())
            }
        } else {
            let snapshot = try client.fetch(.claude, executable: executable, cancellation: ProbeCancellation())
            #expect(snapshot.primary?.usedPercent == 55)
        }
        let commands = try String(contentsOf: directory.appendingPathComponent("commands"), encoding: .utf8)
        #expect(commands == (keepsRejecting ? "y\ny\ny\n" : "y\ny\ny\n/usage\n"))
    }
}

@Test func claudeClientWaitsForStartupOutputToSettle() throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = "auth" ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    for step in 1 2 3 4 5 6 7 8; do
      printf '%s\\n' 'Starting Claude Code...'
      sleep 0.4
    done
    printf '%s\\n' 'Yes, I trust this folder' 'Enter y/n:'
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = y ] || exit 8
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = /usage ] || exit 8
    printf '%s\\n' 'Current session' '55% used' 'Resets 4:30pm (Asia/Tokyo)'
    IFS= read -r unused
    """) { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 55)
        #expect(try String(contentsOf: directory.appendingPathComponent("commands"), encoding: .utf8) == "y\n/usage\n")
    }
}

@Test(arguments: [false, true])
func claudeClientResendsUsageOnceAfterLateTrustPrompt(repeatsPrompt: Bool) throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = "auth" ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    printf '%s\\n' 'Starting Claude Code...'
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = /usage ] || exit 8
    sleep 1.4
    printf '%s\\n' 'Yes, I trust this folder' 'Enter y/n:'
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = y ] || exit 8
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ "$command" = /usage ] || exit 8
    if [ "\(repeatsPrompt)" = true ]; then
      printf '%s\\n' 'Yes, I trust this folder' 'Enter y/n:'
      IFS= read -r command
      printf '%s\\n' "$command" >> commands
      [ "$command" = y ] || exit 8
      if IFS= read -r -t 2 command; then
        printf '%s\\n' "$command" >> commands
      fi
      exit 0
    fi
    printf '%s\\n' 'Show plan usage'
    IFS= read -r command
    printf '%s\\n' "$command" >> commands
    [ -z "$command" ] || exit 8
    printf '%s\\n' 'Current session' '55% used' 'Resets 4:30pm (Asia/Tokyo)'
    IFS= read -r unused
    """) { executable, directory in
        let client = UsageClient(directory: directory)
        if repeatsPrompt {
            #expect(throws: UsageError.timedOut(.claude)) {
                try client.fetch(.claude, executable: executable, cancellation: ProbeCancellation())
            }
        } else {
            let snapshot = try client.fetch(.claude, executable: executable, cancellation: ProbeCancellation())
            #expect(snapshot.primary?.usedPercent == 55)
        }
        let commands = try String(contentsOf: directory.appendingPathComponent("commands"), encoding: .utf8)
        #expect(commands == (repeatsPrompt ? "/usage\ny\n/usage\ny\n" : "/usage\ny\n/usage\n\n"))
    }
}

@Test func claudeClientUsesIsolatedArgumentsAndEnvironment() throws {
    try withExecutable("""
    #!/bin/sh
    mode=interactive
    [ "$1" != auth ] || mode=auth
    printf '%s\\n' "$@" > "$mode-arguments"
    printf '%s\\n' \\
      "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC-unset}" \\
      "DISABLE_TELEMETRY=${DISABLE_TELEMETRY-unset}" \\
      "DISABLE_ERROR_REPORTING=${DISABLE_ERROR_REPORTING-unset}" \\
      "DISABLE_BUG_COMMAND=${DISABLE_BUG_COMMAND-unset}" \\
      "DISABLE_AUTOUPDATER=${DISABLE_AUTOUPDATER-unset}" > "$mode-environment"
    if [ "$mode" = auth ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    printf '%s\\n' 'Claude Code ready'
    IFS= read -r command
    [ "$command" = /usage ] || exit 8
    printf '%s\\n' 'Current session' '55% used' 'Resets 4:30pm (Asia/Tokyo)'
    IFS= read -r unused
    """) { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 55)
        let authArguments = try String(contentsOf: directory.appendingPathComponent("auth-arguments"), encoding: .utf8)
        #expect(authArguments == "auth\nstatus\n--json\n")
        let arguments = try String(contentsOf: directory.appendingPathComponent("interactive-arguments"), encoding: .utf8)
            .components(separatedBy: "\n").dropLast()
        #expect(Array(arguments) == ["--safe-mode", "--tools", "", "--strict-mcp-config", "--no-chrome", "--ax-screen-reader"])
        for mode in ["auth", "interactive"] {
            let environment = try String(contentsOf: directory.appendingPathComponent("\(mode)-environment"), encoding: .utf8)
            #expect(environment == """
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=unset
            DISABLE_TELEMETRY=unset
            DISABLE_ERROR_REPORTING=1
            DISABLE_BUG_COMMAND=1
            DISABLE_AUTOUPDATER=1

            """)
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

@Test(arguments: [false, true])
func claudeClientWaitsForDelayedModelRows(includesFable: Bool) throws {
    try withExecutable("""
    #!/bin/sh
    if [ "$1" = auth ]; then
      printf '%s\\n' '{"loggedIn":true,"authMethod":"claude.ai"}'
      exit 0
    fi
    printf '%s\\n' 'Claude Code ready'
    IFS= read -r command
    [ "$command" = /usage ] || exit 8
    touch first-snapshot
    printf '%s\\n' 'Current session' '55% used' 'Resets 4:30pm (Asia/Tokyo)'
    printf '%s\\n' 'Current week (all models)' '32% used' 'Resets Sep 11 at 2pm (Asia/Tokyo)'
    if [ "\(includesFable)" = true ]; then
      printf '%s\\n' 'Refreshing…'
      sleep 1.0
      printf '\\033[2J\\033[H'
      printf '%s\\n' 'Current session' '56% used' 'Resets 4:30pm (Asia/Tokyo)'
      printf '%s\\n' 'Current week (all models)' '33% used' 'Resets Sep 11 at 2pm (Asia/Tokyo)'
      printf '%s\\n' 'Current week (Fable)' '68% used' 'Resets Sep 11 at 2pm (Asia/Tokyo)'
    fi
    IFS= read -r unused
    """) { executable, directory in
        let snapshot = try UsageClient(directory: directory).fetch(.claude, executable: executable, cancellation: ProbeCancellation())
        #expect(snapshot.windows.count == (includesFable ? 3 : 2))
        #expect(snapshot.primary?.usedPercent == (includesFable ? 56 : 55))
        #expect(snapshot.windows.allSatisfy { $0.resetsAt != nil })
        if includesFable {
            #expect(snapshot.windows.first { $0.id == "weekly.fable" }?.usedPercent == 68)
        } else {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("first-snapshot").path)
            let firstOutput = try #require(attributes[.modificationDate] as? Date)
            #expect(Date().timeIntervalSince(firstOutput) >= 1.5)
            #expect(Date().timeIntervalSince(firstOutput) < 5)
        }
    }
}
