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
    case deleteAccountTooltip
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
            case .deleteAccountTooltip: return "Удалить аккаунт"
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
            case .deleteAccountTooltip: return "Delete account"
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
            case .nowEvent: return "Now"
            case .resetEvent: return "Reset"
            case .exhaustionEvent: return "Capacity ends"
            case .enoughAccessibility: return "Capacity lasts until reset"
            case .notEnoughAccessibility: return "Capacity runs out before reset"
            case .collectingAccessibility: return "Collecting history for a forecast"
            }
        }
    }

    static func sampleChartDetail(date: Date, remainingPercent: Int, language: AppLanguage) -> String {
        let dateStyle = Date.FormatStyle(locale: language.locale)
            .day()
            .month(language == .russian ? .wide : .abbreviated)
        let timeStyle = Date.FormatStyle(locale: language.locale)
            .hour()
            .minute()
        let dateText = date.formatted(dateStyle)
        let timeText = date.formatted(timeStyle)
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        switch language {
        case .russian:
            return "\(dateText), \(timeText) · осталось \(remainingPercent)%"
        case .english:
            return "\(dateText), \(timeText) · \(remainingPercent)% left"
        }
    }

    static func dailyChartDetail(
        date: Date,
        lowPercent: Int,
        endPercent: Int?,
        isToday: Bool,
        language: AppLanguage
    ) -> String {
        let dateText = date.formatted(
            Date.FormatStyle(locale: language.locale)
                .day()
                .month(.abbreviated)
        )
        switch language {
        case .russian:
            var text = "\(dateText) · минимум \(lowPercent)%"
            if let endPercent { text += " · конец \(endPercent)%" }
            if isToday { text += " · сегодня" }
            return text
        case .english:
            var text = "\(dateText) · low \(lowPercent)%"
            if let endPercent { text += " · end \(endPercent)%" }
            if isToday { text += " · today" }
            return text
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
        if hasError, knownTotal == 0 { return language == .russian ? "СБРОСЫ ?" : "RESETS ?" }
        guard knownAccounts > 0 else { return language == .russian ? "СБРОСЫ ..." : "RESETS ..." }
        if knownTotal == 0 { return language == .russian ? "НЕТ СБРОСОВ" : "NO RESETS" }
        let suffix = hasError ? "+" : ""
        if language == .english {
            return knownTotal == 1 ? "1\(suffix) RESET" : "\(knownTotal)\(suffix) RESETS"
        }
        let lastTwo = knownTotal % 100
        let last = knownTotal % 10
        let noun = last == 1 && lastTwo != 11 ? "СБРОС"
            : ((2...4).contains(last) && !(12...14).contains(lastTwo) ? "СБРОСА" : "СБРОСОВ")
        return "\(knownTotal)\(suffix) \(noun)"
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
    static func axisDate(_ date: Date, language: AppLanguage) -> String {
        date.formatted(
            Date.FormatStyle(locale: language.locale)
                .day()
                .month(.abbreviated)
        )
    }

    static func semanticLabels(language: AppLanguage) -> PoolChartSemanticLabels {
        switch language {
        case .russian:
            return PoolChartSemanticLabels(
                index: "Индекс",
                base: "Основание",
                capacity: "Ёмкость",
                pool: "Пул"
            )
        case .english:
            return PoolChartSemanticLabels(
                index: "Index",
                base: "Base",
                capacity: "Capacity",
                pool: "Pool"
            )
        }
    }
}

enum LocalizedIntervalFormatter {
    private enum Unit { case hour, day }

    static func duration(_ interval: TimeInterval, language: AppLanguage) -> String {
        let safeInterval = max(0, interval)
        let unit: Unit = safeInterval < 86_400 ? .hour : .day
        let divisor: Double = unit == .hour ? 3_600 : 86_400
        let value = safeInterval / divisor
        if value < 0.1 {
            return language == .russian
                ? "<0,1 \(unit == .hour ? "часа" : "дня")"
                : "<0.1 \(unit == .hour ? "hours" : "days")"
        }
        let rounded = (value * 10).rounded() / 10
        let number = numberText(rounded, language: language)
        return "\(number) \(unitText(unit, value: rounded, language: language))"
    }

    static func signedMargin(_ interval: TimeInterval, language: AppLanguage) -> String {
        let sign = interval < 0 ? "−" : "+"
        let days = abs(interval) / 86_400
        if days < 0.1 {
            return sign + (language == .russian ? "<0,1 дня" : "<0.1 days")
        }
        let rounded = (days * 10).rounded() / 10
        return sign + numberText(rounded, language: language)
            + " " + unitText(.day, value: rounded, language: language)
    }

    private static func numberText(_ value: Double, language: AppLanguage) -> String {
        let isWhole = abs(value.rounded() - value) < 1e-9
        let text = isWhole ? String(Int(value.rounded())) : String(format: "%.1f", value)
        return language == .russian ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    private static func unitText(_ unit: Unit, value: Double, language: AppLanguage) -> String {
        guard language == .russian else {
            let singular = abs(value - 1) < 1e-9
            return unit == .hour ? (singular ? "hour" : "hours") : (singular ? "day" : "days")
        }
        guard abs(value.rounded() - value) < 1e-9 else { return unit == .hour ? "часа" : "дня" }
        let integer = Int(value.rounded())
        let lastTwo = integer % 100
        let last = integer % 10
        if last == 1, lastTwo != 11 { return unit == .hour ? "час" : "день" }
        if (2...4).contains(last), !(12...14).contains(lastTwo) { return unit == .hour ? "часа" : "дня" }
        return unit == .hour ? "часов" : "дней"
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

struct PoolVerdictPresentation: Equatable {
    let kind: PoolVerdictKind
    let language: AppLanguage
    let resetInterval: TimeInterval?
    let exhaustionInterval: TimeInterval?
    let margin: TimeInterval?
    let title: String
    let detail: String
    let marginBadge: String?
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
                marginBadge: nil,
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
            return PoolVerdictPresentation(
                kind: verdict.kind,
                language: language,
                resetInterval: reset,
                exhaustionInterval: exhaustion,
                margin: margin,
                title: LocalizedText.value(verdict.kind == .enough ? .verdictEnoughTitle : .verdictNotEnoughTitle, language: language),
                detail: LocalizedText.value(verdict.kind == .enough ? .verdictEnoughDetail : .verdictNotEnoughDetail, language: language),
                marginBadge: LocalizedIntervalFormatter.signedMargin(margin, language: language),
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
