import Foundation

// Entry point for the `timemd-mcp` stdio MCP server. A file named `main.swift`
// uses top-level code as its entry point, so no `@main` struct is needed.
//
// Implements a minimal subset of the Model Context Protocol
// (https://spec.modelcontextprotocol.io) over newline-delimited JSON-RPC 2.0
// on stdin/stdout. Four methods are handled: `initialize`,
// `notifications/initialized` (ignored), `tools/list`, and `tools/call`.

let protocolVersion = "2024-11-05"
let serverName = "timemd"
let serverVersion = "1.0.0"

let stderrHandle = FileHandle.standardError
let stdoutHandle = FileHandle.standardOutput

func log(_ message: String) {
    stderrHandle.write(Data("[timemd-mcp] \(message)\n".utf8))
}

let database: Database
do {
    database = try Database()
} catch {
    log("Failed to open database: \(error)")
    exit(1)
}

log("Starting — reading \(Database.screentimeDBPath)")

while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    handle(line: line, db: database)
}

// MARK: - Message handling

func handle(line: String, db: Database) {
    guard let data = line.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let message = object as? [String: Any] else {
        log("Failed to parse JSON: \(line)")
        return
    }

    let method = message["method"] as? String ?? ""
    let id = message["id"]

    // Notifications have no id — no response is sent.
    if id == nil || id is NSNull {
        return
    }

    let params = message["params"] as? [String: Any] ?? [:]

    switch method {
    case "initialize":
        let capabilities: [String: Any] = ["tools": [String: Any]()]
        respond(id: id!, result: [
            "protocolVersion": protocolVersion,
            "capabilities": capabilities,
            "serverInfo": [
                "name": serverName,
                "version": serverVersion
            ]
        ])

    case "tools/list":
        respond(id: id!, result: ["tools": Tools.all()])

    case "tools/call":
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any]
        do {
            let text = try Handlers.dispatch(name: name, arguments: arguments, db: db)
            respond(id: id!, result: [
                "content": [["type": "text", "text": text]],
                "isError": false
            ])
        } catch {
            respond(id: id!, result: [
                "content": [["type": "text", "text": "Error: \(error)"]],
                "isError": true
            ])
        }

    case "ping":
        respond(id: id!, result: [String: Any]())

    case "shutdown":
        respond(id: id!, result: NSNull())

    default:
        respondError(id: id!, code: -32601, message: "Method not found: \(method)")
    }
}

// MARK: - JSON-RPC writers

func respond(id: Any, result: Any) {
    let envelope: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id,
        "result": result
    ]
    writeMessage(envelope)
}

func respondError(id: Any, code: Int, message: String) {
    writeMessage([
        "jsonrpc": "2.0",
        "id": id,
        "error": [
            "code": code,
            "message": message
        ]
    ])
}

func writeMessage(_ message: [String: Any]) {
    do {
        let data = try JSONSerialization.data(
            withJSONObject: message,
            options: [.fragmentsAllowed]
        )
        stdoutHandle.write(data)
        stdoutHandle.write(Data([0x0A]))
    } catch {
        log("Failed to serialize response: \(error)")
    }
}
