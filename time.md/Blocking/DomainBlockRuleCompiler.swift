import Darwin
import Foundation

/// A pure, testable representation of the domain-network state that the
/// privileged helper should apply. The app publishes the full desired state on
/// every reconciliation so the helper can be idempotent and repair partial
/// updates without knowing policy-engine details.
struct DomainBlockDesiredState: Codable, Hashable, Sendable {
    /// Normalized rule domains that are currently active. This is the canonical
    /// policy state exposed in helper status/diagnostics.
    var domains: [String]
    /// Extra concrete hostnames to add to `/etc/hosts` while preserving the
    /// canonical `domains` above. This lets a `reddit.com` rule cover observed
    /// subdomains such as `old.reddit.com`; hosts files do not support true
    /// wildcards, so the compiler also expands common aliases and carries
    /// observed variants alongside the rule domains instead of pretending they
    /// are separate active rules.
    var additionalHostnames: [String]
    var generatedAt: Date

    nonisolated init(domains: [String], additionalHostnames: [String] = [], generatedAt: Date = Date()) throws {
        self.generatedAt = generatedAt
        self.domains = try Self.normalizedDomains(from: domains)
        let domainSet = Set(self.domains)
        self.additionalHostnames = try Self.normalizedDomains(from: additionalHostnames)
            .filter { !domainSet.contains($0) }
    }

    nonisolated init(activeBlocks: [ActiveBlock], generatedAt: Date = Date(), additionalHostnames: [String] = []) throws {
        let domains = activeBlocks.compactMap { block -> String? in
            guard block.state.target.type == .domain else { return nil }
            if let rule = block.rule, (!rule.enabled || rule.enforcementMode != .domainNetwork) {
                return nil
            }
            return block.state.target.value
        }
        try self.init(domains: domains, additionalHostnames: additionalHostnames, generatedAt: generatedAt)
    }

    nonisolated private static func normalizedDomains(from values: [String]) throws -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for value in values {
            let domain = try normalizeDomain(value)
            guard seen.insert(domain).inserted else { continue }
            normalized.append(domain)
        }
        return normalized.sorted()
    }

    nonisolated private static func normalizeDomain(_ rawValue: String) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BlockRuleValidationError.emptyTarget(.domain) }

        let candidate: String
        if trimmed.contains("://") {
            candidate = trimmed
        } else if trimmed.contains("/") || trimmed.contains("?") || trimmed.contains("#") {
            candidate = "https://\(trimmed)"
        } else {
            candidate = "https://\(trimmed)"
        }

        let host = URLComponents(string: candidate)?.host ?? trimmed
        var normalized = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        if normalized.hasPrefix("*.") {
            normalized.removeFirst(2)
        }
        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }

        let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/:@?#*"))
        guard !normalized.isEmpty,
              normalized.rangeOfCharacter(from: invalidCharacters) == nil,
              normalized.contains("."),
              !normalized.hasPrefix("."),
              !normalized.hasSuffix(".") else {
            throw BlockRuleValidationError.invalidDomain(rawValue)
        }
        return normalized
    }
}

struct DomainBlockHostEntry: Codable, Hashable, Sendable {
    let address: String
    let hostname: String
}

struct DomainBlockCompiledRules: Codable, Hashable, Sendable {
    let desiredState: DomainBlockDesiredState
    let hostnames: [String]
    let hostEntries: [DomainBlockHostEntry]
    let hostsBlock: String
    let pfAnchorRules: String
}

/// Compiles active domain cooldowns into owned `/etc/hosts` lines and a pf
/// anchor. Domain names are primarily blocked through hosts entries because IPs
/// can change frequently; callers may optionally pass resolved addresses so the
/// pf anchor can add a best-effort network layer without relying on DNS inside
/// pfctl.
struct DomainBlockRuleCompiler: Sendable {
    nonisolated static let hostsBeginMarker = "# >>> time.md domain blocks >>>"
    nonisolated static let hostsEndMarker = "# <<< time.md domain blocks <<<"
    nonisolated static let pfAnchorName = "com.bontecou.time-md"

    nonisolated static let defaultCommonSubdomainPrefixes = ["amp", "i", "m", "mobile", "new", "np", "old"]

    var ipv4SinkAddress: String
    var ipv6SinkAddress: String
    var includeWWWVariants: Bool
    /// `/etc/hosts` cannot express `*.example.com`, so default network
    /// enforcement expands active domains to common browser-facing subdomains
    /// while the policy/extension path handles arbitrary suffix matches.
    var includeCommonSubdomainVariants: Bool
    var commonSubdomainPrefixes: [String]

