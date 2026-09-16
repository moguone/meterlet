import AppKit
import Combine
import MeterletCore

struct ProviderState {
    var snapshot: UsageSnapshot?
    var error: UsageError?
    var loading = false
    var restored = false
    var failures = 0
    var nextFetch = Date.distantPast
    var lastAttempt = Date.distantPast
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var states: [ProviderID: ProviderState] = [:]
    @Published var now = Date()
    @Published var panelVisible = false
    @Published var language: AppLanguage { didSet { if !demo { defaults.set(language.rawValue, forKey: "language") } } }
    @Published var refreshMinutes: Int { didSet { if !demo { defaults.set(refreshMinutes, forKey: "refreshMinutes") }; reschedulePreferences() } }
    @Published var codexEnabled: Bool { didSet { saveEnabled(.codex, codexEnabled) } }
    @Published var claudeEnabled: Bool { didSet { saveEnabled(.claude, claudeEnabled) } }
    @Published var paths: [String: String] { didSet { if !demo { defaults.set(paths, forKey: "cliPaths") }; invalidate() } }
    @Published var menuWindowIDs: [String: String] { didSet { if !demo { defaults.set(menuWindowIDs, forKey: "menuWindowIds") } } }
    let demo: Bool
    let supportDirectory: URL
    var l10n: L10n { L10n(language) }
    var policy: RefreshPolicy { RefreshPolicy(interval: Double(refreshMinutes * 60)) }
    var providers: [ProviderID] { ProviderID.allCases.filter { $0 == .codex ? codexEnabled : claudeEnabled } }
    var isRefreshing: Bool { states.values.contains(where: \.loading) }
    private let defaults = UserDefaults.standard
    private let cache: SnapshotCache
    private var timer: Timer?
    private var tasks: [ProviderID: Task<Void, Never>] = [:]
    private var cancellations: [ProviderID: ProbeCancellation] = [:]
    private var observers: [NSObjectProtocol] = []
    private var suspended = false

