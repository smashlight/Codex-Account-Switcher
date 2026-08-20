import Foundation

enum AppLanguage: String, CaseIterable {
    case russian = "ru"
    case english = "en"

    static func resolve(_ rawValue: String?) -> AppLanguage {
        guard let rawValue, !rawValue.isEmpty else { return .russian }
        return AppLanguage(rawValue: rawValue) ?? .russian
    }

    var locale: Locale {
        Locale(identifier: self == .russian ? "ru_RU" : "en_US")
    }
}

struct AppLanguagePreferenceStore {
    static let defaultsKey = "appLanguage"
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppLanguage {
        AppLanguage.resolve(defaults.string(forKey: Self.defaultsKey))
    }

    func save(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.defaultsKey)
    }

    @discardableResult
    func select(_ language: AppLanguage, rebuild: () -> Void) -> Bool {
        guard load() != language else { return false }
        save(language)
        rebuild()
        return true
    }
}

enum LocalizedTextKey: CaseIterable {
    case poolHistoryCollecting
    case noAccountsTitle
    case noAccountsDetail
    case settingsButton
    case settingsTooltip
    case addButton
    case addTooltip
    case refreshButton
    case refreshTooltip
    case quitButton
    case quitConfirmButton
    case quitTooltip
    case switchPrompt
    case switchRelaunchDetail
    case cancelButton
    case switchButton
    case deleteAccountButton
    case resetChanceTitle
    case languageLabel
    case russianOption
    case englishOption
    case verdictEnoughTitle
    case verdictEnoughDetail
    case verdictNotEnoughTitle
    case verdictNotEnoughDetail
    case verdictCollectingTitle
    case verdictCollectingDetail
    case verdictDeficitSummary
    case verdictAfterResetSummary
    case nowEvent
    case resetEvent
    case exhaustionEvent
    case enoughAccessibility
    case notEnoughAccessibility
    case collectingAccessibility
}

enum LocalizedText {
    static func value(_ key: LocalizedTextKey, language: AppLanguage) -> String {
        switch language {
        case .russian:
            switch key {
            case .poolHistoryCollecting: return "История пула набирается…"
            case .noAccountsTitle: return "Нет доступных аккаунтов"
            case .noAccountsDetail: return "Откройте настройки, чтобы добавить аккаунт."
            case .settingsButton: return "Настройки"
            case .settingsTooltip: return "Открыть настройки"
            case .addButton: return "Добавить"
            case .addTooltip: return "Добавить аккаунт"
            case .refreshButton: return "Обновить"
            case .refreshTooltip: return "Обновить данные всех сохранённых аккаунтов"
            case .quitButton: return "Выйти"
            case .quitConfirmButton: return "Выйти?"
            case .quitTooltip: return "Выйти из Codex Account Switcher"
            case .switchPrompt: return "Переключиться на этот аккаунт?"
            case .switchRelaunchDetail: return "Codex будет перезапущен"
            case .cancelButton: return "Отмена"
            case .switchButton: return "Переключить"
            case .deleteAccountButton: return "Удалить"
            case .resetChanceTitle: return "Шанс сброса от Tibo"
            case .languageLabel: return "Язык / Language"
            case .russianOption: return "Русский"
            case .englishOption: return "English"
            case .verdictEnoughTitle: return "Хватит до сброса"
            case .verdictEnoughDetail: return "Текущего запаса достаточно до следующего сброса."
            case .verdictNotEnoughTitle: return "Не хватит до сброса"
            case .verdictNotEnoughDetail: return "Запас закончится раньше следующего сброса."
            case .verdictCollectingTitle: return "Собираем историю"
            case .verdictCollectingDetail: return "Нужно больше данных для надёжного прогноза."
            case .verdictDeficitSummary: return "Дефицит"
            case .verdictAfterResetSummary: return "Запас после сброса"
            case .nowEvent: return "Сейчас"
            case .resetEvent: return "Сброс"
            case .exhaustionEvent: return "Запас закончится"
            case .enoughAccessibility: return "Запаса хватит до сброса"
            case .notEnoughAccessibility: return "Запас закончится до сброса"
            case .collectingAccessibility: return "Собираем историю для прогноза"
            }
        case .english:
            switch key {
            case .poolHistoryCollecting: return "Collecting pool history…"
            case .noAccountsTitle: return "No accounts available"
            case .noAccountsDetail: return "Open settings to add an account."
            case .settingsButton: return "Settings"
            case .settingsTooltip: return "Open settings"
            case .addButton: return "Add"
            case .addTooltip: return "Add account"
            case .refreshButton: return "Refresh"
            case .refreshTooltip: return "Refresh usage for all saved accounts"
            case .quitButton: return "Quit"
            case .quitConfirmButton: return "Quit?"
            case .quitTooltip: return "Quit Codex Account Switcher"
            case .switchPrompt: return "Switch to this account?"
            case .switchRelaunchDetail: return "Codex will relaunch"
            case .cancelButton: return "Cancel"
            case .switchButton: return "Switch"
            case .deleteAccountButton: return "Delete"
            case .resetChanceTitle: return "Reset chance by Tibo"
            case .languageLabel: return "Язык / Language"
            case .russianOption: return "Русский"
            case .englishOption: return "English"
            case .verdictEnoughTitle: return "Enough until reset"
            case .verdictEnoughDetail: return "Current capacity is sufficient until the next reset."
            case .verdictNotEnoughTitle: return "Runs out before reset"
            case .verdictNotEnoughDetail: return "Capacity will run out before the next reset."
            case .verdictCollectingTitle: return "Collecting history"
            case .verdictCollectingDetail: return "More data is needed for a reliable forecast."
            case .verdictDeficitSummary: return "Deficit"
            case .verdictAfterResetSummary: return "After reset"
            case .nowEvent: return "Now"
            case .resetEvent: return "Reset"
            case .exhaustionEvent: return "Capacity ends"
            case .enoughAccessibility: return "Capacity lasts until reset"
            case .notEnoughAccessibility: return "Capacity runs out before reset"
            case .collectingAccessibility: return "Collecting history for a forecast"
            }
        }
    }

