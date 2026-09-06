import AppKit
import Combine
import SwiftUI
import MeterletCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuItemValidation {
    let store: UsageStore
    private let updater: AppUpdater
    private var statusItem: NSStatusItem?
    private let label = StatusLabelView()
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var previewWindow: NSWindow?
    private var menuLanguage: AppLanguage?
    private var subscriptions = Set<AnyCancellable>()
    private let renderDirectory: URL?

    init(demo: Bool, language: AppLanguage?, renderDirectory: URL? = nil) {
        store = UsageStore(demo: demo, language: language)
        updater = AppUpdater(enabled: !demo && renderDirectory == nil)
        self.renderDirectory = renderDirectory
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: 48)
        item.autosaveName = "Meterlet.usage"
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            label.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                label.widthAnchor.constraint(equalToConstant: 48),
                label.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        statusItem = item
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        store.objectWillChange.sink { [weak self] _ in
            // ObservableObject emits before the mutation. Draw after the new values are committed.
            DispatchQueue.main.async { self?.updateStatus() }
        }.store(in: &subscriptions)
        updateStatus()
        store.start()
        updater.willPresentUpdate = { [weak self] in self?.popover.performClose(nil) }
        updater.start()
        if CommandLine.arguments.contains("--show-window") || renderDirectory != nil {
            showPreviewWindow()
            if renderDirectory != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.renderPreview() }
            }
        }
        else if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.togglePopover() }
        }
    }

    private func makePopover(height: CGFloat? = nil) -> UsagePopover {
        UsagePopover(store: store, height: height ?? UsagePopover.preferredHeight(for: store), settings: { [weak self] in self?.showSettings() },
                     setup: { [weak self] provider in self?.setup(provider) }, quit: { NSApp.terminate(nil) })
    }
    private func updateStatus() {
        if menuLanguage != store.language { installApplicationMenu() }
        let now = Date()
        label.rows = store.providers.map { provider in
            let state = store.state(provider)
            return (provider, state.restored || state.error != nil ? "—" : (state.snapshot?.menuText(at: now, staleAfter: store.policy.staleAfter) ?? "—"))
        }
        let tooltip = store.providers.map { provider in
            let state = store.state(provider)
            let window = state.snapshot?.primary.map { store.l10n.windowTitle($0) } ?? store.l10n.text("window.usage")
            let value = state.restored || state.error != nil ? "—" : (state.snapshot?.menuText(at: now, staleAfter: store.policy.staleAfter) ?? "—")
            return "\(provider.title) · \(window): \(value)"
        }.joined(separator: "\n")
        statusItem?.button?.toolTip = tooltip
        statusItem?.button?.setAccessibilityLabel("Meterlet. \(tooltip)")
        statusItem?.button?.setAccessibilityRole(.button)
    }
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else { togglePopover() }
    }

    @objc private func togglePopover() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem?.button else { return }
        let screen = button.window?.screen ?? NSScreen.main
        let height = min(UsagePopover.preferredHeight(for: store), max(180, (screen?.visibleFrame.height ?? 800) - 24))
        // Establish a bounded size before AppKit positions the popover. A flexible hosting
        // view can otherwise grow after presentation and push the header outside the screen.
        let controller = NSHostingController(rootView: makePopover(height: height))
        controller.sizingOptions = []
        controller.view.setFrameSize(NSSize(width: 360, height: height))
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 360, height: height)
        store.opened()
        NSApp.activate(ignoringOtherApps: true)
        // NSStatusBarButton uses flipped coordinates: maxY is its lower edge.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: button.isFlipped ? .maxY : .minY)
        popover.contentViewController?.view.window?.makeKey()
        if !popover.isShown { store.closed() }
    }

    private func showContextMenu() {
        popover.performClose(nil)
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        let menu = NSMenu()
        menu.addItem(withTitle: store.l10n.text("usage.title"), action: #selector(togglePopover), keyEquivalent: "").target = self
        menu.addItem(withTitle: store.l10n.text("action.settings"), action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: store.l10n.text("action.checkUpdates"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: store.l10n.text("action.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY), in: button)
    }

    private func installApplicationMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(withTitle: store.l10n.text("usage.title"), action: #selector(togglePopover), keyEquivalent: "1").target = self
        applicationMenu.addItem(withTitle: store.l10n.text("action.settings"), action: #selector(showSettings), keyEquivalent: ",").target = self
        applicationMenu.addItem(withTitle: store.l10n.text("action.checkUpdates"), action: #selector(checkForUpdates), keyEquivalent: "").target = self
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: store.l10n.text("action.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        NSApp.mainMenu = menu
        menuLanguage = store.language
    }
    @objc private func checkForUpdates() { updater.checkForUpdates() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(checkForUpdates) ? updater.canCheckForUpdates : true
    }

    func popoverDidClose(_ notification: Notification) { store.closed() }
    func applicationWillTerminate(_ notification: Notification) { store.stop() }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(store: store, updater: updater))
            let window = NSWindow(contentViewController: controller)
            window.title = "Meterlet"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func setup(_ provider: ProviderID) {
        guard let executable = CLIResolver.resolve(provider, override: store.paths[provider.rawValue] ?? "") else {
            showSettings()
            return
        }
        // Opening this file is a user action. Authentication remains entirely inside the official CLI.
        let command = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let script = "#!/bin/zsh\nexec \(command)\(provider == .codex ? " login" : "")\n"
        let url = store.supportDirectory.appendingPathComponent("Set up \(provider.title).command")
        do {
            try FileManager.default.createDirectory(at: store.supportDirectory, withIntermediateDirectories: true)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
            NSWorkspace.shared.open(url)
        } catch { showSettings() }
    }

    private func showPreviewWindow() {
        store.opened()
        let window = NSWindow(contentViewController: NSHostingController(rootView: makePopover()))
        window.title = store.demo ? "Meterlet · Preview" : "Meterlet"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
    }

    private func renderPreview() {
        guard store.demo, let directory = renderDirectory, let view = previewWindow?.contentView else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, target) in [("popover", view), ("menubar", label as NSView)] {
                target.layoutSubtreeIfNeeded()
                guard let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { throw CocoaError(.fileWriteUnknown) }
                target.cacheDisplay(in: target.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: directory.appendingPathComponent("\(name).png"))
            }
            print("Preview saved to \(directory.path)")
            NSApp.terminate(nil)
        } catch { print("Preview rendering failed"); exit(2) }
    }
}
