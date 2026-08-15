import Darwin
import Foundation

struct CommandResult {
    let status: Int32
    let output: String
}

enum ProcessRunner {
    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Data()

        func store(_ data: Data) {
            lock.lock()
            value = data
            lock.unlock()
        }

        func load() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String],
        input: Data? = nil,
        timeout: TimeInterval = 15
    ) -> CommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        let outputBox = DataBox()
        let outputGroup = DispatchGroup()

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.standardInput = inputPipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: 127, output: error.localizedDescription)
        }

        outputGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            outputBox.store(outputPipe.fileHandleForReading.readDataToEndOfFile())
            outputGroup.leave()
        }

        if let inputPipe, let input {
            inputPipe.fileHandleForWriting.write(input)
            inputPipe.fileHandleForWriting.closeFile()
        }

        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let terminationDeadline = Date().addingTimeInterval(0.5)
            while process.isRunning && Date() < terminationDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        _ = outputGroup.wait(timeout: .now() + 2)
        var output = String(data: outputBox.load(), encoding: .utf8) ?? ""
        if timedOut {
            if !output.isEmpty, !output.hasSuffix("\n") {
                output += "\n"
            }
            output += "Command timed out after \(Int(timeout.rounded())) seconds."
        }
        return CommandResult(status: timedOut ? 124 : process.terminationStatus, output: output)
    }
}

enum ResetRefreshPolicy {
    static func shouldRefresh(lastRefresh: Date?, now: Date = Date(), ttl: TimeInterval, force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= ttl
    }
}

enum UsageRefreshPolicy {
    static func shouldRefresh(lastRefresh: Date?, now: Date = Date(), ttl: TimeInterval, force: Bool) -> Bool {
        guard !force else { return true }
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= ttl
    }
}

enum LastKnownGoodSnapshotPolicy {
    static func merged<Key: Hashable, Value>(
        current: [Key: Value],
        successful: [Key: Value],
        validKeys: Set<Key>
    ) -> [Key: Value] {
        var merged = current.filter { validKeys.contains($0.key) }
        for (key, value) in successful where validKeys.contains(key) {
            merged[key] = value
        }
        return merged
    }
}

enum ToolbarStatusFormatter {
    static func text(label: String, usage: String) -> String {
        "\(label)\(label.count > 1 ? " " : "")\(usage)"
    }
}

enum ComputerUsePluginLocator {
    static func latestApp(in versionsRoot: URL, fileManager: FileManager = .default) -> URL? {
        guard let versionDirectories = try? fileManager.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return versionDirectories
            .compactMap { directory -> (version: String, app: URL)? in
                let app = directory.appendingPathComponent("Codex Computer Use.app", isDirectory: true)
                guard fileManager.fileExists(atPath: app.path) else { return nil }
                return (directory.lastPathComponent, app)
            }
            .sorted { left, right in
                left.version.compare(right.version, options: .numeric) == .orderedDescending
            }
            .first?.app
    }

    static func latestApp(homeDirectory: String, fileManager: FileManager = .default) -> URL? {
        latestApp(
            in: URL(fileURLWithPath: homeDirectory)
                .appendingPathComponent(".codex/plugins/cache/openai-bundled/computer-use", isDirectory: true),
            fileManager: fileManager
        )
    }
}

enum AuthBackupPruner {
    @discardableResult
    static func prune(in directory: URL, keepingPerAccount keepCount: Int = 10, fileManager: FileManager = .default) -> Int {
        guard keepCount >= 0,
              let files = try? fileManager.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return 0
        }

        let backups = files.filter { $0.lastPathComponent.contains(".auth.json.bak.") }
        let grouped = Dictionary(grouping: backups) { url in
            url.lastPathComponent.components(separatedBy: ".bak.").first ?? url.lastPathComponent
        }

        var removed = 0
        for group in grouped.values {
            let ordered = group.sorted { left, right in
                let leftStamp = Int(left.lastPathComponent.components(separatedBy: ".bak.").last ?? "") ?? 0
                let rightStamp = Int(right.lastPathComponent.components(separatedBy: ".bak.").last ?? "") ?? 0
                if leftStamp != rightStamp { return leftStamp > rightStamp }
                let leftDate = (try? left.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? right.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            }

            for staleURL in ordered.dropFirst(keepCount) {
                do {
                    try fileManager.removeItem(at: staleURL)
                    removed += 1
                } catch {
                    continue
                }
            }
        }
        return removed
    }
}

struct HTTPPayload {
    let data: Data
    let statusCode: Int
}

enum CodexHTTPClient {
    static func send(_ request: URLRequest, retries: Int) async throws -> HTTPPayload {
        var lastError: Error?
        let attempts = max(1, retries + 1)

        for attempt in 0..<attempts {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if httpResponse.statusCode >= 500, attempt + 1 < attempts {
                    try await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
                    continue
                }
                return HTTPPayload(data: data, statusCode: httpResponse.statusCode)
            } catch {
                lastError = error
                guard attempt + 1 < attempts else { break }
                try await Task.sleep(nanoseconds: UInt64(250_000_000 * (attempt + 1)))
            }
        }

        throw lastError ?? URLError(.unknown)
    }
}

struct CodexTokenRefreshPayload {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let lastRefresh: Date
}

enum CodexTokenRefreshResult {
    case success(CodexTokenRefreshPayload)
    case notRefreshable
    case expired
    case revoked
    case reused
    case networkError(String)
    case invalidResponse(String)
}

enum CodexTokenRefresher {
    static let refreshEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let refreshAgeThreshold: TimeInterval = 3 * 24 * 60 * 60

