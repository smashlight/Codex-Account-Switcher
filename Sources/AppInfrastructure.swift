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

// MARK: - Pool usage history

struct PoolAccountSample: Codable, Equatable {
    let key: String
    let remaining: Double
}

/// One pool-wide sample: remaining percents per account, the pool total, and
/// the earliest weekly reset date captured from the live usage windows.
struct PoolHistorySample: Codable, Equatable {
    let ts: Date
    let n: Int
    let poolTotal: Double
    let accounts: [PoolAccountSample]
    let resetsAt: Date?
}

extension PoolHistorySample {
    /// Shorthand for history without a captured reset date (tests, legacy code).
    init(ts: Date, n: Int, poolTotal: Double, accounts: [PoolAccountSample]) {
        self.init(ts: ts, n: n, poolTotal: poolTotal, accounts: accounts, resetsAt: nil)
    }
}

/// JSONL store for pool-wide usage history (one sample per line, newest wins
/// within a sampling bucket). Pure logic so it can be unit-tested without AppKit.
enum PoolHistoryStore {
    static let samplingInterval: TimeInterval = 30 * 60
    static let retentionDays = 56
    static let minimumDeltaPoints = 1.0

    static func poolAverage(n: Int, poolTotal: Double) -> Double {
        n > 0 ? poolTotal / Double(n) : 0
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func fileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Codex Account Switcher", isDirectory: true)
            .appendingPathComponent("pool-history.jsonl")
    }

