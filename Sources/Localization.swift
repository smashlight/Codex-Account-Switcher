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
}
