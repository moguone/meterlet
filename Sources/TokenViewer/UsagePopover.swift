import SwiftUI
import TokenViewerCore

extension ProviderID {
    var color: Color { self == .codex ? Color(red: 0.08, green: 0.49, blue: 0.53) : Color(red: 0.80, green: 0.39, blue: 0.27) }
    var symbol: String { self == .codex ? "terminal.fill" : "sun.max.fill" }
}

struct UsagePopover: View {
    @ObservedObject var store: UsageStore
    var settings: () -> Void
    var setup: (ProviderID) -> Void
    var quit: () -> Void
    private var l: L10n { store.l10n }
    @State private var measuredContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(l.text("usage.title")).font(.system(size: 16, weight: .semibold))
                Spacer()
                if store.isRefreshing { ProgressView().controlSize(.small).scaleEffect(0.75) }
                Button(action: store.refresh) { Image(systemName: "arrow.clockwise").font(.system(size: 14)) }
                    .disabled(store.isRefreshing || store.demo).help(l.text("action.refresh")).accessibilityLabel(l.text("action.refresh"))
                Button(action: settings) { Image(systemName: "gearshape").font(.system(size: 15)) }
                    .help(l.text("action.settings")).accessibilityLabel(l.text("action.settings"))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            if store.panelVisible {
                TimelineView(.periodic(from: .now, by: 60)) { context in contents(at: context.date) }
            } else { contents(at: store.now) }
            Divider()
            HStack(spacing: 12) {
                if store.demo {
                    Text(l.text("status.demo")).foregroundStyle(.secondary)
                } else {
                    Link("GitHub", destination: URL(string: "https://github.com/moguone/token_viewer")!)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(l.text("action.refresh"), action: store.refresh).disabled(store.isRefreshing || store.demo)
                Button(action: quit) { Image(systemName: "power") }
                    .help(l.text("action.quit")).accessibilityLabel(l.text("action.quit"))
            }
            .font(.system(size: 11)).buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.vertical, 13)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .environment(\.locale, l.locale)
    }

    private func contents(at now: Date) -> some View {
        let height = measuredContentHeight > 0 ? measuredContentHeight : estimatedHeight
        return ScrollView {
            VStack(spacing: 0) {
                if store.providers.isEmpty {
                    Text(l.text("status.off")).foregroundStyle(.secondary).padding(28)
                }
                ForEach(store.providers) { provider in
                    if provider != store.providers.first { Divider().padding(.horizontal, 20) }
                    providerSection(provider, now: now)
                }
            }
            .background(GeometryReader { geometry in
                Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
            })
        }
        .onPreferenceChange(ContentHeightKey.self) { measuredContentHeight = $0 }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(height, max(240, (NSScreen.main?.visibleFrame.height ?? 800) - 190), 650))
    }

    private var estimatedHeight: CGFloat {
        if store.providers.isEmpty { return 80 }
        return store.providers.reduce(0) { height, provider in
            let state = store.state(provider)
            let windows = state.snapshot?.windows.count ?? 0
            let missingFable = provider == .claude && state.snapshot != nil && state.snapshot?.windows.contains(where: \.isFable) == false
            return height + 93 + CGFloat(windows) * 74 + (state.error == nil ? 0 : 76)
                + (windows == 0 && state.error == nil ? 40 : 0) + (missingFable ? 46 : 0)
        }
    }

    private func providerSection(_ provider: ProviderID, now: Date) -> some View {
        let state = store.state(provider)
        let stale = state.restored || state.error != nil || state.snapshot?.isStale(at: now, after: store.policy.staleAfter) == true
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: provider.symbol).foregroundStyle(provider.color).font(.system(size: 15))
                Text(provider.title).font(.system(size: 15, weight: .semibold))
                Spacer()
                if stale { Text(l.text("status.stale")).font(.system(size: 10)).foregroundStyle(.secondary) }
                Link(destination: provider.usageURL) { Image(systemName: "arrow.up.right.square").font(.system(size: 12)) }
                    .foregroundStyle(.secondary).help(l.text("action.usagePage"))
                    .accessibilityLabel("\(provider.title): \(l.text("action.usagePage"))")
            }
            .padding(.bottom, 16)
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows) { window in
                    UsageWindowRow(window: window, provider: provider, l10n: l, now: now, stale: stale)
                        .padding(.bottom, 17)
                }
                if provider == .claude && !snapshot.windows.contains(where: \.isFable) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle")
                        Text(l.text("status.fableMissing")).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.system(size: 10)).foregroundStyle(.secondary).padding(.bottom, 10)
                }
            } else if state.error == nil {
                Text(l.text(state.loading ? "status.loading" : "status.never"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 20)
            }
            if let error = state.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l.text(error.messageKey)).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if [.cliNotFound(provider), .signInRequired(provider), .setupRequired(provider), .unsupportedCLI(provider)].contains(error) {
                        Button(l.text("action.openCLI")) { setup(provider) }.buttonStyle(.link).font(.system(size: 11))
                    }
                }.padding(.bottom, 12)
            }
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 10))
                Text(state.snapshot.map { l.format("status.updated", l.timestamp($0.fetchedAt)) } ?? l.text("status.never"))
            }
            .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct UsageWindowRow: View {
    let window: UsageWindow
    let provider: ProviderID
    let l10n: L10n
    let now: Date
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(l10n.windowTitle(window)).font(.system(size: 12))
                Spacer(minLength: 8)
                Text(window.percentText).font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.08))
                    Capsule().fill(window.usedPercent >= 90 ? Color.orange : provider.color)
                        .frame(width: geometry.size.width * window.fraction)
                }
            }.frame(height: 5)
            HStack(alignment: .top, spacing: 6) {
                Text(window.resetsAt == nil ? (window.resetDescription ?? l10n.text("reset.unknown")) : l10n.countdown(to: window.resetsAt, now: now))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                if let reset = window.resetsAt {
                    Text(l10n.resetDate(reset, now: now)).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .opacity(stale || window.isExpired(at: now) ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}
