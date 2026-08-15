import AppKit
import Foundation

struct CodexAccount: Equatable {
    let selector: String
    let email: String
    let plan: String
    let fiveHourUsage: String
    let weeklyUsage: String
    let fiveHourUsedPercent: Int?
    let weeklyUsedPercent: Int?
    let lastActivity: String
    let isActive: Bool
}

struct HealthStatus {
    let title: String
    let value: String
    let color: NSColor
}

struct SwitchHistoryEntry: Codable {
    let date: Date
    let fromLabel: String
    let toLabel: String
    let automatic: Bool
    let reason: String
    let result: String
}

struct ResetHistoryEntry: Codable {
    let date: Date
    let accountLabel: String
    let result: String
    let creditBefore: Int?
    let creditAfter: Int?
    let fiveHourRemaining: Int?
    let weeklyRemaining: Int?
    let detail: String
}

struct ApiUsageSnapshot: Equatable {
    let usedTokens: Int
    let limitTokens: Int
    let warningPercent: Int
    let lastUpdatedText: String
    let lastError: String?

    var usedPercent: Int {
        guard limitTokens > 0 else { return 0 }
        return max(0, min(100, Int((Double(usedTokens) / Double(limitTokens)) * 100.0)))
    }

    var remainingTokens: Int {
        max(0, limitTokens - usedTokens)
    }
}

struct ResetCredit: Equatable {
    let id: String
    let title: String
    let resetType: String
    let status: String
    let grantedAt: Date?
    let expiresAt: Date?
}

struct ResetCreditsSnapshot: Equatable {
    let availableCount: Int?
    let credits: [ResetCredit]
    let lastUpdatedText: String
    let lastError: String?

    var availableCredits: [ResetCredit] {
        credits.filter { $0.status.lowercased() == "available" }
    }

    var displayCount: Int? {
        availableCount ?? (credits.isEmpty ? nil : availableCredits.count)
    }
}

struct UsageLimitWindowSnapshot: Equatable {
    let remainingPercent: Int
    let resetAt: Date?
}

struct DirectUsageSnapshot: Equatable {
    let fiveHour: UsageLimitWindowSnapshot
    let weekly: UsageLimitWindowSnapshot
}

struct ResetConsumeReceipt {
    let code: String
    let windowsReset: Int
    let message: String
}

struct ResetVerificationOutcome {
    let resetSnapshot: ResetCreditsSnapshot?
    let usageSnapshot: DirectUsageSnapshot?
    let creditConfirmed: Bool
    let usageConfirmed: Bool
    let attempts: Int
    let detail: String
}

enum UsageDisplayMode: String {
    case fiveHour
    case weekly
}

enum AutoSwitchMode: String {
    case off
    case ask
    case threshold
    case zero
}

enum AccountPanelMode {
    case usage
    case settings
    case api
    case resets
}

enum SettingsPanelAction: String {
    case usageView
    case settingsView
    case resetCreditsView
    case addAccount
    case apiView
    case setupApiMode
    case switchApiMode
    case editApiLimit
    case refreshApiUsage
    case testApiReminder
    case editLabels
    case removeAccount
    case usageWeekly
    case usageFiveHour
    case toggleLaunchAtLogin
    case toggleUsageReminder
    case toggleCreditExpiryNotifications
    case editUsageReminder
    case toggleAutoSwitch
    case editAutoSwitch
    case toggleConfirmSwitch
    case toggleProtectCodex
    case editRefresh
    case forceRefresh
    case checkUpdates
    case cleanBackups
    case diagnostics
    case quit
}

func usageStatusColor(for percent: Int?) -> NSColor {
    guard let percent else { return .secondaryLabelColor }
    if percent >= 50 { return .warmGreen }
    if percent >= 20 { return .warmAmber }
    return .warmRed
}

// MARK: - Warm glass palette

