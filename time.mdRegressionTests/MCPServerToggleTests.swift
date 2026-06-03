import XCTest

final class MCPServerToggleTests: XCTestCase {
    func testCLIListToolsPrintsCatalogWithoutOpeningDatabase() throws {
        let response = try runProcess(arguments: ["list-tools"], environment: [:], stdinObject: nil)

        XCTAssertEqual(response.exitStatus, 0, response.stderr)
        let tools = try XCTUnwrap(response.jsonArray as? [[String: Any]])
        let names = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("get_today"))
        XCTAssertTrue(names.contains("raw_query"))
        XCTAssertFalse(response.stderr.contains("Failed to open database"))
    }

    func testServerOffReturnsEmptyToolsAndSkipsDatabaseOpen() throws {
        let response = try runMCP(
            settings: ["enabled": false, "disabledTools": []],
            request: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]
        )

        XCTAssertEqual(response.exitStatus, 0, response.stderr)
        let result = try XCTUnwrap(response.json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [Any])
        XCTAssertTrue(tools.isEmpty)
        XCTAssertTrue(response.stderr.contains("Server disabled"))
        XCTAssertFalse(response.stderr.contains("Failed to open database"))
    }

    func testDisabledToolsAreHiddenFromToolListWithoutOpeningDatabase() throws {
        let response = try runMCP(
            settings: ["enabled": true, "disabledTools": ["get_schema"]],
            request: ["jsonrpc": "2.0", "id": 1, "method": "tools/list"]
        )

        XCTAssertEqual(response.exitStatus, 0, response.stderr)
        let result = try XCTUnwrap(response.json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        let toolNames = Set(tools.compactMap { $0["name"] as? String })

        XCTAssertFalse(toolNames.isEmpty)
        XCTAssertFalse(toolNames.contains("get_schema"))
        XCTAssertTrue(toolNames.contains("get_today"))
        XCTAssertFalse(response.stderr.contains("Failed to open database"))
    }

    func testDisabledToolCallReturnsMCPErrorResult() throws {
        let response = try runMCP(
            settings: ["enabled": true, "disabledTools": ["get_schema"]],
            request: [
                "jsonrpc": "2.0",
                "id": 1,
                "method": "tools/call",
                "params": ["name": "get_schema", "arguments": [:]]
            ]
        )

        XCTAssertEqual(response.exitStatus, 0, response.stderr)
        let result = try XCTUnwrap(response.json["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)

        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("tool 'get_schema' is disabled"))
        XCTAssertFalse(response.stderr.contains("Failed to open database"))
    }

    private struct MCPRunResponse {
        let json: [String: Any]
        let jsonArray: Any?
        let stderr: String
        let exitStatus: Int32
    }

    private func runMCP(settings: [String: Any], request: [String: Any]) throws -> MCPRunResponse {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("timemd-mcp-tests-")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let settingsURL = tempDirectory.appendingPathComponent("mcp-settings.json")
        let settingsData = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        try settingsData.write(to: settingsURL)

        return try runProcess(
            arguments: [],
            environment: ["TIMEMD_MCP_SETTINGS_PATH": settingsURL.path],
            stdinObject: request
        )
    }

    private func runProcess(
        arguments: [String],
        environment: [String: String],
        stdinObject: [String: Any]?
    ) throws -> MCPRunResponse {
        let process = Process()
        process.executableURL = try bundledMCPBinaryURL()
        process.arguments = arguments
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        if let stdinObject {
            let requestData = try JSONSerialization.data(withJSONObject: stdinObject, options: [])
            stdin.fileHandleForWriting.write(requestData)
            stdin.fileHandleForWriting.write(Data([0x0A]))
        }
        try? stdin.fileHandleForWriting.close()

        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let jsonText: String
        if arguments.isEmpty {
            let firstLine = try XCTUnwrap(stdoutText.split(separator: "\n").first, "stdout was empty; stderr: \(stderrText)")
            jsonText = String(firstLine)
        } else {
            jsonText = stdoutText
        }
        let object = try JSONSerialization.jsonObject(with: Data(jsonText.utf8))
        let json = object as? [String: Any]

        return MCPRunResponse(json: json ?? [:], jsonArray: object as? [Any], stderr: stderrText, exitStatus: process.terminationStatus)
    }

    private func bundledMCPBinaryURL() throws -> URL {
        let fileManager = FileManager.default
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("timemd-mcp"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/timemd-mcp"),
            Bundle(for: Self.self).bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/timemd-mcp")
        ]

        for candidate in candidates.compactMap({ $0 }) where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        throw XCTSkip("Bundled timemd-mcp executable was not found in the test host app")
    }
}