    static func lastUpdated(isRefreshing: Bool, elapsed: TimeInterval?, language: AppLanguage) -> String {
        if isRefreshing { return language == .russian ? "обновление…" : "refreshing..." }
        guard let elapsed else { return language == .russian ? "никогда" : "never" }
        let seconds = max(0, Int(elapsed))
        if seconds < 15 { return language == .russian ? "только что" : "just now" }
        if seconds < 60 { return language == .russian ? "\(seconds) сек. назад" : "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 10 { return language == .russian ? "\(minutes) мин. назад" : "\(minutes)m ago" }
        if minutes < 60 { return language == .russian ? "устарело \(minutes) мин." : "stale \(minutes)m" }
        return language == .russian ? "устарело \(minutes / 60) ч." : "stale \(minutes / 60)h"
    }

    static func resetCreditsButtonTitle(
        knownTotal: Int,
        knownAccounts: Int,
        hasError: Bool,
        language: AppLanguage
    ) -> String {
        if hasError, knownTotal == 0 { return language == .russian ? "Сбросы (?)" : "Resets (?)" }
        guard knownAccounts > 0 else { return language == .russian ? "Сбросы (…)" : "Resets (…)" }
        let suffix = hasError ? "+" : ""
        let label = language == .russian ? "Сбросы" : "Resets"
        return "\(label) (\(knownTotal)\(suffix))"
    }

    static func resetCreditsTooltip(
        knownTotal: Int,
        knownAccounts: Int,
        hasError: Bool,
        language: AppLanguage
    ) -> String {
        if hasError, knownTotal == 0 {
            return language == .russian
                ? "Не удалось проверить кредиты сброса для одного или нескольких аккаунтов"
                : "One or more reset-credit checks failed"
        }
        guard knownAccounts > 0 else {
            return language == .russian ? "Проверяем кредиты сброса" : "Checking reset credits"
        }
        if knownTotal == 0 {
            return language == .russian ? "Нет доступных кредитов сброса Codex" : "No Codex reset credits available"
        }
        return language == .russian
            ? "Показать кредиты сброса Codex по аккаунтам"
            : "Show Codex reset credits by account"
    }
}

struct PoolChartSemanticLabels: Equatable {
    let index: String
    let base: String
    let capacity: String
    let pool: String
}

enum PoolChartLocalization {
    private static let dailyReferencePercent = 100.0 / 7.0

    static func axisDate(_ date: Date, language: AppLanguage) -> String {
        date.formatted(
            Date.FormatStyle(locale: language.locale)
                .day()
                .month(.abbreviated)
        )
    }