extension NSColor {
    /// CodexBar-style teal-blue meter fill (#4FB6C3).
    static let meterBlue = NSColor(red: 0.310, green: 0.714, blue: 0.765, alpha: 1)
    /// Deeper variant of the meter gradient (#3584A3).
    static let meterBlueDeep = NSColor(red: 0.208, green: 0.518, blue: 0.639, alpha: 1)
    /// Warm off-white (#F5F3EE).
    static let warmWhite = NSColor(red: 0.960, green: 0.953, blue: 0.933, alpha: 1)
    /// Warm green (#4ADE80).
    static let warmGreen = NSColor(red: 0.290, green: 0.871, blue: 0.502, alpha: 1)
    /// Amber / system orange (#FF9F0A).
    static let warmAmber = NSColor(red: 1.000, green: 0.624, blue: 0.039, alpha: 1)
    /// Warm system red (#FF453A).
    static let warmRed = NSColor(red: 1.000, green: 0.271, blue: 0.227, alpha: 1)
}

extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

struct PanelTheme {
    let isDark: Bool

    static func current(for appearance: NSAppearance?) -> PanelTheme {
        PanelTheme(isDark: appearance?.isDarkMode ?? NSApp.effectiveAppearance.isDarkMode)
    }

    var primaryText: NSColor {
        NSColor.warmWhite
    }

    var secondaryText: NSColor {
        NSColor(red: 0.659, green: 0.635, blue: 0.620, alpha: 1) // #A8A29E
    }

    var tertiaryText: NSColor {
        NSColor(red: 0.475, green: 0.443, blue: 0.420, alpha: 1) // #79716B
    }

    var valueText: NSColor {
        NSColor(red: 0.840, green: 0.812, blue: 0.780, alpha: 1) // #D6CFC7
    }

    var inactiveAccent: NSColor {
        NSColor(red: 0.545, green: 0.520, blue: 0.490, alpha: 1) // #8B857D
    }

    var activeCardFill: NSColor {
        NSColor(red: 0.150, green: 0.105, blue: 0.055, alpha: 0.96) // warm amber-tinted graphite
    }

    var inactiveCardFill: NSColor {
        NSColor(red: 0.098, green: 0.090, blue: 0.078, alpha: 0.97) // warm graphite
    }

    var inactiveCardHoverFill: NSColor {
        NSColor(red: 0.125, green: 0.114, blue: 0.096, alpha: 1)
    }

    var inactiveCardBorder: NSColor {
        NSColor.warmWhite.withAlphaComponent(0.13)
    }

    var bottomBarFill: NSColor {
        NSColor(red: 0.075, green: 0.069, blue: 0.058, alpha: 0.98)
    }

    var divider: NSColor {
        NSColor.warmWhite.withAlphaComponent(0.10)
    }

    var iconTint: NSColor {
        NSColor(red: 0.720, green: 0.698, blue: 0.670, alpha: 1)
    }

    var ringTrack: NSColor {
        NSColor.white.withAlphaComponent(0.075)
    }

    var progressTrack: NSColor {
        NSColor.white.withAlphaComponent(0.10)
    }

    var inactiveButtonFill: NSColor {
        NSColor(red: 0.165, green: 0.150, blue: 0.130, alpha: 1)
    }

    var usageInactiveButtonFill: NSColor {
        NSColor(red: 0.195, green: 0.178, blue: 0.155, alpha: 1)
    }

    var switchOffFill: NSColor {
        NSColor.white.withAlphaComponent(0.18)
    }
}

enum ApiUsageFetchResult {
    case success(Int)
    case failure(String)
}

enum ResetCreditsFetchResult {
    case success(ResetCreditsSnapshot)
    case failure(String)
}

enum ResetCreditRedemptionResult {
    case success(ResetConsumeReceipt)
    case failure(String)
}

enum DirectUsageFetchResult {
    case success(DirectUsageSnapshot)
    case failure(String)
}

struct SavedAccountAuth {
    let email: String
    let accessToken: String
    let accountID: String
    let refreshToken: String?
    let lastRefresh: Date?
}

enum SavedAccountAuthResult {
    case success(SavedAccountAuth)
    case failure(String)
}