    nonisolated init(
        ipv4SinkAddress: String = "0.0.0.0",
        ipv6SinkAddress: String = "::1",
        includeWWWVariants: Bool = true,
        includeCommonSubdomainVariants: Bool = true,
        commonSubdomainPrefixes: [String] = DomainBlockRuleCompiler.defaultCommonSubdomainPrefixes
    ) {
        self.ipv4SinkAddress = ipv4SinkAddress
        self.ipv6SinkAddress = ipv6SinkAddress
        self.includeWWWVariants = includeWWWVariants
        self.includeCommonSubdomainVariants = includeCommonSubdomainVariants
        self.commonSubdomainPrefixes = Self.normalizedSubdomainPrefixes(from: commonSubdomainPrefixes)
    }

    nonisolated func compile(
        desiredState: DomainBlockDesiredState,
        resolvedAddresses: [String: [String]] = [:]
    ) -> DomainBlockCompiledRules {
        let hostnames = hostnames(for: desiredState.domains, additionalHostnames: desiredState.additionalHostnames)
        let entries = hostnames.flatMap { hostname in
            [
                DomainBlockHostEntry(address: ipv4SinkAddress, hostname: hostname),
                DomainBlockHostEntry(address: ipv6SinkAddress, hostname: hostname)
            ]
        }
        return DomainBlockCompiledRules(
            desiredState: desiredState,
            hostnames: hostnames,
            hostEntries: entries,
            hostsBlock: makeHostsBlock(entries: entries, generatedAt: desiredState.generatedAt),
            pfAnchorRules: makePFAnchorRules(domains: desiredState.domains, resolvedAddresses: resolvedAddresses)
        )
    }

    nonisolated func compile(
        activeBlocks: [ActiveBlock],
        generatedAt: Date = Date(),
        resolvedAddresses: [String: [String]] = [:]
    ) throws -> DomainBlockCompiledRules {
        try compile(
            desiredState: DomainBlockDesiredState(activeBlocks: activeBlocks, generatedAt: generatedAt),
            resolvedAddresses: resolvedAddresses
        )
    }

    nonisolated private func hostnames(for domains: [String], additionalHostnames: [String]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for domain in domains {
            if seen.insert(domain).inserted { names.append(domain) }
            let www = "www.\(domain)"
            if includeWWWVariants, !domain.hasPrefix("www."), seen.insert(www).inserted {
                names.append(www)
            }
            if includeCommonSubdomainVariants {
                for hostname in commonSubdomainHostnames(for: domain) where seen.insert(hostname).inserted {
                    names.append(hostname)
                }
            }
        }
        for hostname in additionalHostnames where seen.insert(hostname).inserted {
            names.append(hostname)
        }
        return names.sorted()
    }

    nonisolated private func commonSubdomainHostnames(for domain: String) -> [String] {
        commonSubdomainPrefixes.map { "\($0).\(domain)" }
    }

    nonisolated private static func normalizedSubdomainPrefixes(from prefixes: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/:@?#*"))
        for prefix in prefixes {
            let value = prefix
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            guard !value.isEmpty,
                  value.rangeOfCharacter(from: invalidCharacters) == nil,
                  !value.contains("."),
                  seen.insert(value).inserted else { continue }
            normalized.append(value)
        }
        return normalized.sorted()
    }

