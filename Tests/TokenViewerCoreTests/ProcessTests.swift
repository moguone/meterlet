import Foundation
import Darwin
import Testing
@testable import TokenViewerCore

private func withExecutable(_ script: String, body: (URL, URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("token-viewer-test-\(UUID().uuidString)")
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
