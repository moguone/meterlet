import Foundation
import Testing
@testable import MeterletCore

private enum StubResult { case success, signedOut, expired, unavailable, rateLimited }

private func withProbes(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meterlet-fallback-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}

private func probe(_ provider: ProviderID, name: String, result: StubResult, directory: URL) throws -> URL {
    let value = name == "cli" ? 17 : 42
    let script: String
    if provider == .codex {
        let response: String
        switch result {
        case .success:
            response = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":\#(value),"windowDurationMins":300}}}}"#
        case .signedOut: response = #"{"id":2,"error":{"code":-32000,"message":"Not logged in"}}"#
        case .expired: response = #"{"id":2,"error":{"code":401,"message":"Token expired"}}"#
        case .unavailable: response = #"{"id":2,"error":{"code":500,"message":"Authentication service unavailable"}}"#
        case .rateLimited: response = #"{"id":2,"error":{"code":429,"message":"429 Too many requests"}}"#
        }
        script = """
        #!/bin/sh
        printf '%s\\n' '\(name)' >> attempts
        while IFS= read -r line; do
          case "$line" in
            *'"method":"initialize"'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
            *'"method":"initialized"'*) ;;
            *rateLimits*read*) printf '%s\\n' '\(response)' ;;
            *) exit 9 ;;
          esac
        done
        """
    } else {
        let loggedIn = result != .signedOut
        let output: String
        switch result {
        case .success:
            output = """
            printf '%s\\n' 'Claude Code v2.1.401 (engine v2.1.429)'
            IFS= read -r command
            case "$command" in *usage*) ;; *) exit 8 ;; esac
            printf '%s\\n' 'Current session' '\(value)% used' 'Resets 4pm (Asia/Tokyo)'
            IFS= read -r unused
            """
        case .expired: output = "printf '%s\\n' 'API Error: 401 authentication_error'"
        case .unavailable: output = "printf '%s\\n' 'Error fetching usage: network unavailable'"
        case .rateLimited: output = "printf '%s\\n' '429 Too many requests'"
        case .signedOut: output = "exit 9"
        }
        script = """
        #!/bin/sh
        if [ "$1" = "auth" ]; then
          printf '%s\\n' '\(name)' >> attempts
          printf '%s\\n' '{"loggedIn":\(loggedIn),"authMethod":"oauth"}'
          exit 0
        fi
        [ -t 0 ] || exit 7
        \(output)
        """
    }
    let path = directory.appendingPathComponent(name)
    try script.write(to: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path.path)
    return path
}

private func attempts(_ directory: URL) throws -> [String] {
    try String(contentsOf: directory.appendingPathComponent("attempts"), encoding: .utf8)
        .split(separator: "\n").map(String.init)
}

@Test(arguments: [ProviderID.codex, .claude])
func authenticatedCLIDoesNotStartDesktop(_ provider: ProviderID) throws {
    try withProbes { directory in
        let cli = try probe(provider, name: "cli", result: .success, directory: directory)
        let desktop = try probe(provider, name: "desktop", result: .success, directory: directory)
        let snapshot = try UsageClient(directory: directory).fetch(provider, executables: [cli, desktop], cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 17)
        #expect(try attempts(directory) == ["cli"])
    }
}

@Test(arguments: [ProviderID.codex, .claude], [StubResult.signedOut, .expired])
private func authenticationFailureFallsBackToDesktop(_ provider: ProviderID, _ result: StubResult) throws {
    try withProbes { directory in
        let cli = try probe(provider, name: "cli", result: result, directory: directory)
        let desktop = try probe(provider, name: "desktop", result: .success, directory: directory)
        let snapshot = try UsageClient(directory: directory).fetch(provider, executables: [cli, desktop], cancellation: ProbeCancellation())
        #expect(snapshot.primary?.usedPercent == 42)
        #expect(try attempts(directory) == ["cli", "desktop"])
    }
}

@Test(arguments: [ProviderID.codex, .claude])
func bothInstallationsSignedOutReturnAuthenticationError(_ provider: ProviderID) throws {
    try withProbes { directory in
        let cli = try probe(provider, name: "cli", result: .signedOut, directory: directory)
        let desktop = try probe(provider, name: "desktop", result: .signedOut, directory: directory)
        #expect(throws: UsageError.signInRequired(provider)) {
            try UsageClient(directory: directory).fetch(provider, executables: [cli, desktop], cancellation: ProbeCancellation())
        }
        #expect(try attempts(directory) == ["cli", "desktop"])
    }
}

@Test(arguments: [ProviderID.codex, .claude], [StubResult.unavailable, .rateLimited])
private func otherErrorsNeverTryAnotherInstallation(_ provider: ProviderID, _ result: StubResult) throws {
    try withProbes { directory in
        let cli = try probe(provider, name: "cli", result: result, directory: directory)
        let desktop = try probe(provider, name: "desktop", result: .success, directory: directory)
        #expect(throws: result == .unavailable ? UsageError.unavailable(provider) : .rateLimited(provider)) {
            try UsageClient(directory: directory).fetch(provider, executables: [cli, desktop], cancellation: ProbeCancellation())
        }
        #expect(try attempts(directory) == ["cli"])
    }
}

@Test func unavailableDesktopPreservesTheCLISignInError() throws {
    try withProbes { directory in
        let cli = try probe(.codex, name: "cli", result: .signedOut, directory: directory)
        #expect(throws: UsageError.signInRequired(.codex)) {
            try UsageClient(directory: directory).fetch(.codex, executables: [cli], cancellation: ProbeCancellation())
        }
        #expect(try attempts(directory) == ["cli"])
    }
}

@Test func cancellingBeforeFallbackCheckDoesNotLaunchEitherCandidate() throws {
    try withProbes { directory in
        let cli = try probe(.codex, name: "cli", result: .signedOut, directory: directory)
        let desktop = try probe(.codex, name: "desktop", result: .success, directory: directory)
        let cancellation = ProbeCancellation()
        cancellation.cancel()
        #expect(throws: UsageError.cancelled) {
            try UsageClient(directory: directory).fetch(.codex, executables: [cli, desktop], cancellation: cancellation)
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("attempts").path))
    }
}