    /// Reads every valid line, keeps the newest sample per sampling bucket, and
    /// returns the history sorted chronologically. Corrupt lines are skipped.
    static func load(
        from url: URL? = nil,
        fileManager: FileManager = .default,
        interval: TimeInterval = Self.samplingInterval
    ) -> [PoolHistorySample] {
        let url = url ?? Self.fileURL(fileManager: fileManager)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        var samples: [PoolHistorySample] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = line.data(using: .utf8),
                  let sample = try? decoder.decode(PoolHistorySample.self, from: lineData) else {
                continue
            }
            samples.append(sample)
        }
        var newestByBucket: [Int64: PoolHistorySample] = [:]
        for sample in samples {
            let bucket = Int64(sample.ts.timeIntervalSince1970 / interval)
            if let existing = newestByBucket[bucket], existing.ts >= sample.ts { continue }
            newestByBucket[bucket] = sample
        }
        return newestByBucket.values.sorted { $0.ts < $1.ts }
    }

    /// Drops samples older than the retention window.
    static func pruned(
        _ samples: [PoolHistorySample],
        now: Date = Date(),
        retentionSeconds: TimeInterval = TimeInterval(Self.retentionDays * 24 * 60 * 60)
    ) -> [PoolHistorySample] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        return samples.filter { $0.ts >= cutoff }
    }

    /// Rewrites the whole history file atomically after pruning. Cheap at
    /// ~2 700 lines, and keeps the file consistent on every append.
    static func write(
        _ samples: [PoolHistorySample],
        to url: URL? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws {
        let url = url ?? Self.fileURL(fileManager: fileManager)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let kept = Self.pruned(samples, now: now)
        var lines: [String] = []
        lines.reserveCapacity(kept.count)
        for sample in kept {
            if let data = try? encoder.encode(sample),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// True when a new sample should be recorded: the pool average changed by
    /// more than the delta threshold, or the last sample is older than the
    /// sampling interval (or no history exists yet).
    static func shouldRecord(
        lastSample: PoolHistorySample?,
        poolAverage: Double,
        now: Date = Date(),
        interval: TimeInterval = samplingInterval,
        minimumDelta: Double = minimumDeltaPoints
    ) -> Bool {
        guard let lastSample else { return true }
        if now.timeIntervalSince(lastSample.ts) >= interval { return true }
        let previousAverage = Self.poolAverage(n: lastSample.n, poolTotal: lastSample.poolTotal)
        return abs(poolAverage - previousAverage) > minimumDelta
    }
}

// MARK: - Weekly pace curves

/// Builds calendar-week curves of the normalized pool average (remaining %),
/// mirroring CodexBar's `HistoricalUsagePace` in the remaining-percent frame:
/// monotone (running minimum) curves over a fixed 0...1 grid. A window reset
/// (a spike upward) never looks like gained headroom.
enum WeekCurveBuilder {
    static let gridPointCount = 100
    static let minimumSamplesPerWeek = 2

    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Splits samples into calendar weeks, one monotone curve per week.
    /// Weeks with fewer than two samples are skipped.
    static func weekCurves(
        from samples: [PoolHistorySample],
        calendar: Calendar,
        gridPointCount: Int = Self.gridPointCount,
        minimumSamples: Int = Self.minimumSamplesPerWeek
    ) -> [(start: Date, curve: [Double])] {
        guard gridPointCount >= 2 else { return [] }
        var grouped: [Date: [PoolHistorySample]] = [:]
        for sample in samples {
            let start = Self.weekStart(of: sample.ts, calendar: calendar)
            grouped[start, default: []].append(sample)
        }
        var curves: [(start: Date, curve: [Double])] = []
        for (start, weekSamples) in grouped {
            guard weekSamples.count >= minimumSamples else { continue }
            guard let duration = calendar.dateInterval(of: .weekOfYear, for: start)?.duration,
                  duration > 0,
                  let curve = Self.reconstructCurve(
                      samples: weekSamples,
                      start: start,
                      duration: duration,
                      gridPointCount: gridPointCount
                  ) else {
                continue
            }
            curves.append((start: start, curve: curve))
        }
        return curves.sorted { $0.start < $1.start }
    }

    /// Grid values are the running minimum of the observed pool average,
    /// interpolated on a fixed grid. Before the first sample of the week the
    /// curve holds the first observed value (no anchor to 100). After the grid
    /// is filled the last observed slope extends to the very end of the week,
    /// so a burn-out in the final half hour is not hidden by the last sample
    /// sitting at Sat 23:30.
    static func reconstructCurve(
        samples: [PoolHistorySample],
        start: Date,
        duration: TimeInterval,
        gridPointCount: Int
    ) -> [Double]? {
        let points = samples
            .map { sample -> (u: Double, value: Double) in
                let u = max(0, min(1, sample.ts.timeIntervalSince(start) / duration))
                let average = PoolHistoryStore.poolAverage(n: sample.n, poolTotal: sample.poolTotal)
                return (u: u, value: max(0, min(100, average)))
            }
            .sorted { $0.u < $1.u }
        guard let first = points.first else { return nil }

        var curve = Array(repeating: first.value, count: gridPointCount)
        var runningMin = first.value
        var pointIndex = 0
        for index in 0..<gridPointCount {
            let u = Double(index) / Double(gridPointCount - 1)
            while pointIndex < points.count, points[pointIndex].u <= u {
                runningMin = min(runningMin, points[pointIndex].value)
                pointIndex += 1
            }
            curve[index] = runningMin
        }
        guard points.count >= 2, let lastPoint = points.last else { return curve }
        let previousPoint = points[points.count - 2]
        let slopeStep = lastPoint.u - previousPoint.u
        if slopeStep > 1e-9, lastPoint.u < 1 {
            // A rising tail must not climb above the running minimum: the
            // week-end level is unknown, the observed floor is the honest
            // guess. Only the downward extension is allowed.
            let endValue = lastPoint.value + ((lastPoint.value - previousPoint.value) / slopeStep) * (1 - lastPoint.u)
            if endValue < curve[gridPointCount - 1] {
                curve[gridPointCount - 1] = max(0, endValue)
            }
        }
        return curve
    }

    static func interpolate(curve: [Double], at u: Double) -> Double {
        guard curve.count >= 2 else { return curve.first ?? 0 }
        let clamped = max(0, min(1, u))
        let position = clamped * Double(curve.count - 1)
        let lower = Int(floor(position))
        let upper = min(curve.count - 1, Int(ceil(position)))
        guard lower != upper else { return curve[lower] }
        let fraction = position - Double(lower)
        return curve[lower] * (1 - fraction) + curve[upper] * fraction
    }
}

// MARK: - Daily pool aggregation

/// One point per calendar day: the minimum pool average observed that day,
/// the last sample of the day (for tooltips), and the sample count.
struct DailyPoolPoint: Equatable {
    let date: Date
    let value: Double
    let endValue: Double
    let sampleCount: Int
}

/// Builds day bars from the raw sample history: groups samples by local
/// calendar day, keeps only the last `dayCount` days including today, and
/// drops days without samples entirely — a missing day must not render as a
/// zero bar, which would look like the pool ran out.
enum DailyPoolAggregator {
    static let defaultDayCount = 14

    static func dailyPoints(
        from samples: [PoolHistorySample],
        dayCount: Int = Self.defaultDayCount,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyPoolPoint] {
        guard dayCount >= 1, !samples.isEmpty else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) else { return [] }

        var grouped: [Date: [(ts: Date, value: Double)]] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.ts)
            guard day >= windowStart, day <= today else { continue }
            grouped[day, default: []].append((
                ts: sample.ts,
                value: min(100, max(0, PoolHistoryStore.poolAverage(n: sample.n, poolTotal: sample.poolTotal)))
            ))
        }
        return grouped.keys.sorted().compactMap { day in
            guard let samplesByDay = grouped[day], let first = samplesByDay.first else { return nil }
            let ordered = samplesByDay.sorted { $0.ts < $1.ts }
            return DailyPoolPoint(
                date: day,
                value: ordered.map(\.value).min() ?? first.value,
                endValue: ordered.last?.value ?? first.value,
                sampleCount: ordered.count
            )
        }
    }
}

