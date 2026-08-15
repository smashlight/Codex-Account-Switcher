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
