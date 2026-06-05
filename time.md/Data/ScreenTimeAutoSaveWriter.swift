import AppKit
import Foundation

/// Keeps screen-time files on disk without requiring the user to press Export.
/// The canonical raw store remains `screentime.db`; the JSON snapshot is a
/// convenience mirror, and `screen-time-auto.<format>` follows the user's last
/// export format/section/range settings.
@MainActor
final class ScreenTimeAutoSaveWriter {
    static let shared = ScreenTimeAutoSaveWriter()

    nonisolated static let historyDays = 365

    nonisolated static var fileURL: URL {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md/screen-time-snapshot.json")
    }

    private let refreshInterval: TimeInterval = 5 * 60
    private let debounceInterval: TimeInterval = 10
    private let initialWriteDelay: TimeInterval = 30

    private var dataService: (any ScreenTimeDataServing)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var pendingTask: Task<Void, Never>?
    private let launchDate = Date()
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

        PerformanceTrace.event("ScreenTimeAutoSaveWriter initial write scheduled delay=\(initialWriteDelay)s")
        requestWrite(delay: initialWriteDelay)
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
        var delay = delay ?? debounceInterval
        let secondsSinceLaunch = Date().timeIntervalSince(launchDate)
        let remainingInitialDelay = max(0, initialWriteDelay - secondsSinceLaunch)
        if remainingInitialDelay > delay {
            delay = remainingInitialDelay
        }

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

        let trace = PerformanceTrace.begin("ScreenTimeAutoSaveWriter.writeNow")
        defer { PerformanceTrace.end("ScreenTimeAutoSaveWriter.writeNow", startedAt: trace) }

        let now = Date()
        let activeSession = ActiveAppTracker.shared.snapshot()
        let device = DeviceInfo.current()

        await Task.detached(priority: .background) {
            do {
                let snapshotTrace = PerformanceTrace.begin("ScreenTimeAutoSaveWriter.snapshot")
                let snapshot = try await Self.makeSnapshot(
                    dataService: dataService,
                    days: Self.historyDays,
                    now: now,
                    activeSession: activeSession,
                    device: device
                )
                try Self.write(snapshot: snapshot, to: Self.fileURL)
                PerformanceTrace.end("ScreenTimeAutoSaveWriter.snapshot", startedAt: snapshotTrace)
            } catch {
                NSLog("[ScreenTimeAutoSaveWriter] Failed to write snapshot: \(error.localizedDescription)")
            }
        }.value