    init(demo: Bool = false, language: AppLanguage? = nil) {
        self.demo = demo
        self.language = language ?? AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "system") ?? .system
        let savedInterval = UserDefaults.standard.integer(forKey: "refreshMinutes")
        refreshMinutes = [1, 5, 10, 15].contains(savedInterval) ? savedInterval : 5
        codexEnabled = UserDefaults.standard.object(forKey: "enabled.codex") as? Bool ?? true
        claudeEnabled = UserDefaults.standard.object(forKey: "enabled.claude") as? Bool ?? true
        paths = UserDefaults.standard.dictionary(forKey: "cliPaths") as? [String: String] ?? [:]
        menuWindowIDs = demo ? [:] : UserDefaults.standard.dictionary(forKey: "menuWindowIds") as? [String: String] ?? [:]
        supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Meterlet", isDirectory: true)
        cache = SnapshotCache(directory: supportDirectory.appendingPathComponent("Usage"))
        for provider in ProviderID.allCases {
            let saved = demo ? nil : cache.load(provider)
            states[provider] = ProviderState(snapshot: saved, restored: saved != nil)
        }
        if demo {
            codexEnabled = true
            claudeEnabled = true
            loadDemo()
        } else {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reschedulePreferences() }
            })
        }
    }

    func state(_ provider: ProviderID) -> ProviderState { states[provider] ?? ProviderState() }
    func start() { if !demo { refresh() } }
    func opened() { now = Date(); panelVisible = true; if !demo { tick() } }
    func closed() { panelVisible = false }
    func refresh() {
        guard !demo, !suspended else { return }
        now = Date()
        for provider in providers where tasks[provider] == nil && now.timeIntervalSince(state(provider).lastAttempt) >= 15 {
            fetch(provider)
        }
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for cancellation in cancellations.values { cancellation.cancel() }
        for task in tasks.values { task.cancel() }
    }
    private func suspend() { suspended = true; stop() }
    private func resume() {
        suspended = false
        now = Date()
        tick()
    }
    private func saveEnabled(_ provider: ProviderID, _ value: Bool) {
        guard !demo else { return }
        defaults.set(value, forKey: "enabled.\(provider.rawValue)")
        if !value { cancellations[provider]?.cancel(); tasks[provider]?.cancel() }
        tick()
    }
    private func reschedulePreferences() {
        guard !demo else { return }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        for provider in ProviderID.allCases {
            states[provider]?.nextFetch = state(provider).lastAttempt.addingTimeInterval(policy.delay(failures: state(provider).failures, lowPower: lowPower))
        }
        tick()
    }
    private func invalidate() {
        guard !demo else { return }
        for provider in providers { states[provider]?.nextFetch = .distantPast }
        tick()
    }

    private func fetch(_ provider: ProviderID) {
        states[provider]?.lastAttempt = Date()
        guard let executable = CLIResolver.resolve(provider, override: paths[provider.rawValue] ?? "") else {
            finish(provider, result: .failure(.cliNotFound(provider)))
            return
        }
        states[provider]?.loading = true
        let cancellation = ProbeCancellation()
        cancellations[provider] = cancellation
        let client = UsageClient(directory: supportDirectory.appendingPathComponent("Probes/\(provider.rawValue)", isDirectory: true))
        tasks[provider] = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await Task.detached(priority: .utility) { () -> Result<UsageSnapshot, UsageError> in
                    do { return .success(try client.fetch(provider, executable: executable, cancellation: cancellation)) }
                    catch let error as UsageError { return .failure(error) }
                    catch { return .failure(.unavailable(provider)) }
                }.value
            } onCancel: { cancellation.cancel() }
            self?.finish(provider, result: result)
        }
    }

    private func finish(_ provider: ProviderID, result: Result<UsageSnapshot, UsageError>) {
        states[provider]?.loading = false
        switch result {
        case .success(let snapshot):
            states[provider]?.snapshot = snapshot
            states[provider]?.error = nil
            states[provider]?.restored = false
            states[provider]?.failures = 0
            try? cache.save(snapshot)
        case .failure(.cancelled): break
        case .failure(let error):
            states[provider]?.error = error
            states[provider]?.failures += 1
        }
        states[provider]?.nextFetch = Date().addingTimeInterval(policy.delay(
            failures: state(provider).failures, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled
        ))
        tasks[provider] = nil
        cancellations[provider] = nil
        now = Date()
        schedule()
    }

    private func tick() {
        guard !demo, !suspended else { return }
        now = Date()
        for provider in providers where state(provider).nextFetch <= now && tasks[provider] == nil {
            fetch(provider)
        }
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        guard !demo, !suspended else { return }
        let current = Date()
        var events = providers.filter { tasks[$0] == nil }.map { state($0).nextFetch }
        for provider in providers {
            if let snapshot = state(provider).snapshot {
                events += snapshot.windows.compactMap(\.resetsAt).filter { $0 > current }
                let staleAt = snapshot.fetchedAt.addingTimeInterval(policy.staleAfter)
                if staleAt > current { events.append(staleAt) }
            }
        }
        guard let event = events.min() else { return }
        let timer = Timer(fire: max(event, current.addingTimeInterval(1)), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func loadDemo() {
        let time = Date()
        states[.codex] = ProviderState(snapshot: UsageSnapshot(provider: .codex, windows: [
            UsageWindow(id: "codex.primary", durationMinutes: 10_080, usedPercent: 28, resetsAt: time.addingTimeInterval(259_200), isPrimary: true),
        ], fetchedAt: time))
        states[.claude] = ProviderState(snapshot: UsageSnapshot(provider: .claude, windows: [
            UsageWindow(id: "session", durationMinutes: 300, usedPercent: 55, resetsAt: time.addingTimeInterval(2_880), isPrimary: true),
            UsageWindow(id: "weekly", durationMinutes: 10_080, usedPercent: 32, resetsAt: time.addingTimeInterval(432_000)),
            UsageWindow(id: "weekly.fable", scope: "Fable", durationMinutes: 10_080, usedPercent: 68, resetsAt: time.addingTimeInterval(432_000)),
        ], fetchedAt: time))
    }
}