    static func shouldRefresh(lastRefresh: Date?, now: Date = Date()) -> Bool {
        guard let lastRefresh else { return true }
        return now.timeIntervalSince(lastRefresh) >= refreshAgeThreshold
    }

    static func makeRequest(refreshToken: String, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(
            url: refreshEndpoint,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func parseResponse(
        data: Data,
        statusCode: Int,
        previousRefreshToken: String?,
        now: Date = Date()
    ) -> CodexTokenRefreshResult {
        guard statusCode == 200 else {
            return failureResult(statusCode: statusCode, data: data)
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .invalidResponse("Invalid JSON")
        }
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            return .invalidResponse("Missing access_token")
        }
        let refreshToken = (json["refresh_token"] as? String) ?? previousRefreshToken
        let idToken = json["id_token"] as? String
        return .success(CodexTokenRefreshPayload(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: idToken,
            lastRefresh: now
        ))
    }

    static func refresh(refreshToken: String, now: Date = Date()) async -> CodexTokenRefreshResult {
        guard !refreshToken.isEmpty else { return .notRefreshable }
        let payload: HTTPPayload
        do {
            payload = try await CodexHTTPClient.send(makeRequest(refreshToken: refreshToken), retries: 1)
        } catch {
            return .networkError(error.localizedDescription)
        }
        return parseResponse(
            data: payload.data,
            statusCode: payload.statusCode,
            previousRefreshToken: refreshToken,
            now: now
        )
    }

    private static func failureResult(statusCode: Int, data: Data) -> CodexTokenRefreshResult {
        if let code = errorCode(from: data) {
            switch code.lowercased() {
            case "refresh_token_expired":
                return .expired
            case "refresh_token_reused":
                return .reused
            case "invalid_grant", "refresh_token_invalidated":
                return .revoked
            default:
                break
            }
        }
        if statusCode == 401 {
            return .expired
        }
        return .invalidResponse("Status \(statusCode)")
    }

    private static func errorCode(from data: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            return code
        }
        if let error = json["error"] as? String { return error }
        return json["code"] as? String
    }
}

enum CodexAuthDate {
    static func parseLastRefresh(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    static func encode(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

enum CodexAuthTokenWriter {
    /// Atomically updates `tokens` in a Codex account auth file. Returns nil on
    /// success or a failure description. Aborts when the stored `account_id` no
    /// longer matches, so a concurrent codex-auth rewrite cannot be clobbered.
    static func applyTokenUpdate(
        to url: URL,
        expectedAccountID: String,
        accessToken: String,
        refreshToken: String?,
        lastRefresh: Date,
        fileManager: FileManager = .default
    ) -> String? {
        guard let data = try? Data(contentsOf: url),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var tokens = json["tokens"] as? [String: Any] else {
            return "auth file was not readable"
        }
        guard let storedAccountID = tokens["account_id"] as? String,
              storedAccountID == expectedAccountID else {
            return "auth file account changed concurrently"
        }
        tokens["access_token"] = accessToken
        if let refreshToken {
            tokens["refresh_token"] = refreshToken
        }
        tokens["last_refresh"] = CodexAuthDate.encode(lastRefresh)
        json["tokens"] = tokens
        guard let output = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
            return "auth file could not be serialized"
        }
        do {
            try output.write(to: url, options: [.atomic])
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

enum WeeklyResetFormatter {
    private static let weekdayIndexByToken: [String: Int] = [
        "mon": 2, "monday": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
        "sun": 1, "sunday": 1
    ]

    private static let abbreviationByWeekday: [Int: String] = [
        1: "SUN", 2: "MON", 3: "TUES", 4: "WED", 5: "THUR", 6: "FRI", 7: "SAT"
    ]

    static func text(from usage: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let open = usage.firstIndex(of: "("),
              let close = usage.firstIndex(of: ")"),
              open < close else {
            return "--"
        }
        let inner = String(usage[usage.index(after: open)..<close])
        guard let weekday = firstWeekday(in: inner) else {
            return inner.uppercased()
        }

        let target = upcomingDate(weekday: weekday, time: firstTime(in: inner), now: now, calendar: calendar)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM"
        let dayMonth = formatter.string(from: target)
        let abbreviation = abbreviationByWeekday[weekday] ?? "?"
        return "\(abbreviation) · \(dayMonth)"
    }

    private static func firstWeekday(in text: String) -> Int? {
        for token in text.split(whereSeparator: { !$0.isLetter }) {
            if let index = weekdayIndexByToken[String(token).lowercased()] {
                return index
            }
        }
        return nil
    }

    private static func firstTime(in text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?<!\d)(\d{1,2}):(\d{2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let minuteRange = Range(match.range(at: 2), in: text),
              let hour = Int(text[hourRange]),
              let minute = Int(text[minuteRange]) else {
            return nil
        }
        return (hour, minute)
    }

    private static func upcomingDate(
        weekday: Int,
        time: (hour: Int, minute: Int)?,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let today = calendar.component(.weekday, from: now)
        var daysAhead = (weekday - today + 7) % 7
        if daysAhead == 0 {
            let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
            let nowHour = nowComponents.hour ?? 0
            let nowMinute = nowComponents.minute ?? 0
            if let time {
                let sameHour = time.hour == nowHour
                let resetFiredToday = time.hour < nowHour || (sameHour && time.minute <= nowMinute)
                if !resetFiredToday {
                    return calendar.startOfDay(for: now)
                }
            }
            daysAhead = 7
        }
        guard let startOfDay = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: now),
              let target = calendar.date(byAdding: .day, value: daysAhead, to: startOfDay) else {
            return now
        }
        return target
    }
}
