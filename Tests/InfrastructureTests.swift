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
        testTokenRefreshRequest()
        testTokenRefreshResponseParsing()
        testTokenRefreshErrorMapping()
        testTokenRefreshAgePolicy()
        testCodexAuthDateParsing()
        try testCodexAuthTokenWriter()
        try testPoolHistoryStore()
        testWeekCurveBuilder()
        testPaceEstimatorForecast()
        testPoolVerdict()
        testPoolHistorySampleResetsAtCoding()

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
        let reset = now.addingTimeInterval(3 * 24 * 3600)
        let eolSoon = now.addingTimeInterval(1 * 24 * 3600)
        expect(
            PoolVerdict.evaluate(poolTotal: 46, burnPerDay: 33, eolDate: eolSoon, resetDate: reset, accountCount: 5, now: now)
                == .notEnoughBeforeReset(eolDate: eolSoon, resetDate: reset),
            "EOL before reset should be reported as not-enough-before-reset")
        let eolLater = now.addingTimeInterval(5 * 24 * 3600)
        expect(
            PoolVerdict.evaluate(poolTotal: 400, burnPerDay: 33, eolDate: eolLater, resetDate: reset, accountCount: 5, now: now)
                == .enough(burnPerDay: 33, limitPerDay: 500.0 / 7.0, resetDate: reset),
            "burn below the weekly limit with reset before EOL should be enough")
        expect(
            PoolVerdict.evaluate(poolTotal: 400, burnPerDay: 120, eolDate: eolLater, resetDate: reset, accountCount: 5, now: now)
                == .burnExceedsLimit(burnPerDay: 120, limitPerDay: 500.0 / 7.0),
            "burn above the weekly limit should exceed even with a reset in sight")
        expect(
            PoolVerdict.evaluate(poolTotal: 400, burnPerDay: 33, eolDate: eolLater, resetDate: nil, accountCount: 5, now: now)
                == .unknown,
            "a missing reset date should fall back to unknown")
        let linearEOL = now.addingTimeInterval(46.0 / 33.0 * 24 * 3600)
        expect(
            PoolVerdict.evaluate(poolTotal: 46, burnPerDay: 33, eolDate: nil, resetDate: reset, accountCount: 5, now: now)
                == .notEnoughBeforeReset(eolDate: linearEOL, resetDate: reset),
            "a linear EOL fallback should be used when the forecast EOL is nil")
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
}
