import AppKit
import Foundation

/// Keeps screen-time files on disk without requiring the user to press Export.
/// The canonical raw store remains `screentime.db`; the JSON snapshot is a
/// convenience mirror, and `screen-time-auto.<format>` follows the user's last
/// export format/section/range settings.
@MainActor
final class ScreenTimeAutoSaveWriter {
    static let shared = ScreenTimeAutoSaveWriter()

    static let historyDays = 365

    static var fileURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md/screen-time-snapshot.json")
    }

    private let refreshInterval: TimeInterval = 5 * 60
    private let debounceInterval: TimeInterval = 10

    private var dataService: (any ScreenTimeDataServing)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pendingTask: Task<Void, Never>?
    private var isWriting = false
    private var needsWriteAfterCurrent = false

    private init() {}

    func start(dataService: any ScreenTimeDataServing) {
        self.dataService = dataService

        // Ensure the canonical SQLite file exists immediately on launch, even
        // before the first app-switch session is finalized.
        Task.detached(priority: .utility) {
            _ = try? HistoryStore.databaseURL()
        }

        if timer == nil {
            let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestWrite(delay: 0)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }

        if observers.isEmpty {
            let notificationCenter = NotificationCenter.default
            observers.append(notificationCenter.addObserver(
                forName: ActiveAppTracker.didRecordSessionNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestWrite()
                }
            })

            observers.append(notificationCenter.addObserver(
                forName: .NSCalendarDayChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestWrite(delay: 0)
                }
            })

            observers.append(notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.requestWrite()
                }
            })
        }

        requestWrite(delay: 1)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pendingTask?.cancel()
        pendingTask = nil

        let notificationCenter = NotificationCenter.default
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func requestWrite(delay: TimeInterval? = nil) {
        guard dataService != nil else { return }

        pendingTask?.cancel()
        let delay = delay ?? debounceInterval
        pendingTask = Task { [weak self] in
            if delay > 0 {
                let nanoseconds = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.writeNow()
        }
    }

    func writeNow() async {
        guard let dataService else { return }

        if isWriting {
            needsWriteAfterCurrent = true
            return
        }

        isWriting = true
        defer {
            isWriting = false
            if needsWriteAfterCurrent {
                needsWriteAfterCurrent = false
                requestWrite()
            }
        }

        let now = Date()

        do {
            let snapshot = try await Self.makeSnapshot(
                dataService: dataService,
                days: Self.historyDays,
                now: now
            )
            try Self.write(snapshot: snapshot, to: Self.fileURL)
        } catch {
            NSLog("[ScreenTimeAutoSaveWriter] Failed to write snapshot: \(error.localizedDescription)")
        }

        do {
            try await Self.writeFormattedAutoExport(dataService: dataService, now: now)
        } catch {
            NSLog("[ScreenTimeAutoSaveWriter] Failed to write formatted auto-export: \(error.localizedDescription)")
        }
    }

    private static func write(snapshot: ScreenTimeSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func writeFormattedAutoExport(
        dataService: any ScreenTimeDataServing,
        now: Date
    ) async throws {
        let settings = ExportSettings.load()
        let dateRange = settings.resolvedAutoSaveRelativeDateRange.dateRange(from: now)
        let filters = FilterSnapshot(
            startDate: dateRange.start,
            endDate: dateRange.end,
            granularity: .day
        )
        let template = settings.resolvedAutoSaveFilenameTemplate
        let config = CombinedExportConfig(
            sections: settings.resolvedAutoSaveExportSections,
            format: settings.resolvedAutoSaveExportFormat,
            filenameTemplate: template,
            includeTimestamp: false
        )
        let coordinator = ExportCoordinator(dataService: dataService)
        let writtenURL = try await coordinator.exportCombined(
            config: config,
            filters: filters,
            settings: settings,
            progress: nil
        )
        removeStaleFormattedAutoExports(keeping: writtenURL, filenameTemplate: template)
    }

    private static func removeStaleFormattedAutoExports(keeping writtenURL: URL, filenameTemplate: String) {
        let directory = writtenURL.deletingLastPathComponent()
        let currentPath = writtenURL.path
        let extensions = Set(ExportFormat.allCases.map(\.fileExtension))

        for fileExtension in extensions {
            let candidate = directory
                .appendingPathComponent(filenameTemplate)
                .appendingPathExtension(fileExtension)
            guard candidate.path != currentPath else { continue }
            try? FileManager.default.removeItem(at: candidate)
        }
    }

    private static func makeSnapshot(
        dataService: any ScreenTimeDataServing,
        days: Int,
        now: Date
    ) async throws -> ScreenTimeSnapshot {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: todayStart) ?? todayStart

        let filters = FilterSnapshot(
            startDate: firstDay,
            endDate: now,
            granularity: .day
        )

        var sessions = try await dataService.fetchRawSessions(filters: filters)

        let active = ActiveAppTracker.shared.snapshot()
        if active.isScreenActive,
           let appName = active.bundleID,
           let startedAt = active.switchTime,
           startedAt >= firstDay,
           startedAt <= now {
            let duration = now.timeIntervalSince(startedAt)
            if duration >= 2 {
                sessions.append(RawSession(
                    appName: appName,
                    startTime: startedAt,
                    endTime: now,
                    durationSeconds: duration
                ))
            }
        }

        var accumulators: [Date: DayAccumulator] = [:]
        for session in sessions where session.durationSeconds > 0 {
            let day = calendar.startOfDay(for: session.startTime)
            guard day >= firstDay, day <= todayStart else { continue }

            var accumulator = accumulators[day] ?? DayAccumulator(date: day)
            accumulator.add(session: session, calendar: calendar)
            accumulators[day] = accumulator
        }

        var snapshotDays: [ScreenTimeSnapshot.Day] = []
        var cursor = firstDay
        while cursor <= todayStart {
            let day = accumulators[cursor] ?? DayAccumulator(date: cursor)
            snapshotDays.append(day.snapshotDay)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return ScreenTimeSnapshot(
            generatedAt: now,
            fileURL: fileURL.path,
            canonicalDatabasePath: (try? HistoryStore.databaseURL().path) ?? HistoryStore.defaultDatabasePath,
            historyDays: days,
            device: DeviceInfo.current(),
            range: .init(startDate: firstDay, endDate: now),
            days: snapshotDays
        )
    }
}

private struct DayAccumulator {
    struct AppAccumulator {
        var totalSeconds: Double = 0
        var sessionCount: Int = 0
    }

    let date: Date
    var totalSeconds: Double = 0
    var sessionCount: Int = 0
    var apps: [String: AppAccumulator] = [:]
    var hours: [Int: Double] = [:]

    mutating func add(session: RawSession, calendar: Calendar) {
        totalSeconds += session.durationSeconds
        sessionCount += 1

        var app = apps[session.appName] ?? AppAccumulator()
        app.totalSeconds += session.durationSeconds
        app.sessionCount += 1
        apps[session.appName] = app

        let hour = calendar.component(.hour, from: session.startTime)
        hours[hour, default: 0] += session.durationSeconds
    }

    var snapshotDay: ScreenTimeSnapshot.Day {
        ScreenTimeSnapshot.Day(
            date: Self.dateFormatter.string(from: date),
            totalSeconds: totalSeconds,
            sessionCount: sessionCount,
            apps: apps
                .map { appName, value in
                    ScreenTimeSnapshot.AppUsage(
                        appName: appName,
                        totalSeconds: value.totalSeconds,
                        sessionCount: value.sessionCount
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.totalSeconds == rhs.totalSeconds {
                        return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
                    }
                    return lhs.totalSeconds > rhs.totalSeconds
                },
            hours: (0..<24).map { hour in
                ScreenTimeSnapshot.HourUsage(
                    hour: hour,
                    totalSeconds: hours[hour, default: 0]
                )
            }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ScreenTimeSnapshot: Codable, Sendable {
    let version = 1
    let generatedAt: Date
    let fileURL: String
    let canonicalDatabasePath: String
    let historyDays: Int
    let device: DeviceInfo
    let range: DateRange
    let days: [Day]

    enum CodingKeys: String, CodingKey {
        case version
        case generatedAt = "generated_at"
        case fileURL = "file_url"
        case canonicalDatabasePath = "canonical_database_path"
        case historyDays = "history_days"
        case device
        case range
        case days
    }

    struct DateRange: Codable, Sendable {
        let startDate: Date
        let endDate: Date

        enum CodingKeys: String, CodingKey {
            case startDate = "start_date"
            case endDate = "end_date"
        }
    }

    struct Day: Codable, Sendable {
        let date: String
        let totalSeconds: Double
        let sessionCount: Int
        let apps: [AppUsage]
        let hours: [HourUsage]

        enum CodingKeys: String, CodingKey {
            case date
            case totalSeconds = "total_seconds"
            case sessionCount = "session_count"
            case apps
            case hours
        }
    }

    struct AppUsage: Codable, Sendable {
        let appName: String
        let totalSeconds: Double
        let sessionCount: Int

        enum CodingKeys: String, CodingKey {
            case appName = "app_name"
            case totalSeconds = "total_seconds"
            case sessionCount = "session_count"
        }
    }

    struct HourUsage: Codable, Sendable {
        let hour: Int
        let totalSeconds: Double

        enum CodingKeys: String, CodingKey {
            case hour
            case totalSeconds = "total_seconds"
        }
    }
}

private extension HistoryStore {
    static var defaultDatabasePath: String {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md/screentime.db")
            .path
    }
}
