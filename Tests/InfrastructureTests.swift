import Foundation

private final class FailingSecondMoveFileManager: FileManager, @unchecked Sendable {
    private var moveCount = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moveCount += 1
        if moveCount == 2 {
            throw NSError(
                domain: "ReferencePluginTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "forced staged swap failure"]
            )
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

private final class FailingSwapAndRestoreFileManager: FileManager, @unchecked Sendable {
    private var moveCount = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moveCount += 1
        if moveCount == 2 || moveCount == 3 {
            throw NSError(
                domain: "ReferencePluginTests",
                code: moveCount,
                userInfo: [NSLocalizedDescriptionKey: "forced move failure \(moveCount)"]
            )
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

@main
struct InfrastructureTests {
    private static var failures: [String] = []
    private static var assertionCount = 0

    static func main() throws {
        testResetRefreshPolicy()
        testUsageRefreshPolicy()
        testWeeklyRemainingBand()
        testAccountListPresentationPolicy()
        testAccountListViewportHeightPolicy()
        testAccountListScrollPolicy()
        testInlineSwitchConfirmationPolicy()
        testInlineQuitConfirmationPolicy()
        testLastKnownGoodSnapshotPolicy()
        testToolbarStatusFormatting()
        testAppLanguagePreference()
        testLocalizedTextCompleteness()
        testLocalizedChartDetails()
        testLocalizedIntervalFormatting()
        testPoolVerdictPresentation()
        try testComputerUsePluginDiscovery()
        try testBackupPruning()
        testProcessRunner()
        testWeeklyResetFormatter()
        testTokenRefreshRequest()
        testTokenRefreshResponseParsing()
        testTokenRefreshErrorMapping()
        testTokenRefreshAgePolicy()
        testCodexAuthDateParsing()
        try testCodexAuthTokenWriter()
        try testPoolHistoryStore()
        testWeekCurveBuilder()
        testDailyPoolAggregator()
        testPaceEstimatorForecast()
        testPoolVerdict()
        testPoolHistorySampleResetsAtCoding()
        testResetChanceParsing()
        try testBundledMarketplaceSnapshotOk()
        try testBundledMarketplaceSnapshotIncomplete()
        try testBundledMarketplaceSnapshotAbsent()
        try testBundledMarketplaceSnapshotMissingManifest()
        try testBundledMarketplaceAppSource()
        try testBundledMarketplaceRepairNoop()
        try testBundledMarketplaceRepairFromApp()
        try testBundledMarketplaceRepairRestoresAbsentSnapshot()
        try testBundledMarketplaceRepairRefreshesOutdatedSnapshot()
        try testBundledMarketplaceRepairNoApp()
        try testBundledMarketplaceRepairStaleMove()
        try testBundledMarketplaceRepairRollback()
        try testBundledMarketplaceRepairReinstall()
        try testBundledMarketplaceRepairReinstallsNewBundledPlugin()
        try testBundledMarketplaceRepairReinstallFailure()
        try testReferencePluginInventory()
        try testReferencePluginCaptureRoundTrip()
        try testReferencePluginCapturePreservesPreviousReference()
        try testReferencePluginCaptureReportsRollbackFailure()
        try testReferencePluginCaptureRequiresReadableConfig()
        try testReferencePluginLoadRejectsModifiedFiles()
        try testReferencePluginMarketplacePreparation()
        try testReferencePluginMarketplaceDetectsChangedInstalledPackage()
        testReferencePluginMarketplaceRejectsMissingDigests()
        try testReferencePluginReconcileExactMatch()
        try testReferencePluginReconcileRestoresChangedFiles()
        try testReferencePluginReconcileIdempotent()
        try testReferencePluginReconcileWithoutReference()
        try testReferencePluginReconcileRollsBackFailedSwap()
        try testReferencePluginReconcileReportsRollbackFailure()
        testCuratedPluginPlan()
        testReferenceMarketplacePluginPlan()
        testReferenceMarketplacePluginPlanReinstallsChangedPackage()
        try testReferenceMarketplacePluginReconcile()
        try testReferenceMarketplacePluginReconcileReinstallsChangedPackage()
        try testReferenceMarketplacePluginReconcileReportsCLIError()
        try testCuratedPluginReconcileRollsBackPartialFailure()
        try testReferencePluginTransactionRollsBackBothLayers()
        try testReferencePluginTransactionRollsBackFailedFinalization()
        try testReferencePluginTransactionPreservesBackupWhenRollbackIsUnsafe()
        testPluginSyncStabilityTracker()
        testProcessLookupPolicy()

        if failures.isEmpty {
            print("Infrastructure tests passed (\(assertionCount) assertions).")
            return
        }

        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertionCount += 1
        if !condition() { failures.append(message) }
    }

    private static func testAppLanguagePreference() {
        let suiteName = "CodexAccountSwitcher.LanguageTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            expect(false, "language tests should create an isolated defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AppLanguagePreferenceStore(defaults: defaults)

        expect(store.load() == .russian, "missing language should default to Russian")
        defaults.set("", forKey: AppLanguagePreferenceStore.defaultsKey)
        expect(store.load() == .russian, "empty language should default to Russian")
        defaults.set("de", forKey: AppLanguagePreferenceStore.defaultsKey)
        expect(store.load() == .russian, "unknown language should default to Russian")

        store.save(.english)
        expect(defaults.string(forKey: AppLanguagePreferenceStore.defaultsKey) == "en", "English should persist with a stable raw value")
        expect(store.load() == .english, "English should restore from defaults")
        store.save(.russian)
        expect(defaults.string(forKey: AppLanguagePreferenceStore.defaultsKey) == "ru", "Russian should persist with a stable raw value")

        var rebuildCount = 0
        expect(!store.select(.russian) { rebuildCount += 1 }, "selecting the current language should be a no-op")
        expect(rebuildCount == 0, "an unchanged language should not rebuild the panel")
        expect(store.select(.english) { rebuildCount += 1 }, "selecting another language should report a change")
        expect(rebuildCount == 1, "a changed language should rebuild exactly once")
    }

    private static func testLocalizedTextCompleteness() {
        for key in LocalizedTextKey.allCases {
            for language in AppLanguage.allCases {
                let value = LocalizedText.value(key, language: language)
                expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(key) should be translated for \(language)")
            }
        }
        expect(LocalizedText.value(.languageLabel, language: .russian) == "Язык / Language", "the language label should stay bilingual")
        expect(LocalizedText.value(.languageLabel, language: .english) == "Язык / Language", "the language label should stay bilingual in English mode")
        expect(LocalizedText.value(.russianOption, language: .english) == "Русский", "the Russian option should remain self-identifying")
        expect(LocalizedText.value(.englishOption, language: .russian) == "English", "the English option should remain self-identifying")
    }

    private static func testLocalizedChartDetails() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 14, minute: 30)) else {
            expect(false, "chart detail tests should create a fixed local date")
            return
        }

        expect(
            LocalizedText.sampleChartDetail(date: date, remainingPercent: 42, language: .russian) == "17 августа, 14:30 · осталось 42%",
            "sample chart details should use the complete Russian sentence"
        )
        expect(
            LocalizedText.sampleChartDetail(date: date, remainingPercent: 42, language: .english) == "Aug 17, 2:30 PM · 42% left",
            "sample chart details should use the complete English sentence"
        )
        expect(
            LocalizedText.dailyChartDetail(date: date, lowPercent: 42, endPercent: 48, isToday: true, language: .russian) == "17 авг. · минимум 42% · конец 48% · сегодня",
            "daily chart details should include the Russian end value and today marker"
        )
        expect(
            LocalizedText.dailyChartDetail(date: date, lowPercent: 42, endPercent: 48, isToday: true, language: .english) == "Aug 17 · low 42% · end 48% · today",
            "daily chart details should include the English end value and today marker"
        )
        expect(
            LocalizedText.dailyChartDetail(date: date, lowPercent: 42, endPercent: nil, isToday: false, language: .english) == "Aug 17 · low 42%",
            "daily chart details should omit unavailable optional values"
        )
    }

    private static func testLocalizedIntervalFormatting() {
        expect(LocalizedIntervalFormatter.duration(90, language: .russian) == "<0,1 часа", "tiny Russian intervals should use a less-than form")
        expect(LocalizedIntervalFormatter.duration(90, language: .english) == "<0.1 hours", "tiny English intervals should use a less-than form")
        expect(LocalizedIntervalFormatter.duration(3_600, language: .russian) == "1 час", "Russian one-hour singular should be correct")
        expect(LocalizedIntervalFormatter.duration(2 * 3_600, language: .russian) == "2 часа", "Russian paucal hours should be correct")
        expect(LocalizedIntervalFormatter.duration(5 * 3_600, language: .russian) == "5 часов", "Russian plural hours should be correct")
        expect(LocalizedIntervalFormatter.duration(86_400, language: .russian) == "1 день", "Russian one-day singular should be correct")
        expect(LocalizedIntervalFormatter.duration(2 * 86_400, language: .russian) == "2 дня", "Russian paucal days should be correct")
        expect(LocalizedIntervalFormatter.duration(5 * 86_400, language: .russian) == "5 дней", "Russian plural days should be correct")
        expect(LocalizedIntervalFormatter.duration(1.5 * 86_400, language: .russian) == "1,5 дня", "Russian decimals should use comma")
        expect(LocalizedIntervalFormatter.duration(3_600, language: .english) == "1 hour", "English singular should be correct")
        expect(LocalizedIntervalFormatter.duration(2 * 3_600, language: .english) == "2 hours", "English plural should be correct")
        expect(LocalizedIntervalFormatter.duration(1.5 * 86_400, language: .english) == "1.5 days", "English decimals should use period")
        expect(LocalizedIntervalFormatter.signedMargin(0.9 * 86_400, language: .russian) == "+0,9 дня", "Russian positive badge should use plus and comma")
        expect(LocalizedIntervalFormatter.signedMargin(-0.7 * 86_400, language: .english) == "−0.7 days", "English deficit badge should use a typographic minus")
    }

    private static func testPoolVerdictPresentation() {
        let enough = PoolVerdict(kind: .enough, resetInterval: 2 * 86_400, exhaustionInterval: 2.9 * 86_400, margin: 0.9 * 86_400)
        let enoughRU = PoolVerdictPresenter.make(verdict: enough, language: .russian)
        expect(enoughRU.title == "Хватит до сброса", "Enough should use the Russian title")
        expect(enoughRU.marginBadge == "+0,9 дня", "Enough should show a positive buffer")
        expect(enoughRU.events.map(\.kind) == [.now, .reset, .exhaustion], "Enough should order reset before exhaustion")
        expect(enoughRU.events.map(\.intervalText) == [nil, "через 2 дня", "через 2,9 дня"], "Russian events should include localized intervals")

        let notEnough = PoolVerdict(kind: .notEnough, resetInterval: 2 * 86_400, exhaustionInterval: 1.3 * 86_400, margin: -0.7 * 86_400)
        let notEnoughEN = PoolVerdictPresenter.make(verdict: notEnough, language: .english)
        expect(notEnoughEN.title == "Runs out before reset", "Not Enough should use the English title")
        expect(notEnoughEN.marginBadge == "−0.7 days", "Not Enough should show a negative deficit")
        expect(notEnoughEN.events.map(\.kind) == [.now, .exhaustion, .reset], "Not Enough should order exhaustion before reset")
        expect(notEnoughEN.events.map(\.intervalText) == [nil, "in 1.3 days", "in 2 days"], "English events should include localized intervals")

        let collecting = PoolVerdictPresenter.make(verdict: .collecting, language: .russian)
        expect(collecting.kind == .collecting, "incomplete inputs should remain collecting")
        expect(collecting.marginBadge == nil, "Collecting should not show a badge")
        expect(collecting.events.isEmpty, "Collecting should not show an event scale")
    }

    private static func testResetRefreshPolicy() {
        let now = Date(timeIntervalSince1970: 1_000)
        expect(ResetRefreshPolicy.shouldRefresh(lastRefresh: nil, now: now, ttl: 300, force: false), "missing reset snapshot should refresh")
        expect(!ResetRefreshPolicy.shouldRefresh(lastRefresh: now.addingTimeInterval(-299), now: now, ttl: 300, force: false), "fresh reset snapshot should stay cached")
        expect(ResetRefreshPolicy.shouldRefresh(lastRefresh: now.addingTimeInterval(-300), now: now, ttl: 300, force: false), "expired reset snapshot should refresh")
        expect(ResetRefreshPolicy.shouldRefresh(lastRefresh: now, now: now, ttl: 300, force: true), "forced reset refresh should bypass cache")
    }

    private static func testUsageRefreshPolicy() {
        let now = Date(timeIntervalSince1970: 2_000)
        expect(UsageRefreshPolicy.shouldRefresh(lastRefresh: nil, now: now, ttl: 30, force: false), "missing usage snapshot should refresh")
        expect(!UsageRefreshPolicy.shouldRefresh(lastRefresh: now.addingTimeInterval(-29), now: now, ttl: 30, force: false), "fresh usage snapshot should stay cached")
        expect(UsageRefreshPolicy.shouldRefresh(lastRefresh: now.addingTimeInterval(-30), now: now, ttl: 30, force: false), "expired usage snapshot should refresh")
        expect(UsageRefreshPolicy.shouldRefresh(lastRefresh: now, now: now, ttl: 30, force: true), "forced usage refresh should bypass cache")
    }

    private static func testWeeklyRemainingBand() {
        expect(WeeklyRemainingBand.classify(nil) == .unknown, "missing remaining usage should be neutral")
        expect(WeeklyRemainingBand.classify(-1) == .critical, "negative remaining usage should clamp into critical")
        expect(WeeklyRemainingBand.classify(0) == .critical, "zero remaining should be critical")
        expect(WeeklyRemainingBand.classify(10) == .critical, "ten percent remaining should be critical")
        expect(WeeklyRemainingBand.classify(11) == .warning, "eleven percent remaining should be warning")
        expect(WeeklyRemainingBand.classify(25) == .warning, "twenty-five percent remaining should be warning")
        expect(WeeklyRemainingBand.classify(26) == .healthy, "twenty-six percent remaining should be healthy")
        expect(WeeklyRemainingBand.classify(100) == .healthy, "full remaining usage should be healthy")
        expect(WeeklyRemainingBand.classify(101) == .healthy, "over-reported remaining usage should clamp into healthy")
    }

    private static func testAccountListPresentationPolicy() {
        expect(AccountListPresentationPolicy.visibleRowCount(accountCount: 0, availableRowCapacity: 10) == 0, "empty accounts should have no rows")
        expect(AccountListPresentationPolicy.visibleRowCount(accountCount: 2, availableRowCapacity: 10) == 2, "two accounts should show two rows")
        expect(AccountListPresentationPolicy.visibleRowCount(accountCount: 10, availableRowCapacity: 10) == 10, "ten accounts should fit without scrolling")
        expect(AccountListPresentationPolicy.visibleRowCount(accountCount: 11, availableRowCapacity: 10) == 10, "eleven accounts should cap the viewport at ten rows")
        expect(AccountListPresentationPolicy.visibleRowCount(accountCount: 10, availableRowCapacity: 6) == 6, "short screens should lower visible capacity")
        expect(!AccountListPresentationPolicy.requiresScrolling(accountCount: 10, availableRowCapacity: 10), "ten rows should not scroll on a tall screen")
        expect(AccountListPresentationPolicy.requiresScrolling(accountCount: 11, availableRowCapacity: 10), "eleven rows should scroll")
        expect(AccountListPresentationPolicy.requiresScrolling(accountCount: 10, availableRowCapacity: 6), "short screens should scroll earlier")
    }

    private static func testAccountListScrollPolicy() {
        expect(AccountListScrollPolicy.revealedOrigin(rowMinY: 54, rowMaxY: 102, viewportHeight: 300, currentOrigin: 0, contentHeight: 500) == 0, "visible rows should preserve the current scroll origin")
        expect(AccountListScrollPolicy.revealedOrigin(rowMinY: 420, rowMaxY: 500, viewportHeight: 300, currentOrigin: 0, contentHeight: 500) == 200, "expanded bottom row should scroll fully into view")
        expect(AccountListScrollPolicy.revealedOrigin(rowMinY: 40, rowMaxY: 120, viewportHeight: 100, currentOrigin: 80, contentHeight: 500) == 40, "expanded row above the viewport should scroll to its top")
        expect(AccountListScrollPolicy.revealedOrigin(rowMinY: 460, rowMaxY: 560, viewportHeight: 300, currentOrigin: 0, contentHeight: 500) == 200, "scroll origin should clamp to the document bottom")
    }

    private static func testAccountListViewportHeightPolicy() {
        expect(AccountListPresentationPolicy.viewportHeight(accountCount: 2, visibleRowCount: 2, maximumHeight: 102, rowHeight: 48, confirmationRowHeight: 78, rowGap: 6, showsConfirmation: true) == 78, "confirmation should temporarily hide a non-fitting second row")
        expect(AccountListPresentationPolicy.viewportHeight(accountCount: 8, visibleRowCount: 8, maximumHeight: 426, rowHeight: 48, confirmationRowHeight: 78, rowGap: 6, showsConfirmation: true) == 402, "confirmation should show only complete rows")
        expect(AccountListPresentationPolicy.viewportHeight(accountCount: 8, visibleRowCount: 8, maximumHeight: 456, rowHeight: 48, confirmationRowHeight: 78, rowGap: 6, showsConfirmation: true) == 402, "confirmation viewport should stay compact even when more height is available")
        expect(AccountListPresentationPolicy.viewportHeight(accountCount: 8, visibleRowCount: 8, maximumHeight: 456, rowHeight: 48, confirmationRowHeight: 78, rowGap: 6, showsConfirmation: false) == 426, "normal lists should retain their compact height")
    }

    private static func testInlineSwitchConfirmationPolicy() {
        expect(InlineSwitchConfirmationPolicy.decision(armedEmail: nil, requestedEmail: "two@example.com", isActive: false, isSwitching: false) == .arm, "first click should arm confirmation")
        expect(InlineSwitchConfirmationPolicy.decision(armedEmail: "two@example.com", requestedEmail: "two@example.com", isActive: false, isSwitching: false) == .confirm, "confirmed target should switch")
        expect(InlineSwitchConfirmationPolicy.decision(armedEmail: "two@example.com", requestedEmail: "three@example.com", isActive: false, isSwitching: false) == .arm, "different target should replace confirmation")
        expect(InlineSwitchConfirmationPolicy.decision(armedEmail: nil, requestedEmail: "one@example.com", isActive: true, isSwitching: false) == .ignore, "active account should not arm")
        expect(InlineSwitchConfirmationPolicy.decision(armedEmail: nil, requestedEmail: "two@example.com", isActive: false, isSwitching: true) == .ignore, "switching state should ignore clicks")
    }

    private static func testInlineQuitConfirmationPolicy() {
        expect(InlineQuitConfirmationPolicy.decision(isArmed: false) == .arm, "first quit click should request confirmation")
        expect(InlineQuitConfirmationPolicy.decision(isArmed: true) == .confirm, "second quit click should terminate")
    }

    private static func testLastKnownGoodSnapshotPolicy() {
        let current = ["one": 100, "two": 100, "removed": 42]
        let merged = LastKnownGoodSnapshotPolicy.merged(
            current: current,
            successful: ["one": 99],
            validKeys: Set(["one", "two", "three"])
        )
        expect(merged["one"] == 99, "new successful usage should replace the previous reading")
        expect(merged["two"] == 100, "a failed or missing refresh should retain the last known good reading")
        expect(merged["three"] == nil, "an account without a successful reading should not invent usage")
        expect(merged["removed"] == nil, "removed accounts should be pruned from retained usage")

        let unchanged = LastKnownGoodSnapshotPolicy.merged(
            current: ["one": 100, "two": 100],
            successful: [:],
            validKeys: Set(["one", "two"])
        )
        expect(unchanged == ["one": 100, "two": 100], "a wholly failed refresh should not roll usage back")
    }

    private static func testToolbarStatusFormatting() {
        expect(ToolbarStatusFormatter.text(label: "A", usage: "89%") == "A89%", "single-character labels should keep the compact menu-bar format")
        expect(ToolbarStatusFormatter.text(label: "1287", usage: "100%") == "1287 100%", "multi-character labels should be separated from usage")
        expect(ToolbarStatusFormatter.text(label: "1287", usage: "100") == "1287 100", "compact usage should also be separated from multi-character labels")
    }

    private static func testComputerUsePluginDiscovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for version in ["1.0.799", "1.0.1000366", "1.2.1"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(version).appendingPathComponent("Codex Computer Use.app"),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("9.9.9"), withIntermediateDirectories: true)
        let found = ComputerUsePluginLocator.latestApp(in: root)
        expect(found?.deletingLastPathComponent().lastPathComponent == "1.2.1", "plugin discovery should use the newest valid numeric version")
        expect(found?.lastPathComponent == "Codex Computer Use.app", "plugin discovery should return the app bundle")
    }