    static func detailLines(for point: DailyPoolSpendPoint, language: AppLanguage) -> [String] {
        let dateText = axisDate(point.date, language: language)
        guard let spentPercent = point.spentPercent, point.coverage != .noData else {
            return [dateText, language == .russian ? "Нет данных" : "No data"]
        }

        let spent = number(spentPercent, language: language)
        let pace = number(spentPercent / dailyReferencePercent, language: language)
        let isLowerBound = point.coverage == .lowerBound || point.coverage == .inProgressLowerBound
        let isInProgress = point.coverage == .inProgress || point.coverage == .inProgressLowerBound
        var lines: [String]
        switch language {
        case .russian:
            lines = [
                dateText,
                isLowerBound ? "Потрачено не менее: \(spent)% пула" : "Потрачено: \(spent)% пула"
            ]
            if !isLowerBound { lines.append("Темп: \(pace)× дневного ориентира") }
            if isLowerBound { lines.append("Неполный день") }
            if let remainingPercent = point.remainingPercent {
                let remaining = number(remainingPercent, language: language)
                lines.append(
                    isInProgress
                        ? "Осталось сейчас: \(remaining)%"
                        : isLowerBound
                            ? "Осталось в последнем замере: \(remaining)%"
                            : "Осталось к концу дня: \(remaining)%"
                )
            }
        case .english:
            lines = [
                dateText,
                isLowerBound ? "Spent at least: \(spent)% of pool" : "Spent: \(spent)% of pool"
            ]
            if !isLowerBound { lines.append("Pace: \(pace)× daily reference") }
            if isLowerBound { lines.append("Incomplete day") }
            if let remainingPercent = point.remainingPercent {
                let remaining = number(remainingPercent, language: language)
                lines.append(
                    isInProgress
                        ? "Remaining now: \(remaining)%"
                        : isLowerBound
                            ? "Remaining at last sample: \(remaining)%"
                            : "Remaining at day end: \(remaining)%"
                )
            }
        }
        return lines
    }

    static func accessibilityValue(for point: DailyPoolSpendPoint, language: AppLanguage) -> String {
        detailLines(for: point, language: language).joined(separator: ". ")
    }

    static func dailyReference(language: AppLanguage) -> String {
        language == .russian ? "Дневной ориентир 14%" : "Daily reference 14%"
    }

    static func chartSummary(language: AppLanguage) -> String {
        language == .russian
            ? "Дневной расход общего недельного пула аккаунтов за 14 дней"
            : "Daily consumption of the combined weekly account pool over 14 days"
    }

    private static func number(_ value: Double, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = language.locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }

    static func semanticLabels(language: AppLanguage) -> PoolChartSemanticLabels {
        switch language {
        case .russian:
            return PoolChartSemanticLabels(
                index: "Индекс",
                base: "Основание",
                capacity: "Полная ёмкость",
                pool: "Расход пула"
            )
        case .english:
            return PoolChartSemanticLabels(
                index: "Index",
                base: "Base",
                capacity: "Full capacity",
                pool: "Pool spend"
            )
        }
    }
}

enum LocalizedIntervalFormatter {
    private enum Unit { case minute, hour, day }

    static func duration(_ interval: TimeInterval, language: AppLanguage) -> String {
        let safeInterval = max(0, interval)
        let totalMinutes = Int((safeInterval / 60).rounded())
        if totalMinutes < 60 {
            return component(totalMinutes, unit: .minute, language: language)
        }
        if totalMinutes < 24 * 60 {
            return joinedComponents(
                [
                    (totalMinutes / 60, .hour),
                    (totalMinutes % 60, .minute)
                ],
                language: language
            )
        }

        let totalHours = Int((safeInterval / 3_600).rounded())
        return joinedComponents(
            [
                (totalHours / 24, .day),
                (totalHours % 24, .hour)
            ],
            language: language
        )
    }

    static func signedMargin(_ interval: TimeInterval, language: AppLanguage) -> String {
        let sign = interval < 0 ? "−" : "+"
        return sign + duration(abs(interval), language: language)
    }

    private static func joinedComponents(
        _ components: [(value: Int, unit: Unit)],
        language: AppLanguage
    ) -> String {
        components
            .filter { $0.value > 0 }
            .map { component($0.value, unit: $0.unit, language: language) }
            .joined(separator: " ")
    }

    private static func component(_ value: Int, unit: Unit, language: AppLanguage) -> String {
        "\(value) \(unitText(unit, value: value, language: language))"
    }

