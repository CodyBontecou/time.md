import Foundation

/// Protocol for cross-device sync operations
protocol SyncServiceProviding: Sendable {
    /// Fetch the latest sync payload from cloud storage
    func fetchPayload() async throws -> SyncPayload
    
    /// Upload updated sync data
    func uploadPayload(_ payload: SyncPayload) async throws
    
    /// Observe changes to the sync file
    func observeChanges(_ handler: @escaping @Sendable (SyncPayload) -> Void) -> any Sendable
    
    /// Check if sync is available
    var isSyncAvailable: Bool { get }
}

/// iCloud Drive-based sync service
/// Uses Documents folder for easy debugging and cross-platform compatibility
actor iCloudSyncService: SyncServiceProviding {
    
    private let containerIdentifier: String?
    private var fileCoordinator: NSFileCoordinator?
    private var presentedItemOperationQueue: OperationQueue?
    
    nonisolated var isSyncAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    init(containerIdentifier: String? = nil) {
        self.containerIdentifier = containerIdentifier
    }
    
    // MARK: - File URL
    
    private var syncFileURL: URL? {
        get async {
            // Try iCloud container first
            if let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: containerIdentifier
            ) {
                let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
                
                // Ensure Documents folder exists
                try? FileManager.default.createDirectory(
                    at: documentsURL,
                    withIntermediateDirectories: true
                )
                
                return documentsURL.appendingPathComponent(SyncPayload.filename)
            }
            
            // Fallback to local storage
            return localFallbackURL
        }
    }
    
    private var localFallbackURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let timeprintDir = appSupport.appendingPathComponent("time.md", isDirectory: true)
        try? FileManager.default.createDirectory(at: timeprintDir, withIntermediateDirectories: true)
        
        return timeprintDir.appendingPathComponent(SyncPayload.filename)
    }
    
    // MARK: - Fetch
    
    func fetchPayload() async throws -> SyncPayload {
        guard let url = await syncFileURL else {
            return .empty
        }
        
        // Use file coordination for iCloud
        if isSyncAvailable {
            return try await fetchWithCoordination(url: url)
        }
        
        // Local fallback
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        
        return try SyncPayload.load(from: url)
    }
    
    private func fetchWithCoordination(url: URL) async throws -> SyncPayload {
        try await withCheckedThrowingContinuation { continuation in
            let coordinator = NSFileCoordinator()
            var error: NSError?
            
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { readURL in
                do {
                    guard FileManager.default.fileExists(atPath: readURL.path) else {
                        continuation.resume(returning: .empty)
                        return
                    }
                    
                    let payload = try SyncPayload.load(from: readURL)
                    continuation.resume(returning: payload)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            if let error = error {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Upload
    
    func uploadPayload(_ payload: SyncPayload) async throws {
        guard let url = await syncFileURL else {
            throw ScreenTimeError.syncFailed(underlying: "No sync destination available")
        }
        
        // Use file coordination for iCloud
        if isSyncAvailable {
            try await uploadWithCoordination(payload: payload, url: url)
        } else {
            try payload.save(to: url)
        }
    }
    
    private func uploadWithCoordination(payload: SyncPayload, url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let coordinator = NSFileCoordinator()
            var error: NSError?
            
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &error) { writeURL in
                do {
                    try payload.save(to: writeURL)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            if let error = error {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Observe Changes
    
    nonisolated func observeChanges(_ handler: @escaping @Sendable (SyncPayload) -> Void) -> any Sendable {
        // Create a metadata query to observe iCloud changes
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, SyncPayload.filename)
        
        let observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak query] _ in
            guard let query = query,
                  let item = query.results.first as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else {
                return
            }
            
            // Load and notify
            Task {
                do {
                    let payload = try SyncPayload.load(from: url)
                    handler(payload)
                } catch {
                    // Log error but don't crash
                    print("[iCloudSync] Failed to load updated payload: \(error)")
                }
            }
        }
        
        query.start()
        
        return SyncObservation(query: query, observer: observer)
    }
}

// MARK: - Observation Token

private final class SyncObservation: @unchecked Sendable {
    private let query: NSMetadataQuery
    private let observer: Any
    
    init(query: NSMetadataQuery, observer: Any) {
        self.query = query
        self.observer = observer
    }
    
    deinit {
        query.stop()
        NotificationCenter.default.removeObserver(observer)
    }
}

// MARK: - Sync Coordinator

/// Coordinates sync operations between local data and cloud storage
actor SyncCoordinator {
    private let syncService: any SyncServiceProviding
    private let dataService: any ScreenTimeProviding
    
    private var lastSyncDate: Date?
    private var observation: (any Sendable)?
    
    init(syncService: any SyncServiceProviding, dataService: any ScreenTimeProviding) {
        self.syncService = syncService
        self.dataService = dataService
    }
    
    /// Perform a full sync (fetch remote, merge, upload)
    func performSync() async throws {
        // 1. Fetch remote payload
        let remotePayload = try await syncService.fetchPayload()
        
        // 2. Build local device data
        let localData = try await buildLocalDeviceData()
        
        // 3. Merge
        var devices = remotePayload.devices.filter { $0.id != localData.id }
        devices.append(localData)
        
        let mergedPayload = SyncPayload(devices: devices)
        
        // 4. Upload
        try await syncService.uploadPayload(mergedPayload)
        
        lastSyncDate = Date()
    }
    
    /// Build sync data for the current device
    private func buildLocalDeviceData() async throws -> DeviceSyncData {
        let device = dataService.currentDevice
        
        // Get last 30 days of data
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: endDate)!
        
        let filters = FilterSnapshot(
            startDate: startDate,
            endDate: endDate,
            granularity: .day,
            selectedApps: [],
            selectedCategories: [],
            selectedHeatmapCells: []
        )
        
        let focusDays = try await dataService.fetchFocusDays(filters: filters)
        let topApps = try await dataService.fetchTopApps(filters: filters, limit: 10)
        
        // Convert to sync format
        let dailySummaries = focusDays.map { day in
            DailySyncSummary(
                date: day.date,
                totalSeconds: day.totalSeconds,
                focusBlocks: day.focusBlocks,
                topAppBundleId: topApps.first?.appName,
                topAppSeconds: topApps.first?.totalSeconds
            )
        }
        
        let appUsage = topApps.map { app in
            AppSyncUsage(
                bundleId: app.appName,
                displayName: app.appName.components(separatedBy: ".").last ?? app.appName,
                category: nil,
                date: endDate,
                totalSeconds: app.totalSeconds,
                sessionCount: app.sessionCount
            )
        }
        
        // Build web browsing data (Mac only)
        let webBrowsing = await buildWebBrowsingData(startDate: startDate, endDate: endDate)
        
        return DeviceSyncData(
            device: device,
            lastSyncDate: Date(),
            dailySummaries: dailySummaries,
            appUsage: appUsage,
            webBrowsing: webBrowsing
        )
    }
    
    /// Fetch the current sync payload (without performing a full sync)
    func fetchPayload() async throws -> SyncPayload {
        try await syncService.fetchPayload()
    }
    
    /// Build web browsing sync data (Mac only - iOS will return nil)
    private func buildWebBrowsingData(startDate: Date, endDate: Date) async -> WebBrowsingSyncData? {
        #if os(macOS)
        let service = SQLiteBrowsingHistoryService()
        
        do {
            // Fetch top domains
            let domains = try await service.fetchTopDomains(
                browser: .all,
                startDate: startDate,
                endDate: endDate,
                limit: 20
            )
            
            // Fetch daily counts
            let dailyCounts = try await service.fetchDailyVisitCounts(
                browser: .all,
                startDate: startDate,
                endDate: endDate
            )
            
            let totalVisits = dailyCounts.reduce(0) { $0 + $1.visitCount }
            
            return WebBrowsingSyncData(
                lastUpdated: Date(),
                topDomains: domains.map { DomainSyncSummary(domain: $0.domain, visitCount: $0.visitCount, lastVisitTime: $0.lastVisitTime) },
                dailyCounts: dailyCounts.map { DailyWebVisitCount(date: $0.date, visitCount: $0.visitCount) },
                totalVisits: totalVisits
            )
        } catch {
            print("[Sync] Failed to build web browsing data: \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }
    
    /// Start observing remote changes
    func startObserving(onChange: @escaping @Sendable (SyncPayload) -> Void) {
        observation = syncService.observeChanges(onChange)
    }
    
    /// Stop observing
    func stopObserving() {
        observation = nil
    }
}
