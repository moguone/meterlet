import AppKit
import Combine
import Sparkle

/// Sparkle owns update scheduling, signature verification, installation, and relaunch.
@MainActor
final class AppUpdater: NSObject, ObservableObject, @preconcurrency SPUStandardUserDriverDelegate {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastChecked: Date?
    let isAvailable: Bool
    var willPresentUpdate: (() -> Void)?
    private var controller: SPUStandardUpdaterController?

    init(enabled: Bool) {
        isAvailable = enabled && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
            && Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String
        super.init()
        guard isAvailable else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastChecked)
    }

    func start() { controller?.startUpdater() }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        willPresentUpdate?()
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        // Sparkle persists this preference. Do not duplicate it or reset it at launch.
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func standardUserDriverWillShowModalAlert() { willPresentUpdate?() }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if handleShowingUpdate { willPresentUpdate?() }
    }
}