// MARK: - Pool pace forecast

/// Forecasts when the pool average reaches 0%, following the CodexBar
/// algorithm: a weighted-median typical week mixed with a linear quota
/// baseline, each historical week extended by its end slope and shifted to the
/// observed level, then a weighted-median crossing time. In the
/// remaining-percent frame the quota baseline (100 → 0 over the week) is only
/// ever pessimistic, so no upside cap is applied — an easy history is a real
/// reserve, unlike CodexBar's used-percent case.
enum PaceEstimator {
    struct Forecast {
        let insufficientData: Bool
        let historyDays: Double
        let eolDate: Date?
        let willLastToReset: Bool
        let runOutProbability: Double?
        let expectedNow: Double
        let actualNow: Double
    }

    static let minimumHistorySeconds: TimeInterval = 2 * 24 * 60 * 60
    static let recencyTauWeeks = 2.0
    static let minimumCompleteWeeks = 1
    static let probabilitySmoothing = 0.5

    static func forecast(
        samples: [PoolHistorySample],
        now: Date = Date(),
        calendar: Calendar = .current,
        gridPointCount: Int = WeekCurveBuilder.gridPointCount
    ) -> Forecast {
        let historyDays = samples.isEmpty
            ? 0
            : max(0, now.timeIntervalSince(samples[0].ts)) / (24 * 60 * 60)
        guard let last = samples.last else {
            return Forecast(
                insufficientData: true, historyDays: historyDays,
                eolDate: nil, willLastToReset: true, runOutProbability: nil,
                expectedNow: 0, actualNow: 0
            )
        }
        let actual = PoolHistoryStore.poolAverage(n: last.n, poolTotal: last.poolTotal)

        guard now.timeIntervalSince(samples[0].ts) >= Self.minimumHistorySeconds else {
            return Forecast(
                insufficientData: true, historyDays: historyDays,
                eolDate: nil, willLastToReset: true, runOutProbability: nil,
                expectedNow: 0, actualNow: actual
            )
        }

        let curves = WeekCurveBuilder.weekCurves(from: samples, calendar: calendar, gridPointCount: gridPointCount)
        guard let currentInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return Forecast(insufficientData: false, historyDays: historyDays,
                            eolDate: nil, willLastToReset: true, runOutProbability: nil,
                            expectedNow: actual, actualNow: actual)
        }
        let currentStart = currentInterval.start
        let currentDuration = currentInterval.duration
        let uNow = max(0, min(1, now.timeIntervalSince(currentStart) / currentDuration))