    private static func testBackupPruning() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for stamp in 1...5 {
            let url = root.appendingPathComponent("account.auth.json.bak.\(stamp)")
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        FileManager.default.createFile(atPath: root.appendingPathComponent("account.auth.json").path, contents: Data())
        let removed = AuthBackupPruner.prune(in: root, keepingPerAccount: 2)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: root.path)
        expect(removed == 3, "backup pruning should report removed files")
        expect(remaining.contains("account.auth.json.bak.5"), "backup pruning should keep newest backup")
        expect(remaining.contains("account.auth.json.bak.4"), "backup pruning should keep requested backup count")
        expect(remaining.contains("account.auth.json"), "backup pruning should preserve active auth snapshot")
    }

    private static func testProcessRunner() {
        let environment = ProcessInfo.processInfo.environment
        let success = ProcessRunner.run("/bin/echo", ["healthy"], environment: environment, timeout: 2)
        expect(success.status == 0 && success.output.contains("healthy"), "process runner should capture successful output")
        let timeout = ProcessRunner.run("/bin/sleep", ["2"], environment: environment, timeout: 0.1)
        expect(timeout.status == 124 && timeout.output.contains("timed out"), "process runner should terminate stalled commands")
    }

    private static func utcDate(day: Int, month: Int, year: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components) ?? .distantPast
    }

    private static func testWeeklyResetFormatter() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!

        let saturday = utcDate(day: 15, month: 8, year: 2026, hour: 12, minute: 0, calendar: utc)
        expect(
            WeeklyResetFormatter.text(from: "82% (Fri 09:00)", now: saturday, calendar: utc) == "FRI · 21 Aug",
            "reset formatter should resolve the nearest upcoming weekday from the usage string"
        )

        let fridayMorning = utcDate(day: 21, month: 8, year: 2026, hour: 8, minute: 0, calendar: utc)
        expect(
            WeeklyResetFormatter.text(from: "82% (Fri 09:00)", now: fridayMorning, calendar: utc) == "FRI · 21 Aug",
            "reset formatter should keep today when the reset time is still upcoming"
        )

        let fridayAfterReset = utcDate(day: 21, month: 8, year: 2026, hour: 10, minute: 0, calendar: utc)
        expect(
            WeeklyResetFormatter.text(from: "82% (Fri 09:00)", now: fridayAfterReset, calendar: utc) == "FRI · 28 Aug",
            "reset formatter should jump to next week once today's reset has fired"
        )

        expect(
            WeeklyResetFormatter.text(from: "82% (Fri)", now: fridayAfterReset, calendar: utc) == "FRI · 28 Aug",
            "day-only reset text should pick next week when the day matches today"
        )

        expect(
            WeeklyResetFormatter.text(from: "82% (09:00)", now: saturday, calendar: utc) == "09:00",
            "reset formatter should fall back to the raw inner text when no weekday is parseable"
        )

        expect(
            WeeklyResetFormatter.text(from: "82% (Sat 09:00)", now: saturday, calendar: utc) == "SAT · 22 Aug",
            "reset formatter should resolve non-Friday weekdays"
        )

        expect(
            WeeklyResetFormatter.text(from: "--", now: saturday, calendar: utc) == "--",
            "dash usage without a parenthesized value should pass through untouched"
        )
    }

    private static func testTokenRefreshRequest() {
        let request = CodexTokenRefresher.makeRequest(refreshToken: "rt-123")
        expect(request.httpMethod == "POST", "token refresh should use POST")
        expect(request.url == CodexTokenRefresher.refreshEndpoint, "token refresh should target the OAuth token endpoint")
        expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json", "token refresh should send JSON")
        guard let bodyData = request.httpBody,
              let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: String] else {
            expect(false, "token refresh body should be parseable JSON")
            return
        }
        expect(body["grant_type"] == "refresh_token", "token refresh should request the refresh_token grant")
        expect(body["refresh_token"] == "rt-123", "token refresh should carry the refresh token")
        expect(body["client_id"] == CodexTokenRefresher.clientID, "token refresh should use the OpenAI app client id")
        expect(body["scope"] == "openid profile email", "token refresh should request the codex scope")
    }

    private static func testTokenRefreshResponseParsing() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let successJSON = #"{"access_token":"at-new","refresh_token":"rt-new","id_token":"id-new"}"#
        guard let successData = successJSON.data(using: .utf8) else {
            expect(false, "success fixture should be UTF-8")
            return
        }
        if case .success(let payload) = CodexTokenRefresher.parseResponse(
            data: successData,
            statusCode: 200,
            previousRefreshToken: "rt-old",
            now: now
        ) {
            expect(payload.accessToken == "at-new", "token refresh should surface the new access token")
            expect(payload.refreshToken == "rt-new", "token refresh should surface the new refresh token")
            expect(payload.idToken == "id-new", "token refresh should surface the id token")
            expect(payload.lastRefresh == now, "token refresh should stamp the refresh time")
        } else {
            expect(false, "a well-formed 200 response should parse as success")
        }

        let rotatedOnlyJSON = #"{"access_token":"at-rotated"}"#
        guard let rotatedData = rotatedOnlyJSON.data(using: .utf8) else {
            expect(false, "rotated fixture should be UTF-8")
            return
        }
        if case .success(let payload) = CodexTokenRefresher.parseResponse(
            data: rotatedData,
            statusCode: 200,
            previousRefreshToken: "rt-old",
            now: now
        ) {
            expect(payload.refreshToken == "rt-old", "token refresh should keep the previous refresh token when omitted")
        } else {
            expect(false, "an access-token-only 200 response should still succeed")
        }

        let missingTokenJSON = #"{"id_token":"id-only"}"#
        guard let missingTokenData = missingTokenJSON.data(using: .utf8) else {
            expect(false, "missing-token fixture should be UTF-8")
            return
        }
        if case .invalidResponse = CodexTokenRefresher.parseResponse(
            data: missingTokenData,
            statusCode: 200,
            previousRefreshToken: "rt-old",
            now: now
        ) {} else {
            expect(false, "a 200 response without access_token should be invalid")
        }

        let garbage = Data("not json".utf8)
        if case .invalidResponse = CodexTokenRefresher.parseResponse(
            data: garbage,
            statusCode: 200,
            previousRefreshToken: "rt-old",
            now: now
        ) {} else {
            expect(false, "non-JSON 200 response should be invalid")
        }
    }

    private static func testTokenRefreshErrorMapping() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)

        let expiredJSON = #"{"error":{"code":"refresh_token_expired"}}"#
        if case .expired = CodexTokenRefresher.parseResponse(
            data: Data(expiredJSON.utf8),
            statusCode: 400,
            previousRefreshToken: "rt",
            now: now
        ) {} else {
            expect(false, "refresh_token_expired should map to expired")
        }

        let reusedJSON = #"{"error":{"code":"refresh_token_reused"}}"#
        if case .reused = CodexTokenRefresher.parseResponse(
            data: Data(reusedJSON.utf8),
            statusCode: 400,
            previousRefreshToken: "rt",
            now: now
        ) {} else {
            expect(false, "refresh_token_reused should map to reused")
        }

        let revokedJSON = #"{"error":"invalid_grant"}"#
        if case .revoked = CodexTokenRefresher.parseResponse(
            data: Data(revokedJSON.utf8),
            statusCode: 400,
            previousRefreshToken: "rt",
            now: now
        ) {} else {
            expect(false, "invalid_grant should map to revoked")
        }

        let invalidatedJSON = #"{"code":"refresh_token_invalidated"}"#
        if case .revoked = CodexTokenRefresher.parseResponse(
            data: Data(invalidatedJSON.utf8),
            statusCode: 400,
            previousRefreshToken: "rt",
            now: now
        ) {} else {
            expect(false, "refresh_token_invalidated should map to revoked")
        }

        if case .expired = CodexTokenRefresher.parseResponse(
            data: Data(),
            statusCode: 401,
            previousRefreshToken: "rt",
            now: now
        ) {} else {
            expect(false, "a bare 401 should map to expired")
        }

        if case .invalidResponse = CodexTokenRefresher.parseResponse(
            data: Data(),
            statusCode: 500,
            previousRefreshToken: "rt",
            now: now
        ) {} else {
            expect(false, "an unknown status should surface as invalid response")
        }
    }

    private static func testTokenRefreshAgePolicy() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        expect(CodexTokenRefresher.shouldRefresh(lastRefresh: nil, now: now), "a missing refresh stamp should be eligible for refresh")
        expect(
            !CodexTokenRefresher.shouldRefresh(lastRefresh: now.addingTimeInterval(-60), now: now),
            "a recent refresh stamp should not trigger proactive refresh"
        )
        expect(
            CodexTokenRefresher.shouldRefresh(lastRefresh: now.addingTimeInterval(-3 * 24 * 60 * 60), now: now),
            "a three-day-old refresh stamp should trigger proactive refresh"
        )
    }

    private static func testCodexAuthDateParsing() {
        let parsed = CodexAuthDate.parseLastRefresh("2026-08-12T09:30:00Z")
        expect(parsed != nil, "an ISO8601 refresh stamp should parse")
        if let parsed {
            let formatter = ISO8601DateFormatter()
            expect(formatter.string(from: parsed) == "2026-08-12T09:30:00Z", "an ISO8601 refresh stamp should keep its instant")
        }

        let fractional = CodexAuthDate.parseLastRefresh("2026-08-12T09:30:00.123Z")
        expect(fractional != nil, "a fractional-seconds refresh stamp should parse")

        expect(CodexAuthDate.parseLastRefresh(nil) == nil, "a missing refresh stamp should stay nil")
        expect(CodexAuthDate.parseLastRefresh("not-a-date") == nil, "a malformed refresh stamp should stay nil")

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let roundtrip = CodexAuthDate.parseLastRefresh(CodexAuthDate.encode(now))
        expect(roundtrip != nil, "an encoded refresh stamp should roundtrip")
        if let roundtrip {
            expect(abs(roundtrip.timeIntervalSince(now)) < 1, "an encoded refresh stamp should preserve the instant")
        }
    }

    private static func testCodexAuthTokenWriter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("accounts.auth.json")

        let fixture: [String: Any] = [
            "tokens": [
                "access_token": "at-old",
                "refresh_token": "rt-old",
                "account_id": "acc-1",
                "unrelated": "keep-me"
            ],
            "oauth_account": ["id": "123"]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture)
        try data.write(to: fileURL)

        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let failure = CodexAuthTokenWriter.applyTokenUpdate(
            to: fileURL,
            expectedAccountID: "acc-1",
            accessToken: "at-new",
            refreshToken: "rt-new",
            lastRefresh: now
        )
        expect(failure == nil, "a matching auth file should update without failure")

        guard let updatedData = try? Data(contentsOf: fileURL),
              let updated = (try? JSONSerialization.jsonObject(with: updatedData)) as? [String: Any],
              let tokens = updated["tokens"] as? [String: Any] else {
            expect(false, "the updated auth file should remain readable JSON")
            return
        }
        expect(tokens["access_token"] as? String == "at-new", "token update should write the new access token")
        expect(tokens["refresh_token"] as? String == "rt-new", "token update should write the new refresh token")
        expect(tokens["last_refresh"] as? String == CodexAuthDate.encode(now), "token update should write the refresh stamp")
        expect(tokens["account_id"] as? String == "acc-1", "token update should preserve the account id")
        expect(tokens["unrelated"] as? String == "keep-me", "token update should preserve unrelated token fields")
        expect((updated["oauth_account"] as? [String: Any])?["id"] as? String == "123", "token update should preserve the outer auth object")

        let mismatch = CodexAuthTokenWriter.applyTokenUpdate(
            to: fileURL,
            expectedAccountID: "acc-2",
            accessToken: "at-should-not-stick",
            refreshToken: "rt-should-not-stick",
            lastRefresh: now
        )
        expect(mismatch != nil, "a concurrent account switch should abort the token update")
        guard let afterMismatchData = try? Data(contentsOf: fileURL),
              let afterMismatch = (try? JSONSerialization.jsonObject(with: afterMismatchData)) as? [String: Any],
              let afterMismatchTokens = afterMismatch["tokens"] as? [String: Any] else {
            expect(false, "the aborted auth file should remain readable JSON")
            return
        }
        expect(afterMismatchTokens["access_token"] as? String == "at-new", "an aborted update must not clobber the file")

        let missingFailure = CodexAuthTokenWriter.applyTokenUpdate(
            to: root.appendingPathComponent("does-not-exist.json"),
            expectedAccountID: "acc-1",
            accessToken: "at",
            refreshToken: "rt",
            lastRefresh: now
        )
        expect(missingFailure != nil, "a missing auth file should report a failure")
    }

    private static func testPoolHistoryStore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("pool-history.jsonl")

        let t0 = Date(timeIntervalSince1970: 1_750_000_000)
        let sampleA = PoolHistorySample(
            ts: t0,
            n: 5,
            poolTotal: 500,
            accounts: [
                PoolAccountSample(key: "a", remaining: 100),
                PoolAccountSample(key: "b", remaining: 100)
            ]
        )
        expect(PoolHistoryStore.poolAverage(n: 0, poolTotal: 0) == 0, "an empty pool should average to zero")
        expect(PoolHistoryStore.poolAverage(n: 5, poolTotal: 500) == 100, "the pool average should normalize by account count")

        let t1 = t0.addingTimeInterval(30 * 60)
        let sampleB = PoolHistorySample(ts: t1, n: 5, poolTotal: 460, accounts: [])
        let duplicateInBucket = PoolHistorySample(ts: t1.addingTimeInterval(60), n: 5, poolTotal: 458, accounts: [])
        try PoolHistoryStore.write([sampleA], to: fileURL, now: t1)
        expect(
            PoolHistoryStore.load(from: fileURL) == [sampleA],
            "a written history file should round-trip its samples"
        )

        let corrupt = root.appendingPathComponent("corrupt.jsonl")
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        var corruptText = "not-json\n"
        if let encoded = try? isoEncoder.encode(sampleA), let line = String(data: encoded, encoding: .utf8) {
            corruptText += line + "\n"
        }
        try corruptText.write(to: corrupt, atomically: true, encoding: .utf8)
        expect(
            PoolHistoryStore.load(from: corrupt) == [sampleA],
            "a corrupt line should be skipped without failing the load"
        )

        var running = PoolHistoryStore.load(from: fileURL)
        running.append(contentsOf: [sampleB, duplicateInBucket])
        try PoolHistoryStore.write(running, to: fileURL, now: t1)
        let deduped = PoolHistoryStore.load(from: fileURL)
        expect(deduped.count == 2, "samples in different buckets should both load")
        expect(deduped.last?.poolTotal == 458, "the newest sample in a bucket should win")

        let older = PoolHistorySample(ts: t0.addingTimeInterval(-100 * 24 * 60 * 60), n: 5, poolTotal: 400, accounts: [])
        let pruned = PoolHistoryStore.pruned([older, sampleA], now: t0)
        expect(pruned == [sampleA], "samples beyond the retention window should be pruned")

        expect(
            PoolHistoryStore.shouldRecord(lastSample: nil, poolAverage: 92, now: t0),
            "a missing last sample should always record"
        )
        expect(
            !PoolHistoryStore.shouldRecord(lastSample: sampleA, poolAverage: 99.9, now: t0.addingTimeInterval(60), minimumDelta: 1.0),
            "a fresh sample with a small delta should not record"
        )
        expect(
            PoolHistoryStore.shouldRecord(lastSample: sampleA, poolAverage: 90, now: t0.addingTimeInterval(60)),
            "a fresh sample with a large delta should record"
        )
        expect(
            PoolHistoryStore.shouldRecord(lastSample: sampleA, poolAverage: 99, now: t0.addingTimeInterval(30 * 60)),
            "a stale sample should record even without a large delta"
        )
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    /// Generates 30-minute pool samples with a linear weekly burn from 100%,
/// starting at a UTC week start, ending no later than `until` (defaults to the
/// full `weeks` span). The last sample never lies after `until`.
    private static func poolSamples(
        startingAt start: Date,
        weeks: Int,
        burnPerWeek: Double,
        accountCount: Int = 5,
        until now: Date? = nil
    ) -> [PoolHistorySample] {
        let weekDuration = 7 * 24 * 60 * 60
        let interval = 30 * 60.0
        let limit = start.addingTimeInterval(Double(weeks) * Double(weekDuration))
        let end = min(limit, now ?? limit)
        var samples: [PoolHistorySample] = []
        var ts = start
        while ts <= end {
            let elapsedWeeks = ts.timeIntervalSince(start) / Double(weekDuration)
            let average = max(0, 100 - burnPerWeek * elapsedWeeks)
            samples.append(PoolHistorySample(ts: ts, n: accountCount, poolTotal: average * Double(accountCount), accounts: []))
            ts = ts.addingTimeInterval(interval)
        }
        return samples
    }

    private static func testWeekCurveBuilder() {
        let calendar = utcCalendar
        let arbitrary = Date(timeIntervalSince1970: 1_752_000_000)
        let start = WeekCurveBuilder.weekStart(of: arbitrary, calendar: calendar)
        expect(calendar.component(.weekday, from: start) == calendar.firstWeekday, "the week start should be the calendar's first weekday")
        expect(start <= arbitrary && arbitrary.timeIntervalSince(start) < 7 * 24 * 60 * 60, "the week start should bracket the sample date")

        let samples = poolSamples(startingAt: start, weeks: 2, burnPerWeek: 25)
        let curves = WeekCurveBuilder.weekCurves(from: samples, calendar: calendar)
        expect(curves.count == 2, "two calendar weeks should build two curves")
        for (_, curve) in curves {
            expect(curve.count == WeekCurveBuilder.gridPointCount, "a week curve should fill the grid")
            for index in 1..<curve.count {
                expect(curve[index] <= curve[index - 1] + 1e-9, "a week curve should be monotone non-increasing")
            }
        }
        guard let firstCurve = curves.first?.curve else {
            expect(false, "the first week curve should exist")
            return
        }
        let middle = WeekCurveBuilder.interpolate(curve: firstCurve, at: 0.5)
        expect(abs(middle - 87.5) < 0.6, "halfway through a 25pt/week burn should sit near 87.5")
        expect(WeekCurveBuilder.interpolate(curve: firstCurve, at: 0) == firstCurve[0], "interpolate at zero should return the start value")
    }

    private static func testDailyPoolAggregator() {
        let calendar = utcCalendar
        let day0 = Date(timeIntervalSince1970: 1_752_000_000)
        let day1 = day0.addingTimeInterval(24 * 3600)
        let day2 = day1.addingTimeInterval(24 * 3600)
        let day3 = day2.addingTimeInterval(24 * 3600)

        func poolSample(_ ts: Date, total: Double) -> PoolHistorySample {
            PoolHistorySample(ts: ts, n: 1, poolTotal: total, accounts: [])
        }

        let history = [
            poolSample(day0.addingTimeInterval(60 * 60), total: 90),
            poolSample(day0.addingTimeInterval(2 * 60 * 60), total: 80), // day 0: min 80, end 80
            poolSample(day1.addingTimeInterval(60 * 60), total: 65),
            poolSample(day1.addingTimeInterval(2 * 60 * 60), total: 70), // day 1: min 65, end 70 (refill)
            // day 2 has no samples at all
            poolSample(day3.addingTimeInterval(60 * 60), total: 60) // day 3
        ]

        let points = DailyPoolAggregator.dailyPoints(
            from: history,
            dayCount: 4,
            now: day3.addingTimeInterval(2 * 3600),
            calendar: calendar
        )
        expect(points.count == 3, "the window should keep days 0, 1 and 3 and skip the empty day 2")
        expect(points.first?.value == 80, "the day value should be the day minimum")
        expect(points.first?.endValue == 80, "endValue should be the last sample of the day")
        expect(points.first?.sampleCount == 2, "sampleCount should count the day's samples")
        expect(points[1].value == 65, "a refill within a day should keep the minimum as the value")
        expect(points[1].endValue == 70, "endValue should be the newest sample, not the day minimum")
        expect(points[1].sampleCount == 2, "two samples in one day should be counted")
        expect(points.last?.value == 60, "the final day should keep its single sample value")
        expect(points.last?.sampleCount == 1, "a single-sample day counts one sample")

        let later = day3.addingTimeInterval(10 * 24 * 3600)
        let outside = DailyPoolAggregator.dailyPoints(from: history, dayCount: 3, now: later, calendar: calendar)
        expect(outside.isEmpty, "samples older than the window must be excluded")

        let empty = DailyPoolAggregator.dailyPoints(from: [], dayCount: 3, now: day3, calendar: calendar)
        expect(empty.isEmpty, "empty history should produce no points")
    }

    private static func testPaceEstimatorForecast() {
        let calendar = utcCalendar
        let arbitrary = Date(timeIntervalSince1970: 1_752_000_000)
        let start = WeekCurveBuilder.weekStart(of: arbitrary, calendar: calendar)
        let now = start.addingTimeInterval(3.5 * 7 * 24 * 60 * 60) // middle of week 4

        // Fast burn: 25 pt per week ends exactly at the end of week 4.
        let fast = poolSamples(startingAt: start, weeks: 4, burnPerWeek: 25, until: now)
        let fastForecast = PaceEstimator.forecast(samples: fast, now: now, calendar: calendar)
        expect(!fastForecast.insufficientData, "four weeks of history should be enough data")
        if let eolDate = fastForecast.eolDate {
            expect(eolDate > now, "the EOL should lie in the future")
            expect(eolDate < now.addingTimeInterval(7 * 24 * 60 * 60), "a 25pt/week burn should end within the current week")
        } else {
            expect(false, "a draining pool should produce an EOL date")
        }

        // Slow burn: 10 pt per week survives every week.
        let slow = poolSamples(startingAt: start, weeks: 4, burnPerWeek: 10, until: now)
        let slowForecast = PaceEstimator.forecast(samples: slow, now: now, calendar: calendar)
        expect(!slowForecast.insufficientData, "the slow history should still be enough data")
        expect(slowForecast.willLastToReset, "a 10pt/week burn should survive the week")
        expect(slowForecast.eolDate == nil, "a surviving pool should have no EOL")
        expect((slowForecast.runOutProbability ?? 0) < 0.5, "the burn-out probability should stay low")

        // Almost no history: one day of samples.
        let sparse = poolSamples(startingAt: start, weeks: 1, burnPerWeek: 25).filter { $0.ts <= start.addingTimeInterval(24 * 60 * 60) }
        let sparseForecast = PaceEstimator.forecast(samples: sparse, now: sparse.last?.ts ?? now, calendar: calendar)
        expect(sparseForecast.insufficientData, "less than two days of history should be reported as insufficient")

        // Partial week only (no complete weeks): a sharp drop should still yield a near-term EOL.
        let partialStart = Date(timeIntervalSince1970: 1_752_000_000)
        var partial: [PoolHistorySample] = []
        var partialTs = partialStart
        var partialValue = 100.0
        while partialValue > 25 {
            partial.append(PoolHistorySample(ts: partialTs, n: 5, poolTotal: partialValue * 5, accounts: []))
            partialTs = partialTs.addingTimeInterval(60 * 60)
            partialValue -= 75.0 / 72.0
        }
        let partialNow = partial.last?.ts ?? partialStart
        let partialForecast = PaceEstimator.forecast(samples: partial, now: partialNow, calendar: calendar)
        expect(!partialForecast.insufficientData, "three days in the current week should produce an approximate forecast")
        expect(partialForecast.eolDate != nil, "a sharp drop within the partial week should forecast an EOL")
    }

    private static func testPoolVerdict() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let reset = now.addingTimeInterval(3 * 86_400)
        let eolSoon = now.addingTimeInterval(2 * 86_400)
        let eolLater = now.addingTimeInterval(5 * 86_400)

        let deficit = PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 100, eolDate: eolSoon, resetDate: reset, hasSufficientHistory: true, now: now)
        expect(deficit.kind == .notEnough, "exhaustion before reset should be not enough")
        expect(deficit.resetInterval == 3 * 86_400, "reset interval should use the captured now")
        expect(deficit.exhaustionInterval == 2 * 86_400, "exhaustion interval should use the captured now")
        expect(deficit.margin == -86_400, "exhaustion before reset should have a negative margin")

        let buffer = PoolVerdict.evaluate(poolTotal: 500, burnPerDay: 120, eolDate: eolLater, resetDate: reset, hasSufficientHistory: true, now: now)
        expect(buffer.kind == .enough, "high burn should still be enough when exhaustion follows reset")
        expect(buffer.margin == 2 * 86_400, "exhaustion after reset should have a positive margin")

        let boundary = PoolVerdict.evaluate(poolTotal: 300, burnPerDay: 100, eolDate: reset, resetDate: reset, hasSufficientHistory: true, now: now)
        expect(boundary.kind == .enough, "an exhaustion event exactly at reset should not be negative")
        expect(boundary.margin == 0, "equal events should have a zero margin")

        let fallbackEOL = now.addingTimeInterval(2 * 86_400)
        let fallback = PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 100, eolDate: nil, resetDate: reset, hasSufficientHistory: true, now: now)
        expect(fallback.exhaustionInterval == fallbackEOL.timeIntervalSince(now), "missing forecast EOL should use the linear pool/burn fallback")

        let collectingInputs: [PoolVerdict] = [
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 100, eolDate: eolLater, resetDate: reset, hasSufficientHistory: false, now: now),
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: nil, eolDate: eolLater, resetDate: reset, hasSufficientHistory: true, now: now),
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 0, eolDate: eolLater, resetDate: reset, hasSufficientHistory: true, now: now),
            PoolVerdict.evaluate(poolTotal: .infinity, burnPerDay: 100, eolDate: eolLater, resetDate: reset, hasSufficientHistory: true, now: now),
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: .nan, eolDate: eolLater, resetDate: reset, hasSufficientHistory: true, now: now),
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 100, eolDate: eolLater, resetDate: nil, hasSufficientHistory: true, now: now),
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 100, eolDate: now.addingTimeInterval(-1), resetDate: reset, hasSufficientHistory: true, now: now),
            PoolVerdict.evaluate(poolTotal: 200, burnPerDay: 100, eolDate: eolLater, resetDate: now, hasSufficientHistory: true, now: now)
        ]
        expect(collectingInputs.allSatisfy { $0.kind == .collecting }, "incomplete, non-finite, and invalid dates should collect")
        expect(collectingInputs.allSatisfy { $0.margin == nil }, "collecting must not expose display intervals")
    }

    private static func testPoolHistorySampleResetsAtCoding() {
        let reset = Date(timeIntervalSince1970: 1_900_000_000)
        let sample = PoolHistorySample(ts: Date(timeIntervalSince1970: 1_800_000_000), n: 5, poolTotal: 220, accounts: [], resetsAt: reset)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(sample)) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        expect(text.contains("resetsAt"), "an encoded sample should include resetsAt")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try? decoder.decode(PoolHistorySample.self, from: data)
        expect(decoded?.resetsAt == reset, "resetsAt should survive an encode/decode round trip")
        let legacy = Data(#"{"ts":"2026-08-15T19:40:56Z","n":5,"poolTotal":33,"accounts":[]}"#.utf8)
        let legacyDecoded = try? decoder.decode(PoolHistorySample.self, from: legacy)
        expect(legacyDecoded?.resetsAt == nil, "a legacy line without resetsAt should decode as nil")
    }

    private static func testResetChanceParsing() {
        let realFixture = #"{"mode":"model","probabilities":{"raw_24h":0.29446105287468405,"raw_48h":0.5022147940893007,"rounded_24h":30,"rounded_48h":50},"confidence":"medium","last_reset_at":"2026-08-13T01:01:37.000Z","cadence":{"recent_median_days":2.3}} "#.utf8
        if case .success(let forecast) = ResetChanceClient.parseResponse(data: Data(realFixture), statusCode: 200) {
            expect(forecast.rounded24h == 30, "real fixture should surface rounded 24h as 30")
            expect(forecast.rounded48h == 50, "real fixture should surface rounded 48h as 50")
        } else {
            expect(false, "a well-formed 200 response should parse as success")
        }

        let missing48Fixture = #"{"probabilities":{"rounded_24h":30}}"#.utf8
        if case .failure = ResetChanceClient.parseResponse(data: Data(missing48Fixture), statusCode: 200) {} else {
            expect(false, "a response without rounded_48h should be invalid")
        }

        let noProbabilitiesFixture = #"{"mode":"model","confidence":"low"}"#.utf8
        if case .failure = ResetChanceClient.parseResponse(data: Data(noProbabilitiesFixture), statusCode: 200) {} else {
            expect(false, "a response without a probabilities object should be invalid")
        }

        let garbage = Data("not json".utf8)
        if case .failure = ResetChanceClient.parseResponse(data: garbage, statusCode: 200) {} else {
            expect(false, "non-JSON 200 response should be invalid")
        }

        if case .failure = ResetChanceClient.parseResponse(data: Data(realFixture), statusCode: 500) {} else {
            expect(false, "a non-200 status should be a failure even with a valid body")
        }
    }

    // MARK: - Bundled marketplace fixtures

    private static func makePluginManifest(root: URL, pluginID: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("plugins/\(pluginID)/.codex-plugin"),
            withIntermediateDirectories: true
        )
    }

    private static func makeCompleteMarketplace(root: URL) throws {
        for id in BundledMarketplaceInspector.expectedPluginIDs() {
            try makePluginManifest(root: root, pluginID: id)
        }
    }

    private static func makeHomeSnapshot(home: URL) throws -> URL {
        let snapshot = home.appendingPathComponent(".codex/.tmp/bundled-marketplaces")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        return snapshot
    }

    private static func makeFakeApp(home: URL) throws -> String {
        let app = home.appendingPathComponent("ChatGPT.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents/Resources/plugins"),
            withIntermediateDirectories: true
        )
        return app.path
    }

    // MARK: - Bundled marketplace inspector

    private static func testBundledMarketplaceSnapshotOk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makeCompleteMarketplace(root: snapshots.appendingPathComponent("openai-bundled"))
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .ok, "a snapshot with all expected plugin manifests should be ok")
    }

    private static func testBundledMarketplaceSnapshotIncomplete() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makeCompleteMarketplace(root: snapshots.appendingPathComponent("openai-bundled"))
        try FileManager.default.removeItem(
            at: snapshots.appendingPathComponent("openai-bundled/plugins/browser")
        )
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .incomplete(missing: ["browser"]), "a snapshot missing the browser manifest should be incomplete")
    }

    private static func testBundledMarketplaceSnapshotAbsent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .absent, "a missing snapshot directory should be absent")
    }

    private static func testBundledMarketplaceSnapshotMissingManifest() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makeCompleteMarketplace(root: snapshots.appendingPathComponent("openai-bundled"))
        try FileManager.default.removeItem(
            at: snapshots.appendingPathComponent("openai-bundled/plugins/computer-use/.codex-plugin")
        )
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .incomplete(missing: ["computer-use"]), "a plugin without its manifest should be treated as missing")
    }

    private static func testBundledMarketplaceAppSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = try makeFakeApp(home: root)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled"),
            withIntermediateDirectories: true
        )
        let source = BundledMarketplaceInspector.appMarketplaceSource(appPath: app)
        expect(source != nil, "the app marketplace source should be found under Contents/Resources/plugins/openai-bundled")
        expect(source?.lastPathComponent == "openai-bundled", "the found source should be the openai-bundled marketplace")

        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        expect(BundledMarketplaceInspector.appMarketplaceSource(appPath: empty.path) == nil, "an app without the marketplace should return nil")
    }

    // MARK: - Bundled marketplace repairer

    private static func testBundledMarketplaceRepairNoop() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makeCompleteMarketplace(root: snapshots.appendingPathComponent("openai-bundled"))
        let app = try makeFakeApp(home: root)
        try makeCompleteMarketplace(root: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled"))
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(homeDirectory: root.path, appPath: app)
        expect(outcome == .ok, "a healthy snapshot should repair to ok without changes")
        let backups = try FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        expect(!backups.contains { $0.hasPrefix("bundled-marketplaces.bak.") }, "a healthy snapshot should not create a backup")
    }

    private static func testBundledMarketplaceRepairFromApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makePluginManifest(root: snapshots.appendingPathComponent("openai-bundled"), pluginID: "chrome")
        let app = try makeFakeApp(home: root)
        try makeCompleteMarketplace(root: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled"))
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(homeDirectory: root.path, appPath: app)
        expect(outcome == .repairedFromApp, "an incomplete snapshot with an app reference should be repaired from the app")
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .ok, "the snapshot should be complete after repairing from the app")
        let backups = try FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        expect(backups.contains { $0.hasPrefix("bundled-marketplaces.bak.") }, "the stale snapshot should be moved to a backup before copying")
    }

    private static func testBundledMarketplaceRepairRestoresAbsentSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try makeHomeSnapshot(home: root)
        let app = try makeFakeApp(home: root)
        try makeCompleteMarketplace(
            root: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled")
        )

        let outcome = BundledMarketplaceRepairer.repairIfNeeded(homeDirectory: root.path, appPath: app)

        expect(outcome == .repairedFromApp, "an absent bundled snapshot should be restored from the app")
        expect(
            BundledMarketplaceInspector.snapshotState(homeDirectory: root.path) == .ok,
            "restoring an absent bundled snapshot should produce a complete marketplace"
        )
    }

    private static func testBundledMarketplaceRepairRefreshesOutdatedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makeCompleteMarketplace(root: snapshots.appendingPathComponent("openai-bundled"))
        let app = try makeFakeApp(home: root)
        let appMarketplace = URL(fileURLWithPath: app)
            .appendingPathComponent("Contents/Resources/plugins/openai-bundled")
        try makeCompleteMarketplace(root: appMarketplace)
        try makePluginManifest(root: appMarketplace, pluginID: "deep-research")

        let outcome = BundledMarketplaceRepairer.repairIfNeeded(homeDirectory: root.path, appPath: app)

        expect(outcome == .repairedFromApp, "a snapshot missing a plugin shipped by the app should be refreshed")
        expect(
            FileManager.default.fileExists(
                atPath: snapshots.appendingPathComponent("openai-bundled/plugins/deep-research/.codex-plugin").path
            ),
            "repair should restore every plugin shipped by the app marketplace"
        )
    }

    private static func testBundledMarketplaceRepairNoApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makePluginManifest(root: snapshots.appendingPathComponent("openai-bundled"), pluginID: "chrome")
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(
            homeDirectory: root.path,
            appPath: root.appendingPathComponent("Missing.app").path
        )
        expect(outcome == .noAppFound, "repair without an app reference should report noAppFound")
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .incomplete(missing: ["browser", "computer-use"]), "repair without an app reference must not touch the snapshot")
    }

    private static func testBundledMarketplaceRepairStaleMove() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makePluginManifest(root: snapshots.appendingPathComponent("openai-bundled"), pluginID: "chrome")
        let app = try makeFakeApp(home: root) // app exists but has no marketplace inside
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(homeDirectory: root.path, appPath: app)
        expect(outcome == .repairedByStaleMove, "an app without a marketplace should fall back to moving the stale snapshot aside")
        let entries = try FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        expect(entries.contains { $0.hasPrefix("bundled-marketplaces.bak.") }, "the stale snapshot should be moved aside for regeneration")
        expect(!entries.contains("openai-bundled"), "the stale snapshot should no longer be in place")
    }

    private static func testBundledMarketplaceRepairRollback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makePluginManifest(root: snapshots.appendingPathComponent("openai-bundled"), pluginID: "chrome")
        let app = try makeFakeApp(home: root)
        // the app marketplace itself is incomplete (only chrome) — the copy will fail verification
        try makePluginManifest(root: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled"), pluginID: "chrome")
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(homeDirectory: root.path, appPath: app)
        if case .failed = outcome {} else {
            expect(false, "a copy that fails verification should report failed")
        }
        let state = BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
        expect(state == .incomplete(missing: ["browser", "computer-use"]), "the original snapshot should be restored after a failed repair")
        let backups = try FileManager.default.contentsOfDirectory(atPath: snapshots.path)
        expect(!backups.contains { $0.hasPrefix("bundled-marketplaces.bak.") }, "the backup should be restored, leaving no stale backup behind")
    }

    private static func testBundledMarketplaceRepairReinstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makePluginManifest(root: snapshots.appendingPathComponent("openai-bundled"), pluginID: "chrome")
        let app = try makeFakeApp(home: root)
        try makeCompleteMarketplace(root: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled"))
        let home = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let configText = """
        [plugins."chrome@openai-bundled"]
        enabled = true

        [plugins."browser@openai-bundled"]
        enabled = true
        """
        try configText.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        var calls: [[String]] = []
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(
            homeDirectory: root.path,
            appPath: app,
            codexExecutable: "/usr/bin/true",
            pluginRunner: { _, arguments, _ in
                calls.append(arguments)
                return CommandResult(status: 0, output: "ok")
            }
        )
        expect(outcome == .repairedFromApp, "reinstall success should still report repairedFromApp")
        let pluginCalls = calls.filter { $0.first == "plugin" }
        expect(pluginCalls.contains { $0.contains("chrome@openai-bundled") }, "enabled chrome plugin should be reinstalled")
        expect(pluginCalls.contains { $0.contains("browser@openai-bundled") }, "enabled browser plugin should be reinstalled")
        expect(!pluginCalls.contains { $0.contains("computer-use@openai-bundled") }, "a plugin absent from config should not be reinstalled")
    }

    private static func testBundledMarketplaceRepairReinstallsNewBundledPlugin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makeCompleteMarketplace(root: snapshots.appendingPathComponent("openai-bundled"))
        let app = try makeFakeApp(home: root)
        let appMarketplace = URL(fileURLWithPath: app)
            .appendingPathComponent("Contents/Resources/plugins/openai-bundled")
        try makeCompleteMarketplace(root: appMarketplace)
        try makePluginManifest(root: appMarketplace, pluginID: "visualize")
        let home = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try """
        [plugins."visualize@openai-bundled"]
        enabled = true
        """.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        var calls: [[String]] = []

        _ = BundledMarketplaceRepairer.repairIfNeeded(
            homeDirectory: root.path,
            appPath: app,
            codexExecutable: "/usr/bin/true",
            pluginRunner: { _, arguments, _ in
                calls.append(arguments)
                return CommandResult(status: 0, output: "ok")
            }
        )

        expect(
            calls.contains(["plugin", "add", "visualize@openai-bundled"]),
            "an enabled plugin discovered in the app marketplace should be reinstalled"
        )
    }

    private static func testBundledMarketplaceRepairReinstallFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshots = try makeHomeSnapshot(home: root)
        try makePluginManifest(root: snapshots.appendingPathComponent("openai-bundled"), pluginID: "chrome")
        let app = try makeFakeApp(home: root)
        try makeCompleteMarketplace(root: URL(fileURLWithPath: app).appendingPathComponent("Contents/Resources/plugins/openai-bundled"))
        let home = root.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let configText = """
        [plugins."chrome@openai-bundled"]
        enabled = true
        """
        try configText.write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let outcome = BundledMarketplaceRepairer.repairIfNeeded(
            homeDirectory: root.path,
            appPath: app,
            codexExecutable: "/usr/bin/true",
            pluginRunner: { _, _, _ in CommandResult(status: 1, output: "boom") }
        )
        if case .failed = outcome {} else {
            expect(false, "a failed plugin reinstall should report failed")
        }
        expect(
            BundledMarketplaceInspector.snapshotState(homeDirectory: root.path)
                == .incomplete(missing: ["browser", "computer-use"]),
            "a failed bundled plugin reinstall should restore the previous snapshot"
        )
    }

    private static func testReferencePluginInventory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let remoteCache = root.appendingPathComponent(".codex/plugins/cache/openai-curated-remote")
        for id in ["superpowers", "cloudflare", "product-design"] {
            try FileManager.default.createDirectory(
                at: remoteCache.appendingPathComponent(id),
                withIntermediateDirectories: true
            )
        }

        let remoteIDs = ReferencePluginInventory.remotePluginIDs(homeDirectory: root.path)
        expect(
            remoteIDs == ["cloudflare", "product-design", "superpowers"],
            "remote reference inventory should contain sorted immediate cache directories"
        )

        let config = """
        [plugins."github@openai-curated"]
        enabled = true

        [plugins."superpowers@openai-curated"]
        enabled = false

        [plugins."browser@openai-bundled"]
        enabled = true

        [plugins."documents@openai-primary-runtime"]
        enabled = true
        """
        expect(
            ReferencePluginInventory.curatedPluginIDs(configText: config) == ["github"],
            "curated reference inventory should include only enabled openai-curated plugins"
        )
    }

    private static func testReferencePluginCaptureRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let remoteCache = home.appendingPathComponent(".codex/plugins/cache/openai-curated-remote")
        try FileManager.default.createDirectory(
            at: remoteCache.appendingPathComponent("product-design/0.1.52"),
            withIntermediateDirectories: true
        )
        try Data("payload".utf8).write(to: remoteCache.appendingPathComponent("product-design/0.1.52/SKILL.md"))
        try """
        [plugins."github@openai-curated"]
        enabled = true
        """.write(
            to: home.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let store = root.appendingPathComponent("reference-plugins")

        let outcome = ReferencePluginStore.capture(homeDirectory: home.path, storeDirectory: store)
        expect(outcome == .captured(remoteCount: 1, curatedCount: 1), "capture should report saved plugin counts")
        guard let loaded = ReferencePluginStore.load(storeDirectory: store) else {
            expect(false, "a captured reference should load")
            return
        }
        expect(loaded.manifest.schemaVersion == 1, "captured reference should use schema version 1")
        expect(loaded.manifest.remotePluginIDs == ["product-design"], "captured manifest should list remote plugins")
        expect(loaded.manifest.curatedPluginIDs == ["github"], "captured manifest should list curated plugins")
        expect(
            FileManager.default.fileExists(
                atPath: loaded.remoteCacheURL.appendingPathComponent("product-design/0.1.52/SKILL.md").path
            ),
            "capture should preserve remote plugin files"
        )
    }

    private static func testReferencePluginCapturePreservesPreviousReference() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let validHome = root.appendingPathComponent("valid-home")
        try FileManager.default.createDirectory(
            at: validHome.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/vercel"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: validHome.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        try "".write(
            to: validHome.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let store = root.appendingPathComponent("reference-plugins")
        _ = ReferencePluginStore.capture(homeDirectory: validHome.path, storeDirectory: store)

        let outcome = ReferencePluginStore.capture(
            homeDirectory: root.appendingPathComponent("missing-home").path,
            storeDirectory: store
        )

        if case .failed = outcome {} else {
            expect(false, "capture without a remote cache should fail")
        }
        expect(
            ReferencePluginStore.load(storeDirectory: store)?.manifest.remotePluginIDs == ["vercel"],
            "failed capture should preserve the previous reference"
        )
    }

    private static func testReferencePluginLoadRejectsModifiedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["vercel"])
        let payload = reference.remoteCacheURL.appendingPathComponent("vercel/1.0.0/payload.txt")
        try Data("corrupt".utf8).write(to: payload)

        expect(
            ReferencePluginStore.load(storeDirectory: root.appendingPathComponent("reference-plugins")) == nil,
            "reference loading should reject modified plugin files even when IDs still match"
        )
    }

    private static func testReferencePluginMarketplacePreparation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["cloudflare", "product-design"])

        let outcome = ReferencePluginMarketplace.prepare(reference: reference)
        guard case .prepared(let marketplaceURL, let pluginIDs) = outcome else {
            expect(false, "a valid reference should produce a local marketplace")
            return
        }

        expect(
            pluginIDs == ["cloudflare", "product-design"],
            "the local marketplace should contain every remote reference plugin"
        )
        expect(
            FileManager.default.fileExists(
                atPath: marketplaceURL.appendingPathComponent(".agents/plugins/marketplace.json").path
            ),
            "the local marketplace should contain a marketplace manifest"
        )
        for id in pluginIDs {
            expect(
                FileManager.default.fileExists(
                    atPath: marketplaceURL.appendingPathComponent("plugins/\(id)/.codex-plugin/plugin.json").path
                ),
                "the local marketplace should flatten the saved version for \(id)"
            )
        }
    }

    private static func testReferencePluginMarketplaceDetectsChangedInstalledPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["cloudflare", "product-design"])
        guard case .prepared(let marketplaceURL, _) = ReferencePluginMarketplace.prepare(reference: reference) else {
            expect(false, "a valid reference should prepare before installed package comparison")
            return
        }
        let installedCache = root.appendingPathComponent("installed-cache")
        for id in ["cloudflare", "product-design"] {
            let destination = installedCache.appendingPathComponent("\(id)/1.0.0")
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: marketplaceURL.appendingPathComponent("plugins/\(id)"),
                to: destination
            )
        }
        try Data("stale".utf8).write(
            to: installedCache.appendingPathComponent("cloudflare/1.0.0/payload.txt")
        )

        expect(
            ReferencePluginMarketplace.staleInstalledPluginIDs(
                marketplaceURL: marketplaceURL,
                installedCacheURL: installedCache,
                pluginIDs: ["cloudflare", "product-design"]
            ) == ["cloudflare"],
            "content comparison should mark only the changed installed package as stale"
        )
    }

    private static func testReferencePluginMarketplaceRejectsMissingDigests() {
        expect(
            !ReferencePluginMarketplace.packageDigestsMatch(installed: nil, reference: nil),
            "two failed package fingerprints must not be treated as matching content"
        )
        expect(
            ReferencePluginMarketplace.packageDigestsMatch(installed: "same", reference: "same"),
            "two non-nil equal package fingerprints should match"
        )
    }

    private static func testReferencePluginCaptureReportsRollbackFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstHome = root.appendingPathComponent("first-home")
        let secondHome = root.appendingPathComponent("second-home")
        for (home, plugin) in [(firstHome, "vercel"), (secondHome, "cloudflare")] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/\(plugin)"),
                withIntermediateDirectories: true
            )
            try "".write(
                to: home.appendingPathComponent(".codex/config.toml"),
                atomically: true,
                encoding: .utf8
            )
        }
        let store = root.appendingPathComponent("reference-plugins")
        _ = ReferencePluginStore.capture(homeDirectory: firstHome.path, storeDirectory: store)

        let outcome = ReferencePluginStore.capture(
            homeDirectory: secondHome.path,
            storeDirectory: store,
            fileManager: FailingSwapAndRestoreFileManager()
        )

        if case .failed(let reason) = outcome {
            expect(reason.contains("rollback failed"), "capture should report a failed reference rollback")
        } else {
            expect(false, "capture with a failed swap and restore should fail")
        }
        let parentEntries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        expect(
            parentEntries.contains(where: { $0.hasPrefix(".reference-plugins.backup.") }),
            "capture should preserve an unrestored reference backup"
        )
    }

    private static func testReferencePluginCaptureRequiresReadableConfig() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/vercel"),
            withIntermediateDirectories: true
        )

        let outcome = ReferencePluginStore.capture(
            homeDirectory: home.path,
            storeDirectory: root.appendingPathComponent("reference-plugins")
        )

        if case .failed = outcome {} else {
            expect(false, "capture should fail when config.toml cannot be read")
        }
    }

    private static func makeReferencePluginFixture(root: URL, remoteIDs: [String]) throws -> ReferencePluginStore.LoadedReference {
        let canonicalHome = root.appendingPathComponent("canonical-home")
        for id in remoteIDs {
            let version = canonicalHome.appendingPathComponent(
                ".codex/plugins/cache/openai-curated-remote/\(id)/1.0.0"
            )
            try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)
            try Data(id.utf8).write(to: version.appendingPathComponent("payload.txt"))
            try FileManager.default.createDirectory(
                at: version.appendingPathComponent(".codex-plugin"),
                withIntermediateDirectories: true
            )
            try Data("{\"name\":\"\(id)\",\"version\":\"1.0.0\"}".utf8).write(
                to: version.appendingPathComponent(".codex-plugin/plugin.json")
            )
        }
        try FileManager.default.createDirectory(
            at: canonicalHome.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        try "".write(
            to: canonicalHome.appendingPathComponent(".codex/config.toml"),
            atomically: true,
            encoding: .utf8
        )
        let store = root.appendingPathComponent("reference-plugins")
        _ = ReferencePluginStore.capture(homeDirectory: canonicalHome.path, storeDirectory: store)
        return ReferencePluginStore.load(storeDirectory: store)!
    }

    private static func testReferencePluginReconcileExactMatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(
            root: root,
            remoteIDs: ["cloudflare", "product-design", "vercel"]
        )
        let targetHome = root.appendingPathComponent("target-home")
        for id in ["canva", "posthog", "vercel"] {
            try FileManager.default.createDirectory(
                at: targetHome.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/\(id)"),
                withIntermediateDirectories: true
            )
        }

        let outcome = ReferencePluginReconciler.reconcile(
            homeDirectory: targetHome.path,
            reference: reference
        )

        expect(
            outcome == .applied(
                added: ["cloudflare", "product-design"],
                removed: ["canva", "posthog"]
            ),
            "reconcile should report exact additions and removals"
        )
        expect(
            ReferencePluginInventory.remotePluginIDs(homeDirectory: targetHome.path) == ["cloudflare", "product-design", "vercel"],
            "reconcile should make the active remote set exactly match the reference"
        )
    }

    private static func testReferencePluginReconcileRestoresChangedFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["vercel"])
        let targetHome = root.appendingPathComponent("target-home")
        let targetPayload = targetHome.appendingPathComponent(
            ".codex/plugins/cache/openai-curated-remote/vercel/1.0.0/payload.txt"
        )
        try FileManager.default.createDirectory(
            at: targetPayload.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("wrong-version".utf8).write(to: targetPayload)

        let outcome = ReferencePluginReconciler.reconcile(homeDirectory: targetHome.path, reference: reference)
        let restoredPayload = try String(contentsOf: targetPayload, encoding: .utf8)

        expect(outcome == .applied(added: [], removed: []), "changed reference files should trigger reconciliation")
        expect(
            restoredPayload == "vercel",
            "reconciliation should restore the exact saved plugin files"
        )
    }

    private static func testReferencePluginReconcileIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["cloudflare", "vercel"])
        let targetHome = root.appendingPathComponent("target-home")
        try FileManager.default.createDirectory(
            at: targetHome.appendingPathComponent(".codex/plugins/cache/openai-curated-remote"),
            withIntermediateDirectories: true
        )

        _ = ReferencePluginReconciler.reconcile(homeDirectory: targetHome.path, reference: reference)
        let second = ReferencePluginReconciler.reconcile(homeDirectory: targetHome.path, reference: reference)

        expect(second == .alreadyMatched, "repeated reconciliation should be a no-op")
    }

    private static func testReferencePluginReconcileWithoutReference() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/canva"),
            withIntermediateDirectories: true
        )

        let outcome = ReferencePluginReconciler.reconcile(homeDirectory: root.path, reference: nil)

        expect(outcome == .noReference, "missing reference should be reported")
        expect(
            ReferencePluginInventory.remotePluginIDs(homeDirectory: root.path) == ["canva"],
            "missing reference should leave the active cache unchanged"
        )
    }

    private static func testReferencePluginReconcileRollsBackFailedSwap() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["vercel"])
        let targetHome = root.appendingPathComponent("target-home")
        try FileManager.default.createDirectory(
            at: targetHome.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/canva"),
            withIntermediateDirectories: true
        )

        let outcome = ReferencePluginReconciler.reconcile(
            homeDirectory: targetHome.path,
            reference: reference,
            fileManager: FailingSecondMoveFileManager()
        )

        if case .failed = outcome {} else {
            expect(false, "a staged swap failure should be reported")
        }
        expect(
            ReferencePluginInventory.remotePluginIDs(homeDirectory: targetHome.path) == ["canva"],
            "a staged swap failure should restore the target account cache"
        )
    }

    private static func testReferencePluginReconcileReportsRollbackFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["vercel"])
        let targetHome = root.appendingPathComponent("target-home")
        try FileManager.default.createDirectory(
            at: targetHome.appendingPathComponent(".codex/plugins/cache/openai-curated-remote/canva"),
            withIntermediateDirectories: true
        )

        let outcome = ReferencePluginReconciler.reconcile(
            homeDirectory: targetHome.path,
            reference: reference,
            fileManager: FailingSwapAndRestoreFileManager()
        )

        if case .failed(let reason) = outcome {
            expect(reason.contains("rollback failed"), "a failed restore should be reported explicitly")
        } else {
            expect(false, "a failed restore should fail reconciliation")
        }
        let cacheParent = targetHome.appendingPathComponent(".codex/plugins/cache")
        let entries = try FileManager.default.contentsOfDirectory(atPath: cacheParent.path)
        expect(
            entries.contains(where: { $0.hasPrefix("openai-curated-remote.backup.") }),
            "a failed restore should preserve the backup for recovery"
        )
    }

    private static func testCuratedPluginPlan() {
        expect(
            CuratedPluginPlan.commands(
                referenceIDs: ["github"],
                installedIDs: ["canva", "github", "browser@openai-bundled"]
            ) == [["plugin", "remove", "canva@openai-curated"]],
            "curated plan should remove non-reference curated plugins and ignore system selectors"
        )
        expect(
            CuratedPluginPlan.commands(
                referenceIDs: ["github", "vercel"],
                installedIDs: ["github"]
            ) == [["plugin", "add", "vercel@openai-curated"]],
            "curated plan should add missing reference plugins"
        )
    }

    private static func testReferenceMarketplacePluginPlan() {
        let config = """
        [plugins."cloudflare@account-switcher-reference"]
        enabled = true

        [plugins."obsolete@account-switcher-reference"]
        enabled = true
        """
        expect(
            ReferencePluginInventory.pluginIDs(
                configText: config,
                marketplace: ReferencePluginMarketplace.name
            ) == ["cloudflare", "obsolete"],
            "plugin inventory should read an explicit marketplace"
        )
        expect(
            PluginInstallPlan.commands(
                referenceIDs: ["cloudflare", "product-design"],
                installedIDs: ["cloudflare", "obsolete"],
                marketplace: ReferencePluginMarketplace.name
            ) == [
                ["plugin", "remove", "obsolete@account-switcher-reference"],
                ["plugin", "add", "product-design@account-switcher-reference"],
            ],
            "the local marketplace plan should remove stale plugins before adding missing references"
        )
    }

    private static func testReferenceMarketplacePluginPlanReinstallsChangedPackage() {
        expect(
            PluginInstallPlan.commands(
                referenceIDs: ["cloudflare", "product-design"],
                installedIDs: ["cloudflare", "product-design"],
                staleIDs: ["product-design"],
                marketplace: ReferencePluginMarketplace.name
            ) == [
                ["plugin", "remove", "product-design@account-switcher-reference"],
                ["plugin", "add", "product-design@account-switcher-reference"],
            ],
            "a changed saved package should be removed and reinstalled even when its ID is unchanged"
        )
    }

    private static func testReferenceMarketplacePluginReconcile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["cloudflare", "product-design"])
        let home = root.appendingPathComponent("target-home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: configURL, atomically: true, encoding: .utf8)
        var commands: [[String]] = []

        let outcome = ReferenceMarketplacePluginReconciler.reconcile(
            homeDirectory: home.path,
            reference: reference
        ) { arguments in
            commands.append(arguments)
            var config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
            if arguments.prefix(3) == ["plugin", "marketplace", "add"] {
                config += "\n[marketplaces.account-switcher-reference]\nsource_type = \"local\"\n"
            } else if arguments.prefix(2) == ["plugin", "add"], let selector = arguments.last {
                config += "\n[plugins.\"\(selector)\"]\nenabled = true\n"
                let pluginID = selector.split(separator: "@", maxSplits: 1).first.map(String.init) ?? selector
                let source = reference.remoteCacheURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("local-marketplace/plugins/\(pluginID)")
                let destination = home.appendingPathComponent(
                    ".codex/plugins/cache/account-switcher-reference/\(pluginID)/1.0.0"
                )
                try? FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.copyItem(at: source, to: destination)
            }
            try? config.write(to: configURL, atomically: true, encoding: .utf8)
            return CommandResult(status: 0, output: "ok")
        }

        expect(outcome == .applied(changes: 3), "reference marketplace registration and installs should be reported")
        expect(
            commands.dropFirst() == [
                ["plugin", "add", "cloudflare@account-switcher-reference"],
                ["plugin", "add", "product-design@account-switcher-reference"],
            ],
            "every saved remote plugin should be installed from the local reference marketplace"
        )
    }

    private static func testReferenceMarketplacePluginReconcileReinstallsChangedPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["cloudflare"])
        let home = root.appendingPathComponent("target-home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [marketplaces.account-switcher-reference]
        source_type = "local"

        [plugins."cloudflare@account-switcher-reference"]
        enabled = true
        """.write(to: configURL, atomically: true, encoding: .utf8)
        let installedCache = home.appendingPathComponent(".codex/plugins/cache/account-switcher-reference")
        let installedPackage = installedCache.appendingPathComponent("cloudflare/0.9.0")
        try FileManager.default.createDirectory(
            at: installedPackage.appendingPathComponent(".codex-plugin"),
            withIntermediateDirectories: true
        )
        try Data("{\"name\":\"cloudflare\",\"version\":\"0.9.0\"}".utf8).write(
            to: installedPackage.appendingPathComponent(".codex-plugin/plugin.json")
        )
        try Data("stale".utf8).write(to: installedPackage.appendingPathComponent("payload.txt"))
        var commands: [[String]] = []

        let outcome = ReferenceMarketplacePluginReconciler.reconcile(
            homeDirectory: home.path,
            reference: reference
        ) { arguments in
            commands.append(arguments)
            let cacheRoot = home.appendingPathComponent(".codex/plugins/cache/account-switcher-reference/cloudflare")
            if arguments.prefix(2) == ["plugin", "remove"] {
                try? FileManager.default.removeItem(at: cacheRoot)
            } else if arguments.prefix(2) == ["plugin", "add"] {
                let source = reference.remoteCacheURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("local-marketplace/plugins/cloudflare")
                let destination = cacheRoot.appendingPathComponent("1.0.0")
                try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
                try? FileManager.default.copyItem(at: source, to: destination)
            }
            return CommandResult(status: 0, output: "ok")
        }

        expect(outcome == .applied(changes: 2), "a changed installed package should be reinstalled")
        expect(
            commands == [
                ["plugin", "remove", "cloudflare@account-switcher-reference"],
                ["plugin", "add", "cloudflare@account-switcher-reference"],
            ],
            "content drift should schedule remove then add for the same plugin ID"
        )
    }

    private static func testReferenceMarketplacePluginReconcileReportsCLIError() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let reference = try makeReferencePluginFixture(root: root, remoteIDs: ["cloudflare"])
        let home = root.appendingPathComponent("target-home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        [marketplaces.account-switcher-reference]
        source_type = "local"
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let outcome = ReferenceMarketplacePluginReconciler.reconcile(
            homeDirectory: home.path,
            reference: reference
        ) { arguments in
            CommandResult(status: 1, output: "forced failure: \(arguments.joined(separator: " "))")
        }

        if case .failed(let reason) = outcome {
            expect(
                reason.contains("plugin add cloudflare@account-switcher-reference failed"),
                "a local marketplace CLI failure should identify the failed command"
            )
        } else {
            expect(false, "a local marketplace CLI failure should fail reconciliation")
        }
    }

    private static func testCuratedPluginReconcileRollsBackPartialFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        let originalConfig = "[plugins.\"canva@openai-curated\"]\nenabled = true\n"
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)

        var commandCount = 0
        let outcome = CuratedPluginReconciler.reconcile(
            homeDirectory: home.path,
            referenceIDs: ["github"]
        ) { arguments in
            commandCount += 1
            if commandCount == 1 {
                try? "".write(to: configURL, atomically: true, encoding: .utf8)
                return CommandResult(status: 0, output: "removed")
            }
            return CommandResult(status: 1, output: "forced add failure")
        }

        if case .failed = outcome {} else {
            expect(false, "partial curated reconciliation should fail")
        }
        let restoredConfig = try String(contentsOf: configURL, encoding: .utf8)
        expect(
            restoredConfig == originalConfig,
            "partial curated reconciliation should restore the original config"
        )
    }

    private static func testPluginSyncStabilityTracker() {
        var tracker = PluginSyncStabilityTracker()
        expect(
            !tracker.observe(inventory: ["canva"], fingerprint: "digest-a"),
            "the first sync observation should not be stable"
        )
        expect(
            tracker.observe(inventory: ["canva"], fingerprint: "digest-a"),
            "two identical sync observations should be stable"
        )
        expect(
            !tracker.observe(inventory: ["canva"], fingerprint: "digest-b"),
            "a file content change should reset sync stability"
        )
        expect(
            !tracker.observe(inventory: ["canva", "posthog"], fingerprint: "digest-b"),
            "an inventory change should reset sync stability"
        )
        var cautiousTracker = PluginSyncStabilityTracker(requiredStableObservations: 4)
        expect(!cautiousTracker.observe(inventory: ["canva"], fingerprint: "digest-a"), "first cautious observation should wait")
        expect(!cautiousTracker.observe(inventory: ["canva"], fingerprint: "digest-a"), "second cautious observation should wait")
        expect(!cautiousTracker.observe(inventory: ["canva"], fingerprint: "digest-a"), "third cautious observation should wait")
        expect(cautiousTracker.observe(inventory: ["canva"], fingerprint: "digest-a"), "fourth cautious observation should stabilize")
    }

    private static func testReferencePluginTransactionRollsBackBothLayers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        let remoteCache = home.appendingPathComponent(".codex/plugins/cache/openai-curated-remote")
        let remotePayload = remoteCache.appendingPathComponent("canva/1.0.0/payload.txt")
        let referenceCache = home.appendingPathComponent(".codex/plugins/cache/account-switcher-reference")
        let referencePayload = referenceCache.appendingPathComponent("cloudflare/1.0.0/payload.txt")
        let originalConfig = "[plugins.\"canva@openai-curated\"]\nenabled = true\n"
        try FileManager.default.createDirectory(at: remotePayload.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try Data("canva".utf8).write(to: remotePayload)
        try FileManager.default.createDirectory(at: referencePayload.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cloudflare".utf8).write(to: referencePayload)

        let outcome = ReferencePluginTransaction.perform(homeDirectory: home.path) {
            try? FileManager.default.removeItem(at: remoteCache)
            try? FileManager.default.removeItem(at: referenceCache)
            try? "".write(to: configURL, atomically: true, encoding: .utf8)
            return "forced curated failure"
        }

        if case .failed(let reason) = outcome {
            expect(reason.contains("restored"), "plugin transaction should report successful rollback")
        } else {
            expect(false, "plugin transaction should fail when its operation fails")
        }
        let restoredConfig = try String(contentsOf: configURL, encoding: .utf8)
        let restoredPayload = try String(contentsOf: remotePayload, encoding: .utf8)
        let restoredReferencePayload = try String(contentsOf: referencePayload, encoding: .utf8)
        expect(
            restoredConfig == originalConfig,
            "plugin transaction should restore curated config"
        )
        expect(
            restoredPayload == "canva",
            "plugin transaction should restore remote cache files"
        )
        expect(
            restoredReferencePayload == "cloudflare",
            "plugin transaction should restore local reference cache files"
        )
    }

    private static func testReferencePluginTransactionRollsBackFailedFinalization() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        let originalConfig = "[plugins.\"github@openai-curated\"]\nenabled = true\n"
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try originalConfig.write(to: configURL, atomically: true, encoding: .utf8)

        let outcome = ReferencePluginTransaction.perform(
            homeDirectory: home.path,
            finalize: {
                .rollback(reason: "final plugin verification failed")
            },
            operation: {
                try? "changed".write(to: configURL, atomically: true, encoding: .utf8)
                return nil
            }
        )

        if case .failed(let reason) = outcome {
            expect(reason.contains("restored"), "failed finalization should report a verified rollback")
        } else {
            expect(false, "failed finalization should fail the transaction")
        }
        let restoredConfig = try String(contentsOf: configURL, encoding: .utf8)
        expect(
            restoredConfig == originalConfig,
            "failed finalization should restore the pre-reconciliation config"
        )
    }

    private static func testReferencePluginTransactionPreservesBackupWhenRollbackIsUnsafe() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home")
        let configURL = home.appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "original".write(to: configURL, atomically: true, encoding: .utf8)

        let outcome = ReferencePluginTransaction.perform(
            homeDirectory: home.path,
            finalize: {
                .preserveBackup(reason: "Codex could not be stopped")
            },
            operation: {
                try? "changed".write(to: configURL, atomically: true, encoding: .utf8)
                return nil
            }
        )

        if case .failed(let reason) = outcome {
            expect(reason.contains("backup kept"), "unsafe rollback should report the retained backup")
        } else {
            expect(false, "unsafe rollback should fail without touching live state")
        }
        let currentConfig = try String(contentsOf: configURL, encoding: .utf8)
        expect(
            currentConfig == "changed",
            "unsafe rollback should not overwrite config while Codex may still be running"
        )
        let codexDirectory = home.appendingPathComponent(".codex")
        let backups = try FileManager.default.contentsOfDirectory(atPath: codexDirectory.path)
        expect(
            backups.contains(where: { $0.hasPrefix(".reference-plugin-transaction.") }),
            "unsafe rollback should retain the transaction backup"
        )
        let backupName = backups.first(where: { $0.hasPrefix(".reference-plugin-transaction.") })!
        let savedConfig = try String(
            contentsOf: codexDirectory.appendingPathComponent("\(backupName)/config.toml"),
            encoding: .utf8
        )
        expect(savedConfig == "original", "retained transaction backup should include the original config")
    }

    private static func testProcessLookupPolicy() {
        expect(ProcessLookupPolicy.parse(status: 1, output: "") == .noMatches, "pgrep status 1 should mean no matches")
        expect(
            ProcessLookupPolicy.parse(status: 0, output: "12\n34\n") == .matches(["12", "34"]),
            "successful pgrep output should return process IDs"
        )
        if case .failed = ProcessLookupPolicy.parse(status: 2, output: "usage error") {} else {
            expect(false, "pgrep errors should not be treated as no matches")
        }
    }
}
