import Foundation

@main
struct InfrastructureTests {
    private static var failures: [String] = []
    private static var assertionCount = 0

    static func main() throws {
        testResetRefreshPolicy()
        testUsageRefreshPolicy()
        testLastKnownGoodSnapshotPolicy()
        testToolbarStatusFormatting()
        try testComputerUsePluginDiscovery()
        try testBackupPruning()
        testProcessRunner()
        testWeeklyResetFormatter()

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
}
