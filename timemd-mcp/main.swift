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

// Tool catalog introspection: `timemd-mcp --list-tools` prints the catalog as
// a JSON array of `{name, description}` objects to stdout and exits. The
// containing app uses this to populate its tool picker UI without duplicating
// the catalog.
if CommandLine.arguments.dropFirst().contains("--list-tools") {
    let catalog: [[String: String]] = Tools.all().compactMap { entry in
        guard let name = entry["name"] as? String,
              let description = entry["description"] as? String else { return nil }
        return ["name": name, "description": description]
    }
    if let data = try? JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted]) {
        stdoutHandle.write(data)
        stdoutHandle.write(Data([0x0A]))
    }
    exit(0)
}

let enabledEnvVarKey = "TIMEMD_MCP_ENABLED"
let disabledToolsEnvVarKey = "TIMEMD_DISABLED_TOOLS"
let settingsPathEnvVarKey = "TIMEMD_MCP_SETTINGS_PATH"
let runtimeSettingsFileName = "mcp-settings.json"

struct RuntimeSettings {
    let enabled: Bool?
    let disabledTools: Set<String>?
}

struct EffectiveSettings {
    let enabled: Bool
    let disabledTools: Set<String>
}

/// Runtime settings are written by the app to Application Support so the
/// global on/off switch works even for manually configured MCP clients whose
/// JSON config does not include freshly generated environment variables.
let startupSettings = effectiveSettings()

var database: Database?
if startupSettings.enabled {
    log("Starting — will read \(Database.screentimeDBPath) on demand")
    if !startupSettings.disabledTools.isEmpty {
        log("Disabled tools: \(startupSettings.disabledTools.sorted().joined(separator: ", "))")
    }
} else {
    log("Server disabled in time.md settings — returning no tools")
}

while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    handle(line: line)
}

// MARK: - Runtime settings

func loadRuntimeSettings() -> RuntimeSettings {
    let url: URL
    if let overridePath = ProcessInfo.processInfo.environment[settingsPathEnvVarKey], !overridePath.isEmpty {
        url = URL(fileURLWithPath: overridePath)
    } else {
        url = runtimeSettingsURL().appendingPathComponent(runtimeSettingsFileName)
    }
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data),
          let json = object as? [String: Any] else {
        return RuntimeSettings(enabled: nil, disabledTools: nil)
    }

    let enabled = json["enabled"] as? Bool
    let disabled = (json["disabledTools"] as? [String]).map { Set($0) }
    return RuntimeSettings(enabled: enabled, disabledTools: disabled)
}

func runtimeSettingsURL() -> URL {
    let base = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library")
        .appendingPathComponent("Application Support")
    return base.appendingPathComponent("time.md", isDirectory: true)
}

func effectiveSettings() -> EffectiveSettings {
    let runtimeSettings = loadRuntimeSettings()
    let enabled = runtimeSettings.enabled
        ?? parseBoolean(ProcessInfo.processInfo.environment[enabledEnvVarKey])
        ?? true
    let disabledTools = runtimeSettings.disabledTools ?? parseToolList(
        ProcessInfo.processInfo.environment[disabledToolsEnvVarKey]
    )
    return EffectiveSettings(enabled: enabled, disabledTools: disabledTools)
}

func ensureDatabase() throws -> Database {
    if let database { return database }
    let opened = try Database()
    database = opened
    log("Starting — reading \(Database.screentimeDBPath)")
    return opened
}

func parseBoolean(_ raw: String?) -> Bool? {
    guard let raw else { return nil }
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on": return true
    case "0", "false", "no", "off": return false
    default: return nil
    }
}

func parseToolList(_ raw: String?) -> Set<String> {
    guard let raw else { return [] }
    let names = raw
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return Set(names)
}

// MARK: - Message handling

func handle(line: String) {
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
    let settings = effectiveSettings()
    if !settings.enabled {
        database = nil
    }

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
        guard settings.enabled else {
            respond(id: id!, result: ["tools": [Any]()])
            return
        }
        let visible = Tools.all().filter { entry in
            guard let name = entry["name"] as? String else { return true }
            return !settings.disabledTools.contains(name)
        }
        respond(id: id!, result: ["tools": visible])

    case "tools/call":
        let name = params["name"] as? String ?? ""
        let arguments = params["arguments"] as? [String: Any]
        guard settings.enabled else {
            respond(id: id!, result: [
                "content": [["type": "text", "text": "Error: timemd-mcp is turned off in time.md settings."]],
                "isError": true
            ])
            return
        }
        if settings.disabledTools.contains(name) {
            respond(id: id!, result: [
                "content": [["type": "text", "text": "Error: tool '\(name)' is disabled in time.md settings."]],
                "isError": true
            ])
            return
        }
        do {
            let db = try ensureDatabase()
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
