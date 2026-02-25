import XCTest
import SQLite3
import Darwin
@testable import time_md

final class ScreenTimeDataServiceErrorTests: XCTestCase {
    private let mappingPathEnvKey = "SCREENTIME_CATEGORY_MAPPINGS_DB_PATH"
    private let appleEpochOffset: Double = 978_307_200

    private var tempDirectory: URL!
    private var defaultMappingPath: String!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TimeMdErrorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        defaultMappingPath = tempDirectory.appendingPathComponent("category-mappings.db").path
        XCTAssertEqual(setenv(mappingPathEnvKey, defaultMappingPath, 1), 0)
    }

    override func tearDownWithError() throws {
        _ = unsetenv(mappingPathEnvKey)

        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
    }

    func testInvalidPathOverrideProducesActionableDatabaseNotFoundError() async {
        let missing = tempDirectory.appendingPathComponent("does-not-exist.db")
        let service = SQLiteScreenTimeDataService(pathOverride: missing.path)

        do {
            _ = try await service.fetchTopApps(filters: makeFilters(), limit: 5)
            XCTFail("Expected databaseNotFound error")
        } catch let error as ScreenTimeDataError {
            guard case let .databaseNotFound(searchedPaths) = error else {
                XCTFail("Expected databaseNotFound, got \(error)")
                return
            }

            XCTAssertEqual(searchedPaths, ["SCREENTIME_DB_PATH=\(missing.path)"])

            let message = ScreenTimeDataError.message(for: error)
            XCTAssertTrue(message.contains("SCREENTIME_DB_PATH is set"))
            XCTAssertTrue(message.contains(missing.path))
            XCTAssertTrue(message.contains("Update SCREENTIME_DB_PATH"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDirectoryPathOverrideProducesPermissionDeniedError() async throws {
        let directoryPath = tempDirectory.appendingPathComponent("directory-instead-of-db", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryPath, withIntermediateDirectories: true)

        let service = SQLiteScreenTimeDataService(pathOverride: directoryPath.path)

        do {
            _ = try await service.fetchTopCategories(filters: makeFilters(), limit: 5)
            XCTFail("Expected permissionDenied error")
        } catch let error as ScreenTimeDataError {
            guard case let .permissionDenied(path) = error else {
                XCTFail("Expected permissionDenied, got \(error)")
                return
            }

            XCTAssertEqual(path, directoryPath.path)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testKnowledgeSchemaMismatchIncludesMissingColumnDetails() async throws {
        let dbURL = try createKnowledgeDatabase(missingEndDateColumn: true)
        let service = SQLiteScreenTimeDataService(pathOverride: dbURL.path)

        do {
            _ = try await service.fetchTopApps(filters: makeFilters(), limit: 10)
            XCTFail("Expected schemaMismatch error")
        } catch let error as ScreenTimeDataError {
            guard case let .schemaMismatch(path, details) = error else {
                XCTFail("Expected schemaMismatch, got \(error)")
                return
            }

            XCTAssertEqual(path, dbURL.path)
            XCTAssertTrue(details.contains("ZENDDATE"))
            XCTAssertTrue(details.contains("Available columns"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMappingInstallFailureIncludesTemporaryAndUnderlyingContext() async throws {
        let dbURL = try createKnowledgeDatabase(missingEndDateColumn: false)

        let blockedParent = tempDirectory.appendingPathComponent("blocked-parent")
        FileManager.default.createFile(atPath: blockedParent.path, contents: Data("x".utf8))

        let invalidMappingPath = blockedParent.appendingPathComponent("category-mappings.db").path
        XCTAssertEqual(setenv(mappingPathEnvKey, invalidMappingPath, 1), 0)

        let service = SQLiteScreenTimeDataService(pathOverride: dbURL.path)

        do {
            _ = try await service.fetchTopCategories(filters: makeFilters(), limit: 10)
            XCTFail("Expected mapping install failure")
        } catch let error as ScreenTimeDataError {
            guard case let .sqlite(path, message) = error else {
                XCTFail("Expected sqlite error, got \(error)")
                return
            }

            XCTAssertTrue(path.contains("time.md-"))
            XCTAssertTrue(path.hasSuffix("knowledgeC.db"))
            XCTAssertTrue(message.contains("Failed to install category mappings into temporary analysis database"))
            XCTAssertTrue(message.contains(blockedParent.path))
            XCTAssertFalse(message.contains("(query)"))
            XCTAssertFalse(message.contains("(bind)"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testLockedKnowledgeDatabaseCanStillBeQueriedViaTemporaryCopy() async throws {
        let dbURL = try createKnowledgeDatabase(missingEndDateColumn: false)
        let lockConnection = try openDatabase(path: dbURL.path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX)

        defer {
            _ = sqlite3_exec(lockConnection, "ROLLBACK", nil, nil, nil)
            sqlite3_close(lockConnection)
        }

        try exec(db: lockConnection, sql: "PRAGMA journal_mode=WAL;")
        try exec(db: lockConnection, sql: "BEGIN IMMEDIATE TRANSACTION;")

        let service = SQLiteScreenTimeDataService(pathOverride: dbURL.path)
        let topApps = try await service.fetchTopApps(filters: makeFilters(), limit: 5)

        XCTAssertEqual(topApps.count, 2)
        XCTAssertEqual(topApps.first?.appName, "YouTube")
        XCTAssertEqual(topApps.first?.totalSeconds ?? 0, 2400, accuracy: 0.001)
    }
}

private extension ScreenTimeDataServiceErrorTests {
    func makeFilters() -> FilterSnapshot {
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
            selectedCategories: [],
            selectedHeatmapCells: []
        )
    }

    func createKnowledgeDatabase(missingEndDateColumn: Bool) throws -> URL {
        let dbURL = tempDirectory.appendingPathComponent(missingEndDateColumn ? "knowledge-missing-zenddate.db" : "knowledgeC.db")
        let db = try openDatabase(path: dbURL.path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX)
        defer { sqlite3_close(db) }

        if missingEndDateColumn {
            try exec(db: db, sql: """
            CREATE TABLE ZOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                ZSTREAMNAME TEXT,
                ZVALUESTRING TEXT,
                ZSTARTDATE REAL
            );
            """)
            return dbURL
        }

        try exec(db: db, sql: """
        CREATE TABLE ZOBJECT (
            Z_PK INTEGER PRIMARY KEY,
            ZSTREAMNAME TEXT,
            ZVALUESTRING TEXT,
            ZSTARTDATE REAL,
            ZENDDATE REAL
        );
        """)

        let start = makeFilters().startDate
        try insertUsage(db: db, appName: "YouTube", start: start.addingTimeInterval(9 * 3600), durationSeconds: 2400)
        try insertUsage(db: db, appName: "Safari", start: start.addingTimeInterval(10 * 3600), durationSeconds: 1200)

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

    func openDatabase(path: String, flags: Int32) throws -> OpaquePointer {
        var dbPointer: OpaquePointer?
        let result = sqlite3_open_v2(path, &dbPointer, flags, nil)
        guard result == SQLITE_OK, let db = dbPointer else {
            throw makeSQLiteError(dbPointer)
        }
        return db
    }

    func exec(db: OpaquePointer, sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw makeSQLiteError(db)
        }
    }

    func makeSQLiteError(_ db: OpaquePointer?) -> NSError {
        let message = db.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(domain: "ScreenTimeDataServiceErrorTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
