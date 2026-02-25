import XCTest
import SQLite3
import Darwin
@testable import time_md

final class CategoryMappingIntegrationTests: XCTestCase {
    private let mappingPathEnvKey = "SCREENTIME_CATEGORY_MAPPINGS_DB_PATH"
    private let appleEpochOffset: Double = 978_307_200

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let mappingPath = tempDirectory.appendingPathComponent("category-mappings.db").path
        XCTAssertEqual(setenv(mappingPathEnvKey, mappingPath, 1), 0)
    }

    override func tearDownWithError() throws {
        _ = unsetenv(mappingPathEnvKey)

        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testCategoryMappingStoreCRUDPersistsAcrossOperations() throws {
        XCTAssertTrue(try CategoryMappingStore.fetchAll().isEmpty)

        try CategoryMappingStore.upsert(appName: "  YouTube  ", category: "  Entertainment  ")
        try CategoryMappingStore.upsert(appName: "Safari", category: "Work")

        let initial = try CategoryMappingStore.fetchAll()
        XCTAssertEqual(initial.map(\.appName), ["Safari", "YouTube"])
        XCTAssertEqual(initial.map(\.category), ["Work", "Entertainment"])

        try CategoryMappingStore.upsert(appName: "YouTube", category: "Video")

        let updated = try CategoryMappingStore.fetchAll()
        let updatedByApp = Dictionary(uniqueKeysWithValues: updated.map { ($0.appName, $0.category) })
        XCTAssertEqual(updatedByApp["YouTube"], "Video")
        XCTAssertEqual(updatedByApp["Safari"], "Work")

        try CategoryMappingStore.delete(appName: "  YouTube  ")

        let final = try CategoryMappingStore.fetchAll()
        XCTAssertEqual(final.count, 1)
        XCTAssertEqual(final.first?.appName, "Safari")
        XCTAssertEqual(final.first?.category, "Work")
    }

    func testKnowledgeBackendCategoryQueriesUsePersistedMappingsAndFilters() async throws {
        let knowledgeDB = try createKnowledgeDatabase()
        let service = SQLiteScreenTimeDataService(pathOverride: knowledgeDB.path)

        let baselineCategories = try await service.fetchTopCategories(filters: makeFilters(), limit: 10)
        XCTAssertEqual(baselineCategories.count, 1)
        XCTAssertEqual(baselineCategories.first?.category, "Uncategorized")
        XCTAssertEqual(baselineCategories.first?.totalSeconds ?? 0, 3600, accuracy: 0.001)

        try await service.saveCategoryMapping(appName: "YouTube", category: "Entertainment")

        let reopenedService = SQLiteScreenTimeDataService(pathOverride: knowledgeDB.path)
        let storedMappings = try await reopenedService.fetchCategoryMappings()
        XCTAssertEqual(storedMappings.count, 1)
        XCTAssertEqual(storedMappings.first?.appName, "YouTube")
        XCTAssertEqual(storedMappings.first?.category, "Entertainment")

        let mappedCategories = try await reopenedService.fetchTopCategories(filters: makeFilters(), limit: 10)
        var totalsByCategory: [String: Double] = [:]
        for row in mappedCategories {
            totalsByCategory[row.category] = row.totalSeconds
        }

        XCTAssertEqual(totalsByCategory["Entertainment"] ?? 0, 2400, accuracy: 0.001)
        XCTAssertEqual(totalsByCategory["Uncategorized"] ?? 0, 1200, accuracy: 0.001)

        let entertainmentApps = try await reopenedService.fetchTopApps(
            filters: makeFilters(selectedCategories: ["Entertainment"]),
            limit: 10
        )
        XCTAssertEqual(entertainmentApps.count, 1)
        XCTAssertEqual(entertainmentApps.first?.appName, "YouTube")
        XCTAssertEqual(entertainmentApps.first?.totalSeconds ?? 0, 2400, accuracy: 0.001)

        let uncategorizedApps = try await reopenedService.fetchTopApps(
            filters: makeFilters(selectedCategories: ["Uncategorized"]),
            limit: 10
        )
        XCTAssertEqual(uncategorizedApps.count, 1)
        XCTAssertEqual(uncategorizedApps.first?.appName, "Safari")
        XCTAssertEqual(uncategorizedApps.first?.totalSeconds ?? 0, 1200, accuracy: 0.001)
    }
}

private extension CategoryMappingIntegrationTests {
    func makeFilters(selectedCategories: Set<String> = []) -> FilterSnapshot {
        let calendar = Calendar.current
        var day = DateComponents()
        day.year = 2026
        day.month = 1
        day.day = 5
        day.hour = 0
        day.minute = 0
        day.second = 0

        let start = calendar.date(from: day) ?? Date()

        return FilterSnapshot(
            startDate: start,
            endDate: start,
            granularity: .day,
            selectedApps: [],
            selectedCategories: selectedCategories,
            selectedHeatmapCells: []
        )
    }

    func createKnowledgeDatabase() throws -> URL {
        let dbURL = tempDirectory.appendingPathComponent("knowledgeC.db")

        var dbPointer: OpaquePointer?
        let openResult = sqlite3_open_v2(
            dbURL.path,
            &dbPointer,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )

        guard openResult == SQLITE_OK, let db = dbPointer else {
            throw makeSQLiteError(dbPointer)
        }

        defer { sqlite3_close(db) }

        try exec(db: db, sql: """
        CREATE TABLE ZOBJECT (
            Z_PK INTEGER PRIMARY KEY,
            ZSTREAMNAME TEXT,
            ZVALUESTRING TEXT,
            ZSTARTDATE REAL,
            ZENDDATE REAL
        );
        """)

        let dayStart = makeFilters().startDate

        try insertUsage(db: db, appName: "YouTube", start: dayStart.addingTimeInterval(9 * 3600), durationSeconds: 2400)
        try insertUsage(db: db, appName: "Safari", start: dayStart.addingTimeInterval(10 * 3600), durationSeconds: 1200)

        return dbURL
    }

    func insertUsage(db: OpaquePointer, appName: String, start: Date, durationSeconds: Double) throws {
        let sql = "INSERT INTO ZOBJECT (ZSTREAMNAME, ZVALUESTRING, ZSTARTDATE, ZENDDATE) VALUES ('/app/usage', ?, ?, ?)"
        var statementPointer: OpaquePointer?

        let prepareResult = sqlite3_prepare_v2(db, sql, -1, &statementPointer, nil)
        guard prepareResult == SQLITE_OK, let statement = statementPointer else {
            throw makeSQLiteError(db)
        }

        defer { sqlite3_finalize(statement) }

        let startApple = start.timeIntervalSince1970 - appleEpochOffset
        let endApple = startApple + durationSeconds

        guard sqlite3_bind_text(statement, 1, appName, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK,
              sqlite3_bind_double(statement, 2, startApple) == SQLITE_OK,
              sqlite3_bind_double(statement, 3, endApple) == SQLITE_OK else {
            throw makeSQLiteError(db)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw makeSQLiteError(db)
        }
    }

    func exec(db: OpaquePointer, sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw makeSQLiteError(db)
        }
    }

    func makeSQLiteError(_ db: OpaquePointer?) -> NSError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "CategoryMappingIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