    private static func unitText(_ unit: Unit, value: Int, language: AppLanguage) -> String {
        guard language == .russian else {
            switch unit {
            case .minute: return value == 1 ? "minute" : "minutes"
            case .hour: return value == 1 ? "hour" : "hours"
            case .day: return value == 1 ? "day" : "days"
            }
        }

        let lastTwo = value % 100
        let last = value % 10
        let form: Int
        if last == 1, lastTwo != 11 {
            form = 0
        } else if (2...4).contains(last), !(12...14).contains(lastTwo) {
            form = 1
        } else {
            form = 2
        }
        switch unit {
        case .minute: return ["минута", "минуты", "минут"][form]
        case .hour: return ["час", "часа", "часов"][form]
        case .day: return ["день", "дня", "дней"][form]
        }
    }
}

enum PoolVerdictEventKind: Equatable {
    case now
    case reset
    case exhaustion
}

struct PoolVerdictEventPresentation: Equatable {
    let kind: PoolVerdictEventKind
    let title: String
    let intervalText: String?
}

enum PoolVerdictTimelineGeometry {
    static func firstEventFraction(
        firstInterval: TimeInterval,
        lastInterval: TimeInterval
    ) -> Double? {
        guard firstInterval.isFinite, lastInterval.isFinite,
              firstInterval > 0, lastInterval > 0 else { return nil }
        return max(0, min(1, firstInterval / lastInterval))
    }
}

struct PoolVerdictPresentation: Equatable {
    let kind: PoolVerdictKind
    let language: AppLanguage
    let resetInterval: TimeInterval?
    let exhaustionInterval: TimeInterval?
    let margin: TimeInterval?
    let title: String
    let detail: String
    let firstEventFraction: Double?
    let marginSummaryLabel: String?
    let marginSummaryValue: String?
    let accessibilityLabel: String
    let events: [PoolVerdictEventPresentation]
}

enum PoolVerdictPresenter {
    static func make(verdict: PoolVerdict, language: AppLanguage) -> PoolVerdictPresentation {
        switch verdict.kind {
        case .collecting:
            return PoolVerdictPresentation(
                kind: .collecting,
                language: language,
                resetInterval: nil,
                exhaustionInterval: nil,
                margin: nil,
                title: LocalizedText.value(.verdictCollectingTitle, language: language),
                detail: LocalizedText.value(.verdictCollectingDetail, language: language),
                firstEventFraction: nil,
                marginSummaryLabel: nil,
                marginSummaryValue: nil,
                accessibilityLabel: LocalizedText.value(.collectingAccessibility, language: language),
                events: []
            )
        case .enough, .notEnough:
            guard let reset = verdict.resetInterval,
                  let exhaustion = verdict.exhaustionInterval,
                  let margin = verdict.margin else {
                return make(verdict: .collecting, language: language)
            }
            let resetEvent = event(.reset, interval: reset, language: language)
            let exhaustionEvent = event(.exhaustion, interval: exhaustion, language: language)
            let events = [event(.now, interval: nil, language: language)]
                + (verdict.kind == .enough ? [resetEvent, exhaustionEvent] : [exhaustionEvent, resetEvent])
            let firstInterval = verdict.kind == .enough ? reset : exhaustion
            let lastInterval = verdict.kind == .enough ? exhaustion : reset
            guard let firstEventFraction = PoolVerdictTimelineGeometry.firstEventFraction(
                firstInterval: firstInterval,
                lastInterval: lastInterval
            ) else {
                return make(verdict: .collecting, language: language)
            }
            let marginSummaryKey: LocalizedTextKey = verdict.kind == .enough
                ? .verdictAfterResetSummary
                : .verdictDeficitSummary
            return PoolVerdictPresentation(
                kind: verdict.kind,
                language: language,
                resetInterval: reset,
                exhaustionInterval: exhaustion,
                margin: margin,
                title: LocalizedText.value(verdict.kind == .enough ? .verdictEnoughTitle : .verdictNotEnoughTitle, language: language),
                detail: LocalizedText.value(verdict.kind == .enough ? .verdictEnoughDetail : .verdictNotEnoughDetail, language: language),
                firstEventFraction: firstEventFraction,
                marginSummaryLabel: LocalizedText.value(marginSummaryKey, language: language),
                marginSummaryValue: LocalizedIntervalFormatter.duration(abs(margin), language: language),
                accessibilityLabel: LocalizedText.value(verdict.kind == .enough ? .enoughAccessibility : .notEnoughAccessibility, language: language),
                events: events
            )
        }
    }

    private static func event(
        _ kind: PoolVerdictEventKind,
        interval: TimeInterval?,
        language: AppLanguage
    ) -> PoolVerdictEventPresentation {
        let key: LocalizedTextKey = kind == .now ? .nowEvent : (kind == .reset ? .resetEvent : .exhaustionEvent)
        let intervalText = interval.map {
            let duration = LocalizedIntervalFormatter.duration($0, language: language)
            return language == .russian ? "через \(duration)" : "in \(duration)"
        }
        return PoolVerdictEventPresentation(
            kind: kind,
            title: LocalizedText.value(key, language: language),
            intervalText: intervalText
        )
    }
}