        let scopedWeeks = curves.filter { $0.start < currentStart }
        guard scopedWeeks.count >= Self.minimumCompleteWeeks else {
            return Self.partialForecast(
                samples: samples,
                actual: actual,
                now: now,
                calendar: calendar,
                historyDays: historyDays
            )
        }

        let weightedWeeks = scopedWeeks.map { week in
            let ageWeeks = max(0, currentStart.timeIntervalSince(week.start) / currentDuration)
            let weight = exp(-ageWeeks / Self.recencyTauWeeks)
            return (week: week, weight: weight)
        }
        let totalWeight = weightedWeeks.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return Forecast(insufficientData: false, historyDays: historyDays,
                            eolDate: nil, willLastToReset: true, runOutProbability: nil,
                            expectedNow: actual, actualNow: actual)
        }

        // Weighted-median typical week, mixed with the linear quota baseline
        // (100 → 0 over the week). λ grows with the effective sample count, so
        // little history leans on the pessimistic quota instead.
        var medianCurve = Array(repeating: 0.0, count: gridPointCount)
        for index in 0..<gridPointCount {
            let values = weightedWeeks.map { $0.week.curve[index] }
            let weights = weightedWeeks.map(\.weight)
            medianCurve[index] = Self.weightedMedian(values: values, weights: weights)
        }
        let totalWeightSquared = weightedWeeks.reduce(0.0) { $0 + $1.weight * $1.weight }
        let nEff = totalWeightSquared > 0 ? totalWeight * totalWeight / totalWeightSquared : 0
        let lambda = Self.clamp((nEff - 2) / 6, lower: 0, upper: 1)
        var expectedCurve = Array(repeating: 0.0, count: gridPointCount)
        for index in 0..<gridPointCount {
            let u = Double(index) / Double(gridPointCount - 1)
            let linearBaseline = 100 * (1 - u)
            expectedCurve[index] = (lambda * medianCurve[index]) + ((1 - lambda) * linearBaseline)
        }

        let expectedNow = WeekCurveBuilder.interpolate(curve: expectedCurve, at: uNow)

        var weightedRunOutMass = 0.0
        var crossingCandidates: [(etaSeconds: TimeInterval, weight: Double)] = []
        for weighted in weightedWeeks {
            let curve = weighted.week.curve
            let shift = actual - WeekCurveBuilder.interpolate(curve: curve, at: uNow)
            if (curve.last ?? 0) + shift <= 0 {
                weightedRunOutMass += weighted.weight
                if let crossingU = Self.firstCrossing(
                    after: uNow,
                    curve: curve,
                    shift: shift,
                    actualAtNow: actual
                ) {
                    crossingCandidates.append((
                        etaSeconds: max(0, (crossingU - uNow) * currentDuration),
                        weight: weighted.weight
                    ))
                }
            }
        }

        let smoothedProbability = Self.clamp(
            (weightedRunOutMass + Self.probabilitySmoothing) / (totalWeight + 1),
            lower: 0,
            upper: 1
        )
        let willRunOut = smoothedProbability >= 0.5

        var eolDate: Date?
        if actual <= 0 {
            eolDate = now
        } else if willRunOut, !crossingCandidates.isEmpty {
            let values = crossingCandidates.map(\.etaSeconds)
            let weights = crossingCandidates.map(\.weight)
            eolDate = now.addingTimeInterval(max(0, Self.weightedMedian(values: values, weights: weights)))
        }

        return Forecast(
            insufficientData: false,
            historyDays: historyDays,
            eolDate: eolDate,
            willLastToReset: eolDate == nil,
            runOutProbability: smoothedProbability,
            expectedNow: expectedNow,
            actualNow: actual
        )
    }

    /// With no complete weeks yet, extrapolate the recent burn rate (last 12
    /// samples) to zero inside the current week. Marked as approximate by the
    /// UI. A flat recent history reports will-last.
    private static func partialForecast(
        samples: [PoolHistorySample],
        actual: Double,
        now: Date,
        calendar: Calendar,
        historyDays: Double
    ) -> Forecast {
        let willLast = Forecast(
            insufficientData: false, historyDays: historyDays,
            eolDate: nil, willLastToReset: true, runOutProbability: 0.5,
            expectedNow: actual, actualNow: actual
        )
        guard samples.count >= 4,
              let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
              let oldestSample = samples.suffix(12).first,
              let lastSample = samples.last else {
            return willLast
        }
        let span = lastSample.ts.timeIntervalSince(oldestSample.ts)
        guard span > 0 else { return willLast }
        let oldestAverage = PoolHistoryStore.poolAverage(n: oldestSample.n, poolTotal: oldestSample.poolTotal)
        let burnPerSecond = max(0, (oldestAverage - actual) / span)
        guard burnPerSecond > 1e-9 else { return willLast }
        let eolDate = now.addingTimeInterval(actual / burnPerSecond)
        if eolDate < weekInterval.end {
            return Forecast(insufficientData: false, historyDays: historyDays,
                            eolDate: eolDate, willLastToReset: false,
                            runOutProbability: 1, expectedNow: actual, actualNow: actual)
        }
        return willLast
    }

    static func firstCrossing(
        after uNow: Double,
        curve: [Double],
        shift: Double,
        actualAtNow: Double
    ) -> Double? {
        guard curve.count >= 2 else { return nil }
        let gridCount = curve.count
        let denominator = Double(gridCount - 1)
        var previousU = uNow
        var previousValue = actualAtNow
        let startIndex = min(gridCount - 1, max(1, Int(floor(uNow * denominator)) + 1))
        for index in startIndex..<gridCount {
            let u = Double(index) / denominator
            if u <= uNow + 1e-9 { continue }
            let value = curve[index] + shift
            if previousValue > 1e-9, value <= 1e-9 {
                let delta = previousValue - value
                let ratio = delta > 1e-9 ? (previousValue / delta) : 0
                return Self.clamp(previousU + ratio * (u - previousU), lower: uNow, upper: 1)
            }
            previousU = u
            previousValue = value
        }
        return nil
    }

    static func weightedMedian(values: [Double], weights: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let pairs = zip(values, weights).sorted { $0.0 < $1.0 }
        let total = max(1e-9, pairs.reduce(0.0) { $0 + $1.1 })
        var cumulative = 0.0
        for (value, weight) in pairs {
            cumulative += weight
            if cumulative >= total / 2 { return value }
        }
        return pairs.last?.0 ?? 0
    }

    static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(upper, value))
    }
}

