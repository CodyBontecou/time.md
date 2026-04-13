import XCTest
@testable import time_md

final class CategoryMappingIntegrationTests: XCTestCase {
    private let mappingPathEnvKey = "SCREENTIME_CATEGORY_MAPPINGS_DB_PATH"

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

}
