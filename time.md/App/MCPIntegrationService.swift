import Foundation

/// Manages MCP server registration for time.md across multiple coding agents.
///
/// The bundled `timemd-mcp` binary speaks standard MCP, so any agent that
/// understands the `mcpServers` config shape (Claude Code, Cursor, Windsurf,
/// and most others) can be wired up by writing a small JSON entry to that
/// agent's config file. For agents we don't auto-install for, callers can
/// surface `configSnippet()` and let the user paste it manually.
///
/// Tool gating is propagated to the binary via the `TIMEMD_DISABLED_TOOLS`
/// env var (comma-separated tool names). The binary filters its `tools/list`
/// response and rejects `tools/call` for disabled tools.
@MainActor
final class MCPIntegrationService {
    static let shared = MCPIntegrationService()

    enum Agent: String, CaseIterable, Identifiable {
        case claudeCode
        case cursor
        case windsurf

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claudeCode: return "Claude Code"
            case .cursor:     return "Cursor"
            case .windsurf:   return "Windsurf"
            }
        }

        /// Path to the JSON config file we read/write for this agent.
        var configPath: String {
            let home = NSHomeDirectory()
            switch self {
            case .claudeCode: return home + "/.claude.json"
            case .cursor:     return home + "/.cursor/mcp.json"
            case .windsurf:   return home + "/.codeium/windsurf/mcp_config.json"
            }
        }

        /// User-facing config path for display (uses `~`).
        var displayConfigPath: String {
            switch self {
            case .claudeCode: return "~/.claude.json"
            case .cursor:     return "~/.cursor/mcp.json"
            case .windsurf:   return "~/.codeium/windsurf/mcp_config.json"
            }
        }
    }

    enum Status: Equatable {
        case inactive
        case registered(path: String)
        case missingBinary
        case error(String)
    }

    struct ToolInfo: Hashable, Identifiable {
        let name: String
        let description: String
        var id: String { name }
    }

    /// The MCP server name written into each agent's config.
    private let serverKey = "timemd"
    private let disabledDefaultsKey = "MCPDisabledTools"
    private let envVarKey = "TIMEMD_DISABLED_TOOLS"

    private var cachedTools: [ToolInfo]?

    private init() {}

    // MARK: - Binary

    /// Absolute path to the bundled `timemd-mcp` executable.
    var bundledBinaryPath: String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("timemd-mcp")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.path
    }

    // MARK: - Tool catalog

    /// Tools advertised by the bundled binary. Cached for the app's lifetime
    /// since the catalog only changes when time.md ships a new version.
    func availableTools() -> [ToolInfo] {
        if let cached = cachedTools { return cached }
        guard let binaryPath = bundledBinaryPath else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["--list-tools"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let raw = try? JSONSerialization.jsonObject(with: data),
              let array = raw as? [[String: Any]] else {
            return []
        }
        let tools: [ToolInfo] = array.compactMap { entry in
            guard let name = entry["name"] as? String,
                  let description = entry["description"] as? String else { return nil }
            return ToolInfo(name: name, description: description)
        }
        cachedTools = tools
        return tools
    }

    // MARK: - Disabled tools

    /// Names of tools the user has toggled off, persisted to `UserDefaults`.
    func disabledTools() -> Set<String> {
        let raw = UserDefaults.standard.array(forKey: disabledDefaultsKey) as? [String] ?? []
        return Set(raw)
    }

    /// Replaces the disabled set and re-registers any currently-active agents
    /// so their config files pick up the new env var. Returns the updated
    /// status map for active agents.
    @discardableResult
    func setDisabledTools(_ disabled: Set<String>) -> [Agent: Status] {
        UserDefaults.standard.set(Array(disabled).sorted(), forKey: disabledDefaultsKey)
        var updated: [Agent: Status] = [:]
        for agent in Agent.allCases {
            if case .registered = status(for: agent) {
                updated[agent] = register(agent: agent)
            }
        }
        return updated
    }

    /// Comma-separated env var value (sorted for deterministic JSON output).
    private var disabledEnvValue: String {
        disabledTools().sorted().joined(separator: ",")
    }

    // MARK: - Snippet

    /// Generic JSON config snippet a user can paste into any MCP-compatible
    /// agent. Returns `nil` if the bundled binary is missing.
    func configSnippet() -> String? {
        guard let binaryPath = bundledBinaryPath else { return nil }
        let payload: [String: Any] = [
            "mcpServers": [
                serverKey: serverEntry(binaryPath: binaryPath)
            ]
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func serverEntry(binaryPath: String) -> [String: Any] {
        var env: [String: String] = [:]
        let disabled = disabledEnvValue
        if !disabled.isEmpty {
            env[envVarKey] = disabled
        }
        return [
            "command": binaryPath,
            "args": [String](),
            "env": env
        ]
    }

    // MARK: - Register / unregister

    /// Current registration status for `agent`.
    func status(for agent: Agent) -> Status {
        guard let binaryPath = bundledBinaryPath else {
            return .missingBinary
        }
        do {
            let json = try loadConfig(at: agent.configPath)
            if let servers = json["mcpServers"] as? [String: Any],
               let entry = servers[serverKey] as? [String: Any],
               let command = entry["command"] as? String,
               command == binaryPath {
                return .registered(path: binaryPath)
            }
            return .inactive
        } catch {
            return .error("\(error)")
        }
    }

    /// Adds or updates the `mcpServers.timemd` entry in `agent`'s config,
    /// preserving any other keys. Creates the file (and parent dirs) if needed.
    @discardableResult
    func register(agent: Agent) -> Status {
        guard let binaryPath = bundledBinaryPath else {
            return .missingBinary
        }
        do {
            var json = (try? loadConfig(at: agent.configPath)) ?? [:]
            var servers = (json["mcpServers"] as? [String: Any]) ?? [:]
            servers[serverKey] = serverEntry(binaryPath: binaryPath)
            json["mcpServers"] = servers
            try writeConfig(json, to: agent.configPath)
            return .registered(path: binaryPath)
        } catch {
            return .error("\(error)")
        }
    }

    /// Removes the `mcpServers.timemd` entry from `agent`'s config, preserving
    /// any other keys. Drops `mcpServers` if it becomes empty.
    @discardableResult
    func unregister(agent: Agent) -> Status {
        do {
            var json = (try? loadConfig(at: agent.configPath)) ?? [:]
            if var servers = json["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: serverKey)
                if servers.isEmpty {
                    json.removeValue(forKey: "mcpServers")
                } else {
                    json["mcpServers"] = servers
                }
            }
            try writeConfig(json, to: agent.configPath)
            return .inactive
        } catch {
            return .error("\(error)")
        }
    }

    // MARK: - File I/O

    private func loadConfig(at path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any]) ?? [:]
    }

    private func writeConfig(_ json: [String: Any], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(
                at: parent,
                withIntermediateDirectories: true
            )
        }
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