/// The forecast row's verdict: does the pool last until the next weekly reset,
/// and is the daily burn below the weekly limit per day?
enum PoolVerdict: Equatable {
    case enough(burnPerDay: Double, limitPerDay: Double, resetDate: Date)
    case notEnoughBeforeReset(eolDate: Date, resetDate: Date)
    case burnExceedsLimit(burnPerDay: Double, limitPerDay: Double)
    case unknown

    static func evaluate(
        poolTotal: Double,
        burnPerDay: Double?,
        eolDate: Date?,
        resetDate: Date?,
        accountCount: Int,
        now: Date = Date()
    ) -> PoolVerdict {
        guard let resetDate, let burnPerDay, burnPerDay > 1e-9, poolTotal > 0 else {
            return .unknown
        }
        let limitPerDay = Double(max(1, accountCount)) * 100.0 / 7.0
        let effectiveEOL = eolDate ?? now.addingTimeInterval(poolTotal / burnPerDay * (24 * 60 * 60))
        if effectiveEOL < resetDate {
            return .notEnoughBeforeReset(eolDate: effectiveEOL, resetDate: resetDate)
        }
        if burnPerDay > limitPerDay {
            return .burnExceedsLimit(burnPerDay: burnPerDay, limitPerDay: limitPerDay)
        }
        return .enough(burnPerDay: burnPerDay, limitPerDay: limitPerDay, resetDate: resetDate)
    }
}
