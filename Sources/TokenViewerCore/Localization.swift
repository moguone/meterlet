import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case system, en, ja
}

public struct L10n: Sendable {
    private static let resources: Bundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent("TokenViewer_TokenViewerCore.bundle"),
           let packaged = Bundle(url: url) { return packaged }
        return Bundle.module
    }()
    public let language: AppLanguage
    public var identifier: String {
        switch language {
        case .en: "en"
        case .ja: "ja"
        case .system: Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en"
        }
    }
    public var locale: Locale { Locale(identifier: identifier) }
    public init(_ language: AppLanguage = .system) { self.language = language }

    public func text(_ key: String) -> String {
        guard let path = Self.resources.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    public func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: args)
    }
    public func windowTitle(_ window: UsageWindow) -> String {
        let period: String
        switch window.durationMinutes {
        case 300: period = text("window.fiveHour")
        case 10_080: period = text("window.weekly")
        case let minutes? where minutes % 60 == 0: period = format("window.hours", minutes / 60)
        case let minutes?: period = format("window.minutes", minutes)
        case nil: period = text("window.usage")
        }
        return window.scope.map { "\($0) · \(period)" } ?? period
    }
    public func countdown(to reset: Date?, now: Date) -> String {
        guard let reset else { return text("reset.unknown") }
        guard reset > now else { return text("reset.pending") }
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        let remaining = ceil(reset.timeIntervalSince(now) / 60) * 60
        return format("reset.countdown", formatter.string(from: remaining) ?? text("reset.soon"))
    }
    public func resetDate(_ date: Date, now: Date = .now) -> String {
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        if Calendar.current.isDate(date, inSameDayAs: now) { return format("date.today", time) }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))
    }
    public func timestamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute().locale(locale))
    }
}
