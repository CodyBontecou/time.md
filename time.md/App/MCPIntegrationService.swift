import Foundation

/// Manages the Claude Code MCP server registration for time.md.
///
/// When enabled, this writes an `mcpServers.timemd` entry into `~/.claude.json`
/// pointing at the `timemd-mcp` binary embedded inside the running `.app` bundle.
/// Claude Code picks up the entry the next time it launches, and the user can
/// query time.md data via MCP tools without any CLI installation.
@MainActor
final class MCPIntegrationService {
    static let shared = MCPIntegrationService()

    enum Status: Equatable {
        case inactive
        case registered(path: String)
        case missingBinary
        case error(String)
    }

    private let serverKey = "timemd"
    private let claudeConfigPath: String = {
        NSHomeDirectory() + "/.claude.json"
    }()

    private init() {}

    /// Absolute path to the bundled `timemd-mcp` executable.
    var bundledBinaryPath: String? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let url = resourceURL.appendingPathComponent("timemd-mcp")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.path
    }

    /// Current registration status, based on the contents of `~/.claude.json`
    /// and whether the bundled binary can be found.
    func currentStatus() -> Status {
        guard let binaryPath = bundledBinaryPath else {
            return .missingBinary
        }
        do {
            let json = try loadClaudeConfig()
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

    /// Adds or updates the `mcpServers.timemd` entry, preserving all other
    /// keys in `~/.claude.json`. Creates the file if it does not exist.
    @discardableResult
    func register() -> Status {
        guard let binaryPath = bundledBinaryPath else {
            return .missingBinary
        }
        do {
            var json = (try? loadClaudeConfig()) ?? [:]
            var servers = (json["mcpServers"] as? [String: Any]) ?? [:]
            servers[serverKey] = [
                "command": binaryPath,
                "args": [String](),
                "env": [String: String]()
            ] as [String: Any]
            json["mcpServers"] = servers
            try writeClaudeConfig(json)
            return .registered(path: binaryPath)
        } catch {
            return .error("\(error)")
        }
    }

    /// Removes the `mcpServers.timemd` entry, preserving all other keys. If
    /// `mcpServers` becomes empty after removal, the key is deleted too.
    @discardableResult
    func unregister() -> Status {
        do {
            var json = (try? loadClaudeConfig()) ?? [:]
            if var servers = json["mcpServers"] as? [String: Any] {
                servers.removeValue(forKey: serverKey)
                if servers.isEmpty {
                    json.removeValue(forKey: "mcpServers")
                } else {
                    json["mcpServers"] = servers
                }
            }
            try writeClaudeConfig(json)
            return .inactive
        } catch {
            return .error("\(error)")
        }
    }

    // MARK: - File I/O

    private func loadClaudeConfig() throws -> [String: Any] {
        let url = URL(fileURLWithPath: claudeConfigPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any]) ?? [:]
    }

    private func writeClaudeConfig(_ json: [String: Any]) throws {
        let url = URL(fileURLWithPath: claudeConfigPath)
        let data = try JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }
}