        await Task.detached(priority: .background) {
            do {
                let exportTrace = PerformanceTrace.begin("ScreenTimeAutoSaveWriter.formattedAutoExport")
                try await Self.writeFormattedAutoExport(dataService: dataService, now: now)
                PerformanceTrace.end("ScreenTimeAutoSaveWriter.formattedAutoExport", startedAt: exportTrace)
            } catch {
                NSLog("[ScreenTimeAutoSaveWriter] Failed to write formatted auto-export: \(error.localizedDescription)")
            }
        }.value
    }

    nonisolated private static func write(snapshot: ScreenTimeSnapshot, to url: URL) throws {
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

    nonisolated private static func writeFormattedAutoExport(
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
        let sections = liveAutoSaveSections(from: settings.resolvedAutoSaveExportSections)
        guard !sections.isEmpty else {
            PerformanceTrace.event("ScreenTimeAutoSaveWriter.formattedAutoExport skipped: no safe sections")
            return
        }

        let config = CombinedExportConfig(
            sections: sections,
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

    nonisolated private static func liveAutoSaveSections(from selection: ExportSectionSelection) -> ExportSectionSelection {
        let excludedRawInputSections: Set<ExportSection> = [.inputRawKeystrokes, .inputRawMouseEvents]
        let safeSections = selection.sections.filter { !excludedRawInputSections.contains($0) }
        if safeSections.count != selection.sections.count {
            let excluded = selection.sections
                .filter { excludedRawInputSections.contains($0) }
                .map(\.rawValue)
                .joined(separator: ",")
            PerformanceTrace.event("ScreenTimeAutoSaveWriter.formattedAutoExport excluded raw input sections=\(excluded)")
        }
        return ExportSectionSelection(sections: safeSections)
    }

    nonisolated private static func removeStaleFormattedAutoExports(keeping writtenURL: URL, filenameTemplate: String) {
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

    nonisolated private static func makeSnapshot(
        dataService: any ScreenTimeDataServing,
        days: Int,
        now: Date,
        activeSession: ActiveAppTracker.CurrentAppSnapshot,
        device: DeviceInfo
    ) async throws -> ScreenTimeSnapshot {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(max(days, 1) - 1), to: todayStart) ?? todayStart

        var accumulators: [Date: DayAccumulator]
        if let sqliteService = dataService as? SQLiteScreenTimeDataService {
            do {
                let trace = PerformanceTrace.begin("ScreenTimeAutoSaveWriter.snapshot.rollups")
                let rows = try await sqliteService.fetchSnapshotRollupRows(startDate: firstDay, endDate: now)
                accumulators = accumulatorsFromRollupRows(rows, calendar: calendar, firstDay: firstDay, todayStart: todayStart)
                PerformanceTrace.end(
                    "ScreenTimeAutoSaveWriter.snapshot.rollups",
                    startedAt: trace,
                    metadata: "rows=\(rows.count)"
                )
            } catch {
                PerformanceTrace.event("ScreenTimeAutoSaveWriter.snapshot.rollups fallback: \(error.localizedDescription)")
                accumulators = try await rawSessionAccumulators(
                    dataService: dataService,
                    calendar: calendar,
                    firstDay: firstDay,
                    todayStart: todayStart,
                    now: now
                )
            }
        } else {
            accumulators = try await rawSessionAccumulators(
                dataService: dataService,
                calendar: calendar,
                firstDay: firstDay,
                todayStart: todayStart,
                now: now
            )
        }

        addActiveSession(
            activeSession,
            now: now,
            calendar: calendar,
            firstDay: firstDay,
            todayStart: todayStart,
            accumulators: &accumulators
        )

        return buildSnapshot(
            from: accumulators,
            firstDay: firstDay,
            todayStart: todayStart,
            now: now,
            historyDays: days,
            device: device,
            calendar: calendar
        )
    }

    nonisolated private static func rawSessionAccumulators(
        dataService: any ScreenTimeDataServing,
        calendar: Calendar,
        firstDay: Date,
        todayStart: Date,
        now: Date
    ) async throws -> [Date: DayAccumulator] {
        let filters = FilterSnapshot(
            startDate: firstDay,
            endDate: now,
            granularity: .day
        )

        let sessions = try await dataService.fetchRawSessions(filters: filters)
        var accumulators: [Date: DayAccumulator] = [:]
        for session in sessions where session.durationSeconds > 0 {
            let day = calendar.startOfDay(for: session.startTime)
            guard day >= firstDay, day <= todayStart else { continue }

            var accumulator = accumulators[day] ?? DayAccumulator(date: day)
            accumulator.add(
                appName: session.appName,
                startTime: session.startTime,
                totalSeconds: session.durationSeconds,
                sessionCount: 1,
                calendar: calendar
            )
            accumulators[day] = accumulator
        }
        return accumulators
    }

    nonisolated private static func accumulatorsFromRollupRows(
        _ rows: [ScreenTimeSnapshotRollupRow],
        calendar: Calendar,
        firstDay: Date,
        todayStart: Date
    ) -> [Date: DayAccumulator] {
        var accumulators: [Date: DayAccumulator] = [:]
        for row in rows where row.totalSeconds > 0 && row.sessionCount > 0 {
            guard let day = parseSnapshotDay(row.day), day >= firstDay, day <= todayStart else { continue }

            var accumulator = accumulators[day] ?? DayAccumulator(date: day)
            accumulator.add(
                appName: row.appName,
                hour: row.hour,
                totalSeconds: row.totalSeconds,
                sessionCount: row.sessionCount
            )
            accumulators[day] = accumulator
        }
        return accumulators
    }

    nonisolated private static func addActiveSession(
        _ activeSession: ActiveAppTracker.CurrentAppSnapshot,
        now: Date,
        calendar: Calendar,
        firstDay: Date,
        todayStart: Date,
        accumulators: inout [Date: DayAccumulator]
    ) {
        guard activeSession.isScreenActive,
              let appName = activeSession.bundleID,
              let startedAt = activeSession.switchTime,
              startedAt >= firstDay,
              startedAt <= now else { return }

        let duration = now.timeIntervalSince(startedAt)
        guard duration >= 2 else { return }

        let day = calendar.startOfDay(for: startedAt)
        guard day >= firstDay, day <= todayStart else { return }

        var accumulator = accumulators[day] ?? DayAccumulator(date: day)
        accumulator.add(
            appName: appName,
            startTime: startedAt,
            totalSeconds: duration,
            sessionCount: 1,
            calendar: calendar
        )
        accumulators[day] = accumulator
    }

    nonisolated private static func buildSnapshot(
        from accumulators: [Date: DayAccumulator],
        firstDay: Date,
        todayStart: Date,
        now: Date,
        historyDays: Int,
        device: DeviceInfo,
        calendar: Calendar
    ) -> ScreenTimeSnapshot {
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
            historyDays: historyDays,
            device: device,
            range: .init(startDate: firstDay, endDate: now),
            days: snapshotDays
        )
    }

    nonisolated private static func parseSnapshotDay(_ value: String) -> Date? {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return nil }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)
    }
}

nonisolated private struct DayAccumulator {
    struct AppAccumulator {
        var totalSeconds: Double = 0
        var sessionCount: Int = 0
    }

    let date: Date
    var totalSeconds: Double = 0
    var sessionCount: Int = 0
    var apps: [String: AppAccumulator] = [:]
    var hours: [Int: Double] = [:]

    mutating func add(
        appName: String,
        startTime: Date,
        totalSeconds: Double,
        sessionCount: Int,
        calendar: Calendar
    ) {
        let hour = calendar.component(.hour, from: startTime)
        add(appName: appName, hour: hour, totalSeconds: totalSeconds, sessionCount: sessionCount)
    }

    mutating func add(appName: String, hour: Int, totalSeconds: Double, sessionCount: Int) {
        self.totalSeconds += totalSeconds
        self.sessionCount += sessionCount

        var app = apps[appName] ?? AppAccumulator()
        app.totalSeconds += totalSeconds
        app.sessionCount += sessionCount
        apps[appName] = app

        hours[hour, default: 0] += totalSeconds
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

nonisolated private struct ScreenTimeSnapshot: Codable, Sendable {
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
    nonisolated static var defaultDatabasePath: String {
        realHomeDirectory()
            .appendingPathComponent("Library/Application Support/time.md/screentime.db")
            .path
    }
}
