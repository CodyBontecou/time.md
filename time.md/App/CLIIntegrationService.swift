import Foundation

/// Installs the bundled time.md command-line helper into a user-writable PATH
/// directory. The helper binary is still named `timemd-mcp` in the app bundle
/// for backwards compatibility, but users should invoke it as `timemd`.
@MainActor
final class CLIIntegrationService {
    static let shared = CLIIntegrationService()

    enum InstallStatus: Equatable {
        case missingBinary
        case notInstalled
        case installed
        case partial(installedCommands: [String])
        case conflict(path: String)
    }

    nonisolated static let primaryCommand = "timemd"
    nonisolated static let legacyCommand = "timemd-mcp"

    private let commands = [primaryCommand, legacyCommand]

    private init() {}

    var bundledBinaryPath: String? {
        MCPIntegrationService.shared.bundledBinaryPath
    }

    var installDirectory: URL {
        realHomeDirectory().appendingPathComponent(".local/bin", isDirectory: true)
    }

    var primaryCommandPath: URL {
        installDirectory.appendingPathComponent(Self.primaryCommand)
    }

    var pathSnippet: String {
        "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    }

    var isInstallDirectoryOnPATH: Bool {
        let installPath = installDirectory.standardizedFileURL.path
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) }
        return pathEntries.contains { entry in
            URL(fileURLWithPath: (entry as NSString).expandingTildeInPath)
                .standardizedFileURL
                .path == installPath
        }
    }

    func status() -> InstallStatus {
        guard bundledBinaryPath != nil else { return .missingBinary }

        var installed: [String] = []
        for command in commands {
            let url = installDirectory.appendingPathComponent(command)
            switch linkState(at: url) {
            case .missing:
                continue
            case .owned:
                installed.append(command)
            case .conflict:
                return .conflict(path: url.path)
            }
        }

        if installed.count == commands.count { return .installed }
        if !installed.isEmpty { return .partial(installedCommands: installed) }
        return .notInstalled
    }

    func install() throws {
        guard let bundledBinaryPath else {
            throw CLIInstallError.missingBinary
        }

        try FileManager.default.createDirectory(
            at: installDirectory,
            withIntermediateDirectories: true
        )

        for command in commands {
            let url = installDirectory.appendingPathComponent(command)
            switch linkState(at: url) {
            case .missing:
                break
            case .owned:
                try FileManager.default.removeItem(at: url)
            case .conflict:
                throw CLIInstallError.conflict(path: url.path)
            }
            try FileManager.default.createSymbolicLink(
                at: url,
                withDestinationURL: URL(fileURLWithPath: bundledBinaryPath)
            )
        }
    }

    func uninstall() throws {
        for command in commands {
            let url = installDirectory.appendingPathComponent(command)
            switch linkState(at: url) {
            case .missing:
                continue
            case .owned:
                try FileManager.default.removeItem(at: url)
            case .conflict:
                throw CLIInstallError.conflict(path: url.path)
            }
        }
    }

    private enum LinkState {
        case missing
        case owned
        case conflict
    }

    private func linkState(at url: URL) -> LinkState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else {
            return .conflict
        }

        let resolvedDestination: String
        if destination.hasPrefix("/") {
            resolvedDestination = destination
        } else {
            resolvedDestination = url.deletingLastPathComponent().appendingPathComponent(destination).path
        }

        let standardizedDestinationURL = URL(fileURLWithPath: resolvedDestination).standardizedFileURL
        let currentBinary = bundledBinaryPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        if standardizedDestinationURL.path == currentBinary {
            return .owned
        }

        // Treat symlinks to older/dev copies of the same helper as repairable.
        // This lets Sparkle updates and source builds repoint the command
        // without failing on a stale, previously installed symlink.
        if standardizedDestinationURL.lastPathComponent == "timemd-mcp" {
            return .owned
        }

        return .conflict
    }
}

enum CLIInstallError: LocalizedError {
    case missingBinary
    case conflict(path: String)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "The bundled timemd-mcp binary was not found. Rebuild or reinstall time.md."
        case .conflict(let path):
            return "A different file already exists at \(path). Remove it or choose a different install location."
        }
    }
}
