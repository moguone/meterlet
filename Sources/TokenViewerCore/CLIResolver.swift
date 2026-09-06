import Foundation

public enum CLIResolver {
    /// GUI apps have a minimal PATH. Resolve common official install locations without starting a login shell.
    public static func resolve(_ provider: ProviderID, override: String = "", environment: [String: String] = ProcessInfo.processInfo.environment,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let fm = FileManager.default
        if !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        let name = provider.rawValue
        var candidates = [
            home.appendingPathComponent(".local/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
        ]
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/\(name)" }
        candidates += [home.appendingPathComponent(".local/share/mise/shims/\(name)").path]
        if provider == .codex {
            candidates += ["/Applications/Codex.app/Contents/Resources/codex",
                           home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path]
        }
        return candidates.first(where: fm.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }

    public static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.local/share/mise/shims", "/usr/bin", "/bin"]
        env["PATH"] = ((env["PATH"] ?? "").split(separator: ":").map(String.init) + additions).joined(separator: ":")
        return env
    }
}
