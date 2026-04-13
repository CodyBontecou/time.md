import XCTest
@testable import time_md

final class ScreenTimeDataServiceErrorTests: XCTestCase {
    private let mappingPathEnvKey = "SCREENTIME_CATEGORY_MAPPINGS_DB_PATH"

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
}
