import Foundation
import SwiftUI

/// Drives the user's single scheduled export. Polls every 60 seconds while the
/// app is running and fires the export when its scheduled fire time has elapsed
/// since the last successful run. Missed runs (sleep, app quit) are caught up on
/// the next launch / wake.
@MainActor
@Observable
final class ScheduledExportRunner {
    private(set) var isRunning: Bool = false
    private(set) var lastTickAt: Date?

    private let store: ExportScheduleStore
    private let dataService: any ScreenTimeDataServing
    private let browsingService: any BrowsingHistoryServing
    private var timer: Timer?

    init(
        store: ExportScheduleStore,
        dataService: any ScreenTimeDataServing,
        browsingService: (any BrowsingHistoryServing)? = nil
    ) {
        self.store = store
        self.dataService = dataService
        self.browsingService = browsingService ?? SQLiteBrowsingHistoryService()
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Force-run the schedule now, regardless of timing. Used by the "Run now" button.
    func runNow() async {
        guard let schedule = store.schedule else { return }
        await execute(schedule)
    }

    private func tick() {
        lastTickAt = Date()
        guard let schedule = store.schedule, schedule.isEnabled else { return }
        guard schedule.isDue(at: Date(), lastRun: schedule.lastRunAt) else { return }
        Task { await execute(schedule) }
    }

    private func execute(_ schedule: ExportSchedule) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            let outputURL = try resolveOutputDirectory(for: schedule)
            let started = outputURL.startAccessingSecurityScopedResource()
            defer { if started { outputURL.stopAccessingSecurityScopedResource() } }

            let snapshot = makeFilterSnapshot(for: schedule)
            let coordinator = ExportCoordinator(
                dataService: dataService,
                browsingService: browsingService,
                outputDirectoryOverride: outputURL
            )
            let config = CombinedExportConfig(
                sections: schedule.sections,
                format: schedule.format
            )
            _ = try await coordinator.exportCombined(
                config: config,
                filters: snapshot,
                settings: ExportSettings.load(),
                progress: nil
            )
            store.recordRun(success: true)
        } catch {
            store.recordRun(success: false, error: error.localizedDescription)
        }
    }

    private func resolveOutputDirectory(for schedule: ExportSchedule) throws -> URL {
        if let bookmark = schedule.outputBookmark {
            let resolved = try SecurityScopedBookmark.resolve(bookmark)
            if let refreshed = resolved.refreshedData {
                var updated = schedule
                updated.outputBookmark = refreshed
                updated.outputPath = resolved.url.path
                store.save(updated)
            }
            return resolved.url
        }
        if let path = schedule.outputPath {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return downloads.appendingPathComponent("time.md Exports", isDirectory: true)
    }

    private func makeFilterSnapshot(for schedule: ExportSchedule) -> FilterSnapshot {
        let range = schedule.relativeDateRange.dateRange()
        return FilterSnapshot(
            startDate: range.start,
            endDate: range.end,
            granularity: .day
        )
    }
}
