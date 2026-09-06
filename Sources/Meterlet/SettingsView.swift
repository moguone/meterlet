import AppKit
import ServiceManagement
import SwiftUI
import MeterletCore

struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updater: AppUpdater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError = false
    private var l: L10n { store.l10n }

    var body: some View {
        Form {
            Section(l.text("settings.general")) {
                Picker(l.text("settings.language"), selection: $store.language) {
                    Text(l.text("settings.system")).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.en)
                    Text("日本語").tag(AppLanguage.ja)
                }
                Picker(l.text("settings.interval"), selection: $store.refreshMinutes) {
                    ForEach([1, 5, 10, 15], id: \.self) { minutes in
                        Text(l.format("settings.minutes", minutes)).tag(minutes)
                    }
                }
                Toggle(l.text("settings.launch"), isOn: $launchAtLogin)
                    .disabled(store.demo)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchError = SMAppService.mainApp.status == .requiresApproval
                        } catch { launchError = true }
                    }
                if launchError { Text(l.text("settings.launchError")).font(.caption).foregroundStyle(.secondary) }
            }
            Section(l.text("settings.updates")) {
                Toggle(l.text("settings.autoUpdates"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.setAutomaticallyChecksForUpdates($0) }
                )).disabled(!updater.isAvailable)
                Text(l.text(updater.isAvailable ? "settings.updateExplanation" : "settings.updateUnavailable"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(l.text("action.checkUpdates"), action: updater.checkForUpdates)
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let checked = updater.lastChecked {
                        Text(l.format("settings.lastUpdateCheck", l.timestamp(checked)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section(l.text("settings.providers")) {
                Toggle(l.format("settings.enabled", "Codex"), isOn: $store.codexEnabled)
                Toggle(l.format("settings.enabled", "Claude Code"), isOn: $store.claudeEnabled)
                ForEach(ProviderID.allCases) { provider in
                    ExecutablePathRow(store: store, provider: provider)
                }
            }
            Section {
                Text(l.text("settings.menu"))
                Text(l.text("settings.energy"))
                Text(l.text("settings.fable"))
                Text(l.text("settings.privacy"))
            }.font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(l.format("settings.version", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Link("GitHub", destination: URL(string: "https://github.com/moguone/meterlet")!)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .environment(\.locale, l.locale)
    }

}

private struct ExecutablePathRow: View {
    @ObservedObject var store: UsageStore
    let provider: ProviderID
    @State private var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.l10n.format("settings.path", provider.title)).font(.caption)
            HStack {
                TextField(store.l10n.text("settings.autoPath"), text: $draft)
                    .onSubmit { store.paths[provider.rawValue] = draft }
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                Button(store.l10n.text("action.browse"), action: browse)
            }
        }
        .onAppear { draft = store.paths[provider.rawValue] ?? "" }
    }
    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.showsHiddenFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            draft = url.path
            store.paths[provider.rawValue] = url.path
        }
    }
}
