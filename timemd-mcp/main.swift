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

// With no arguments this executable remains the stdio MCP server. With a CLI
// subcommand it acts as a normal command-line reader for the same local data.
let launchArguments = Array(CommandLine.arguments.dropFirst())
if shouldHandleCLIMode(launchArguments) {
    exit(Int32(handleCLIMode(launchArguments)))
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

// MARK: - CLI mode

func shouldHandleCLIMode(_ args: [String]) -> Bool {
    guard let first = args.first else { return false }
    let command = first.lowercased()
    if command == "mcp" || command == "serve" || command == "--mcp" {
        return false
    }
    return true
}

func handleCLIMode(_ args: [String]) -> Int {
    do {
        guard let first = args.first else {
            printCLIHelp()
            return 0
        }

        switch first.lowercased() {
        case "help", "--help", "-h":
            printCLIHelp()
            return 0

        case "list-tools", "tools", "--list-tools":
            let catalog = toolCatalog()
            printJSON(catalog)
            return 0

        case "call":
            guard args.count >= 2, let toolName = resolveToolName(args[1]) else {
                throw CLIError.message("Usage: call <tool-name> [--key value ...]")
            }
            let toolArgs = try parseCLIArguments(Array(args.dropFirst(2)))
            return try runCLITool(name: toolName, arguments: toolArgs)

        case "sql", "query":
            let rest = Array(args.dropFirst())
            let toolArgs: [String: Any]
            if let firstRest = rest.first, !firstRest.hasPrefix("--") {
                toolArgs = ["sql": rest.joined(separator: " ")]
            } else {
                toolArgs = try parseCLIArguments(rest)
            }
            return try runCLITool(name: "raw_query", arguments: toolArgs)

        default:
            guard let toolName = resolveToolName(first) else {
                throw CLIError.message("Unknown command or tool: \(first)")
            }
            let toolArgs = try parseCLIArguments(Array(args.dropFirst()))
            return try runCLITool(name: toolName, arguments: toolArgs)
        }
    } catch {
        writeStderr("Error: \(error)\n")
        writeStderr("Run `timemd-mcp help` for usage.\n")
        return 1
    }
}

func runCLITool(name: String, arguments: [String: Any]) throws -> Int {
    let db = try Database()
    let output = try Handlers.dispatch(name: name, arguments: arguments, db: db)
    stdoutHandle.write(Data(output.utf8))
    if !output.hasSuffix("\n") {
        stdoutHandle.write(Data([0x0A]))
    }
    return 0
}

func toolCatalog() -> [[String: String]] {
    Tools.all().compactMap { entry in
        guard let name = entry["name"] as? String,
              let description = entry["description"] as? String else { return nil }
        return ["name": name, "description": description]
    }
}

func resolveToolName(_ raw: String) -> String? {
    let normalized = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "-", with: "_")
    guard !normalized.isEmpty else { return nil }

    let toolNames = Set(Tools.all().compactMap { $0["name"] as? String })
    if toolNames.contains(normalized) { return normalized }
    let prefixed = "get_\(normalized)"
    if toolNames.contains(prefixed) { return prefixed }
    if normalized == "raw" || normalized == "raw_query" { return "raw_query" }
    return nil
}

func parseCLIArguments(_ tokens: [String]) throws -> [String: Any] {
    var parsed: [String: Any] = [:]
    var index = 0

    while index < tokens.count {
        let token = tokens[index]

        if token == "--json" || token == "--args" {
            guard index + 1 < tokens.count else {
                throw CLIError.message("\(token) requires a JSON object argument")
            }
            let object = try parseJSONObject(tokens[index + 1])
            parsed.merge(object) { _, new in new }
            index += 2
            continue
        }

        guard token.hasPrefix("--") else {
            throw CLIError.message("Unexpected positional argument: \(token)")
        }

        let rawKeyValue = String(token.dropFirst(2))
        guard !rawKeyValue.isEmpty else {
            throw CLIError.message("Empty option name")
        }

        let key: String
        let value: Any
        if let equals = rawKeyValue.firstIndex(of: "=") {
            key = String(rawKeyValue[..<equals])
            let rawValue = String(rawKeyValue[rawKeyValue.index(after: equals)...])
            value = coerceCLIValue(rawValue)
            index += 1
        } else {
            key = rawKeyValue
            if index + 1 < tokens.count, !tokens[index + 1].hasPrefix("--") {
                value = coerceCLIValue(tokens[index + 1])
                index += 2
            } else {
                value = true
                index += 1
            }
        }

        parsed[normalizeCLIKey(key)] = value
    }

    return parsed
}

func normalizeCLIKey(_ key: String) -> String {
    key.replacingOccurrences(of: "-", with: "_")
}

func coerceCLIValue(_ raw: String) -> Any {
    let lower = raw.lowercased()
    if lower == "true" { return true }
    if lower == "false" { return false }
    if let intValue = Int64(raw) { return intValue }
    if let doubleValue = Double(raw) { return doubleValue }
    return raw
}

func parseJSONObject(_ raw: String) throws -> [String: Any] {
    guard let data = raw.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw CLIError.message("Expected a JSON object, got: \(raw)")
    }
    return object
}

func printJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(
        withJSONObject: value,
        options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
    ) {
        stdoutHandle.write(data)
        stdoutHandle.write(Data([0x0A]))
    }
}

func printCLIHelp() {
    let help = """
    timemd-mcp can run as either the bundled MCP server or a normal CLI.

    Usage:
      timemd-mcp                         Start the stdio MCP server (default)
      timemd-mcp mcp                     Start the stdio MCP server explicitly
      timemd-mcp list-tools              Print available tools as JSON
      timemd-mcp <tool-or-alias> [opts]  Run a data query and print JSON
      timemd-mcp call <tool> [opts]      Run an exact tool name
      timemd-mcp sql '<select ...>'      Run a read-only SQL query

    Examples:
      timemd-mcp today --limit 5
      timemd-mcp top-apps --since 7d --limit 20
      timemd-mcp sessions --since today --app-name Slack --limit 50
      timemd-mcp call get_heatmap --since 30d --stream-type app_usage
      timemd-mcp sql 'SELECT app_name, SUM(duration_seconds) AS seconds FROM usage GROUP BY app_name ORDER BY seconds DESC LIMIT 10'

    Options:
      --key value                         Adds an argument, with hyphens converted to underscores
      --key=value                         Same as above
      --json '{"since":"7d"}'             Merge a JSON object into arguments

    Data defaults to ~/Library/Application Support/time.md/*.db.
    Set TIMEMD_DATA_DIR or SCREENTIME_DB_PATH to point at another database.
    """
    stdoutHandle.write(Data(help.utf8))
    stdoutHandle.write(Data([0x0A]))
}

func writeStderr(_ message: String) {
    stderrHandle.write(Data(message.utf8))
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let message): return message
        }
    }
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
