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

@Test func explicitCLISelectionNeverSilentlyFallsBack() throws {
    try withHome { home in
        let cli = try executable(home.appendingPathComponent("Selected CLI"))
        _ = try executable(home.appendingPathComponent(".local/bin/codex"))
        #expect(CLIResolver.resolve(.codex, override: cli.path, home: home, systemDirectories: []) == cli)
        #expect(CLIResolver.resolve(.codex, override: home.appendingPathComponent("missing").path, home: home, systemDirectories: []) == nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cli.path)
        #expect(CLIResolver.resolve(.codex, override: cli.path, home: home, systemDirectories: []) == nil)
    }
}

@Test func localBinPrecedesPathAndPathPrecedesShims() throws {
    try withHome { home in
        let local = try executable(home.appendingPathComponent(".local/bin/claude"))
        let path = try executable(home.appendingPathComponent("path/claude"))
        let shim = try executable(home.appendingPathComponent(".local/share/mise/shims/claude"))
        let env = ["PATH": path.deletingLastPathComponent().path]
        #expect(CLIResolver.resolve(.claude, environment: env, home: home, systemDirectories: []) == local)
        try FileManager.default.removeItem(at: local)
        #expect(CLIResolver.resolve(.claude, environment: env, home: home, systemDirectories: []) == path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        #expect(CLIResolver.resolve(.claude, environment: env, home: home, systemDirectories: []) == shim)
        try FileManager.default.removeItem(at: shim)
        #expect(CLIResolver.resolve(.claude, environment: env, home: home, systemDirectories: []) == nil)
    }
}
