import AppKit
import Foundation

public enum CLIResolver {
    /// GUI apps have a minimal PATH. Resolve common official install locations without starting a login shell.
    public static func resolve(_ provider: ProviderID, override: String = "", environment: [String: String] = ProcessInfo.processInfo.environment,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        candidates(provider, override: override, environment: environment, home: home).first
    }

    /// At most one installed CLI followed by one desktop runtime. Explicit selection is fixed.
    public static func candidates(_ provider: ProviderID, override: String = "",
                                  environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let fm = FileManager.default
        if !override.isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? [URL(fileURLWithPath: path)] : []
        }
        let name = provider.rawValue
        var candidates = [
            home.appendingPathComponent(".local/bin/\(name)").path,
            "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)",
        ]
        candidates += (environment["PATH"] ?? "").split(separator: ":").map { "\($0)/\(name)" }
        candidates += [home.appendingPathComponent(".local/share/mise/shims/\(name)").path]
        let installed = candidates.first(where: fm.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
        var applications: [URL] = []
        if provider == .codex {
            // Resolve by bundle identifier too: the app may be renamed or installed elsewhere.
            if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") {
                applications.append(registered)
            }
            for directory in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
                applications += ["ChatGPT.app", "Codex.app"].map { directory.appendingPathComponent($0) }
            }
        }
        let desktop = desktopExecutable(provider, home: home, applications: applications)
        var seen = Set<URL>()
        return [installed, desktop].compactMap { $0 }.filter {
            seen.insert($0.resolvingSymlinksInPath().standardizedFileURL).inserted
        }
    }

    /// Desktop runtimes are a fallback; explicit paths and separately installed CLIs keep priority.
    static func desktopExecutable(_ provider: ProviderID, home: URL, applications: [URL]) -> URL? {
        let fm = FileManager.default
        var candidates: [URL]
        switch provider {
        case .codex:
            candidates = applications.map { $0.appendingPathComponent("Contents/Resources/codex") }
        case .claude:
            let directory = home.appendingPathComponent("Library/Application Support/Claude/claude-code")
            let versions = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                        options: .skipsHiddenFiles)) ?? []
            candidates = versions.filter {
                $0.lastPathComponent.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil
            }.sorted {
                $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
            }.map { $0.appendingPathComponent("claude.app/Contents/MacOS/claude") }
            // claude-code-vm contains a different runtime. Never execute it on the host.
        }
        return candidates.first { fm.isExecutableFile(atPath: $0.path) }
    }

    public static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.local/share/mise/shims", "/usr/bin", "/bin"]
        env["PATH"] = ((env["PATH"] ?? "").split(separator: ":").map(String.init) + additions).joined(separator: ":")
        return env
    }
}
