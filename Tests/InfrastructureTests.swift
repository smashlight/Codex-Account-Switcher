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
}