    nonisolated private func makeHostsBlock(entries: [DomainBlockHostEntry], generatedAt: Date) -> String {
        var lines = [
            Self.hostsBeginMarker,
            "# Managed by time.md. Edits inside this block may be overwritten.",
            "# Generated at \(ISO8601DateFormatter().string(from: generatedAt))."
        ]
        lines += entries.map { "\($0.address)\t\($0.hostname)" }
        lines.append(Self.hostsEndMarker)
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated private func makePFAnchorRules(domains: [String], resolvedAddresses: [String: [String]]) -> String {
        var lines = [
            "# time.md owned pf anchor: \(Self.pfAnchorName)",
            "# Loaded independently with: pfctl -a \(Self.pfAnchorName) -f <anchor-file>",
            "# Hosts entries remain the primary domain-name enforcement path."
        ]

        var addresses: [String] = []
        var seen = Set<String>()
        for domain in domains {
            for address in resolvedAddresses[domain, default: []] where isIPAddress(address) && seen.insert(address).inserted {
                addresses.append(address)
            }
        }

        if addresses.isEmpty {
            lines.append("# No resolved IP addresses supplied; no pf block rules generated.")
        } else {
            lines.append("table <timemd_blocked_hosts> persist { \(addresses.sorted().joined(separator: ", ")) }")
            lines.append("block drop quick proto { tcp udp } from any to <timemd_blocked_hosts>")
            lines.append("block drop quick proto { tcp udp } from <timemd_blocked_hosts> to any")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    nonisolated private func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString { inet_pton(AF_INET, $0, &ipv4) == 1 || inet_pton(AF_INET6, $0, &ipv6) == 1 }
    }
}

enum DomainBlockHostsReconciler {
    nonisolated static let maximumHostsBytes = 2 * 1024 * 1024

    nonisolated static func applyingOwnedBlock(_ block: String, to existingData: Data?) throws -> Data {
        let existing = try decodeHosts(existingData)
        let withoutOwnedBlock = removeOwnedBlocks(from: existing)
        var result = withoutOwnedBlock.trimmingTrailingWhitespaceAndNewlines
        if !result.isEmpty { result += "\n\n" }
        result += block.trimmingTrailingWhitespaceAndNewlines + "\n"
        return Data(result.utf8)
    }

    nonisolated static func clearingOwnedBlock(from existingData: Data?) throws -> Data {
        let existing = try decodeHosts(existingData)
        let cleared = removeOwnedBlocks(from: existing).trimmingTrailingWhitespaceAndNewlines
        return Data((cleared.isEmpty ? "" : cleared + "\n").utf8)
    }

    /// Returns whether the owned hosts block needs a write while ignoring
    /// comment-only changes such as a newer "Generated at" timestamp. Without
    /// this, periodic reconciles would prompt for administrator privileges even
    /// when the effective host entries are unchanged.
    nonisolated static func ownedHostsBlockNeedsUpdate(
        existingData: Data?,
        desiredEntries: [DomainBlockHostEntry],
        clearing: Bool
    ) throws -> Bool {
        switch try ownedBlockSnapshot(from: existingData) {
        case .missing:
            return !clearing && !desiredEntries.isEmpty
        case .partial:
            return true
        case let .complete(existingEntries):
            if clearing { return true }
            return existingEntries != Set(desiredEntries)
        }
    }

    nonisolated private static func decodeHosts(_ data: Data?) throws -> String {
        guard let data else { return "" }
        guard data.count <= maximumHostsBytes else { throw DomainBlockHelperError.hostsFileTooLarge(data.count) }
        guard let text = String(data: data, encoding: .utf8) else { throw DomainBlockHelperError.hostsFileNotUTF8 }
        return text
    }

    nonisolated private static func removeOwnedBlocks(from text: String) -> String {
        var remainder = text
        while let beginRange = remainder.range(of: DomainBlockRuleCompiler.hostsBeginMarker) {
            guard let endRange = remainder.range(
                of: DomainBlockRuleCompiler.hostsEndMarker,
                range: beginRange.upperBound..<remainder.endIndex
            ) else {
                remainder.removeSubrange(beginRange.lowerBound..<remainder.endIndex)
                break
            }
            remainder.removeSubrange(beginRange.lowerBound..<endRange.upperBound)
        }
        return remainder
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingTrailingWhitespaceAndNewlines
    }

    private enum OwnedBlockSnapshot: Equatable {
        case missing
        case partial
        case complete(Set<DomainBlockHostEntry>)
    }

    nonisolated private static func ownedBlockSnapshot(from existingData: Data?) throws -> OwnedBlockSnapshot {
        let text = try decodeHosts(existingData)
        var searchStart = text.startIndex
        var snapshots: [Set<DomainBlockHostEntry>] = []

        while let beginRange = text.range(of: DomainBlockRuleCompiler.hostsBeginMarker, range: searchStart..<text.endIndex) {
            guard let endRange = text.range(
                of: DomainBlockRuleCompiler.hostsEndMarker,
                range: beginRange.upperBound..<text.endIndex
            ) else {
                return .partial
            }

            let blockBody = String(text[beginRange.upperBound..<endRange.lowerBound])
            snapshots.append(parseHostEntries(from: blockBody))
            searchStart = endRange.upperBound
        }

        guard !snapshots.isEmpty else { return .missing }
        guard snapshots.count == 1, let entries = snapshots.first else { return .partial }
        return .complete(entries)
    }

    nonisolated private static func parseHostEntries(from blockBody: String) -> Set<DomainBlockHostEntry> {
        var entries = Set<DomainBlockHostEntry>()
        for rawLine in blockBody.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard parts.count >= 2 else { continue }
            entries.insert(DomainBlockHostEntry(address: parts[0], hostname: parts[1]))
        }
        return entries
    }
}

private extension String {
    nonisolated var trimmingTrailingWhitespaceAndNewlines: String {
        var value = self
        while let last = value.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
            value.removeLast()
        }
        return value
    }
}
