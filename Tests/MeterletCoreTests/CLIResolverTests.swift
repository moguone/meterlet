import Foundation
import Testing
@testable import MeterletCore

private func withHome(_ body: (URL) throws -> Void) throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("meterlet-resolver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try body(home)
}

private func executable(_ url: URL, mode: Int = 0o700) throws -> URL {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    return url
}

@Test func findsCodexInsideCurrentLegacyAndRelocatedDesktopApps() throws {
    try withHome { home in
        for name in ["ChatGPT.app", "Codex.app", "Custom Folder/My Desktop.app"] {
            let app = home.appendingPathComponent(name)
            let cli = try executable(app.appendingPathComponent("Contents/Resources/codex"))
            #expect(CLIResolver.desktopExecutable(.codex, home: home, applications: [app]) == cli)
        }
        #expect(CLIResolver.desktopExecutable(.codex, home: home, applications: [home.appendingPathComponent("Missing.app")]) == nil)
    }
}

@Test func claudeDesktopChoosesLatestUsableNativeRuntime() throws {
    try withHome { home in
        let root = home.appendingPathComponent("Library/Application Support/Claude")
        _ = try executable(root.appendingPathComponent("claude-code/2.1.9/claude.app/Contents/MacOS/claude"))
        let latest = try executable(root.appendingPathComponent("claude-code/2.1.10/claude.app/Contents/MacOS/claude"))
        _ = try executable(root.appendingPathComponent("claude-code/2.1.11/claude.app/Contents/MacOS/claude"), mode: 0o600)
        _ = try executable(root.appendingPathComponent("claude-code/999.0.0.tmp/claude.app/Contents/MacOS/claude"))
        _ = try executable(root.appendingPathComponent("claude-code-vm/999.0.0/claude"))
        #expect(CLIResolver.desktopExecutable(.claude, home: home, applications: [])?.resolvingSymlinksInPath() == latest.resolvingSymlinksInPath())
        try FileManager.default.removeItem(at: root.appendingPathComponent("claude-code"))
        #expect(CLIResolver.desktopExecutable(.claude, home: home, applications: []) == nil)
    }
}

@Test func explicitCLISelectionNeverSilentlyFallsBack() throws {
    try withHome { home in
        let cli = try executable(home.appendingPathComponent("Selected CLI"))
        #expect(CLIResolver.candidates(.codex, override: cli.path, home: home) == [cli])
        #expect(CLIResolver.candidates(.claude, override: home.appendingPathComponent("missing").path, home: home).isEmpty)
    }
}

@Test func separatelyInstalledCLIStillWins() throws {
    try withHome { home in
        let cli = try executable(home.appendingPathComponent(".local/bin/codex"))
        _ = try executable(home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"))
        #expect(CLIResolver.resolve(.codex, environment: ["PATH": ""], home: home) == cli)
    }
}

@Test func authenticationCandidatesAreOrderedAndDoNotRepeatSymlinkTargets() throws {
    try withHome { home in
        let cli = try executable(home.appendingPathComponent(".local/bin/claude"))
        let desktop = try executable(home.appendingPathComponent("Library/Application Support/Claude/claude-code/2.1.237/claude.app/Contents/MacOS/claude"))
        let candidates = CLIResolver.candidates(.claude, environment: ["PATH": ""], home: home)
        #expect(candidates.map { $0.resolvingSymlinksInPath() } == [cli, desktop].map { $0.resolvingSymlinksInPath() })
        try FileManager.default.removeItem(at: cli)
        try FileManager.default.createSymbolicLink(at: cli, withDestinationURL: desktop)
        #expect(CLIResolver.candidates(.claude, environment: ["PATH": ""], home: home) == [cli])
    }
}
