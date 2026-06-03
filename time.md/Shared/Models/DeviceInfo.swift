import Foundation
import IOKit

/// Represents the Mac running time.md.
struct DeviceInfo: Codable, Identifiable, Sendable, Hashable {
    let id: String           // Unique hardware identifier
    let name: String         // User-facing name ("Cody's MacBook Pro")
    let model: String        // Device model ("MacBookPro18,3")
    let platform: Platform   // macOS
    let osVersion: String    // "15.2", "26.1"

    enum Platform: String, Codable, Sendable {
        case macOS

        var icon: String { "desktopcomputer" }
        var displayName: String { "Mac" }
    }

    /// Create DeviceInfo for the current Mac.
    static func current() -> DeviceInfo {
        DeviceInfo(
            id: Self.deviceIdentifier(),
            name: Self.deviceName(),
            model: Self.deviceModel(),
            platform: .macOS,
            osVersion: Self.osVersionString()
        )
    }

    // MARK: - Device Identifier

    private static func deviceIdentifier() -> String {
        macOSHardwareUUID() ?? UUID().uuidString
    }

    private static func macOSHardwareUUID() -> String? {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )

        guard platformExpert != 0 else { return nil }
        defer { IOObjectRelease(platformExpert) }

        guard let serialNumberAsCFString = IORegistryEntryCreateCFProperty(
            platformExpert,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        ) else { return nil }

        return serialNumberAsCFString.takeUnretainedValue() as? String
    }

    // MARK: - Device Name

    private static func deviceName() -> String {
        Host.current().localizedName ?? "Mac"
    }

    // MARK: - Device Model

    private static func deviceModel() -> String {
        macOSModelName() ?? "Mac"
    }

    private static func macOSModelName() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }

    // MARK: - OS Version

    private static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - Formatting

extension DeviceInfo {
    /// Display string like "MacBook Pro (Mac 26.1)".
    var displayDescription: String {
        "\(model) (\(platform.displayName) \(osVersion))"
    }

    /// Short display like "Mac".
    var shortDescription: String {
        platform.displayName
    }
}
