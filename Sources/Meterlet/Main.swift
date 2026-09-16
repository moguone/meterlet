import AppKit
import SwiftUI
import MeterletCore

@main
enum MeterletMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--probe"), args.indices.contains(index + 1),
           let provider = ProviderID(rawValue: args[index + 1]) {
            probe(provider)
            return
        }
        if !args.contains("--render-preview"), let bundleID = Bundle.main.bundleIdentifier {
            let current = NSRunningApplication.current
            let first = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).min { left, right in
                let lhs = left.launchDate ?? .distantPast
                let rhs = right.launchDate ?? .distantPast
                return lhs == rhs ? left.processIdentifier < right.processIdentifier : lhs < rhs
            }
            if let first, first.processIdentifier != current.processIdentifier {
                first.activate(options: [])
                return
            }
        }
        let language: AppLanguage? = args.firstIndex(of: "--language").flatMap { index in
            args.indices.contains(index + 1) ? AppLanguage(rawValue: args[index + 1]) : nil
        }
        let app = NSApplication.shared
        if args.contains("--dark") { app.appearance = NSAppearance(named: .darkAqua) }
        if args.contains("--light") { app.appearance = NSAppearance(named: .aqua) }
        let renderDirectory = args.firstIndex(of: "--render-preview").flatMap { index in
            args.indices.contains(index + 1) ? URL(fileURLWithPath: args[index + 1]) : nil
        }
        let delegate = AppDelegate(demo: args.contains("--demo") || renderDirectory != nil, language: language, renderDirectory: renderDirectory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    private static func probe(_ provider: ProviderID) {
        let cancellation = ProbeCancellation()
        do {
            guard let executable = CLIResolver.resolve(provider) else { throw UsageError.cliNotFound(provider) }
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Meterlet/Probes/\(provider.rawValue)")
            let snapshot = try UsageClient(directory: root).fetch(provider, executable: executable, cancellation: cancellation)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        } catch let error as UsageError {
            print("\(provider.title): \(L10n(.en).text(error.messageKey))")
            exit(1)
        } catch {
            print("\(provider.title): \(L10n(.en).text("error.unavailable"))")
            exit(1)
        }
    }
}
