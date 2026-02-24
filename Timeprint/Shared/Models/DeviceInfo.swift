import Foundation

#if os(macOS)
import IOKit
#elseif os(iOS)
import UIKit
#endif

/// Represents a device in the Timeprint ecosystem
struct DeviceInfo: Codable, Identifiable, Sendable, Hashable {
    let id: String           // Unique device identifier
    let name: String         // User-facing name ("Cody's MacBook Pro")
    let model: String        // Device model ("MacBook Pro", "iPhone 15")
    let platform: Platform   // macOS, iOS, iPadOS
    let osVersion: String    // "15.2", "26.1"
    
    enum Platform: String, Codable, Sendable {
        case macOS
        case iOS
        case iPadOS
        case watchOS
        case visionOS
        
        var icon: String {
            switch self {
            case .macOS: "desktopcomputer"
            case .iOS: "iphone"
            case .iPadOS: "ipad"
            case .watchOS: "applewatch"
            case .visionOS: "visionpro"
            }
        }
        
        var displayName: String {
            switch self {
            case .macOS: "Mac"
            case .iOS: "iPhone"
            case .iPadOS: "iPad"
            case .watchOS: "Apple Watch"
            case .visionOS: "Vision Pro"
            }
        }
    }
    
    /// Create DeviceInfo for the current device
    static func current() -> DeviceInfo {
        DeviceInfo(
            id: Self.deviceIdentifier(),
            name: Self.deviceName(),
            model: Self.deviceModel(),
            platform: Self.currentPlatform(),
            osVersion: Self.osVersionString()
        )
    }
    
    // MARK: - Platform Detection
    
    private static func currentPlatform() -> Platform {
        #if os(macOS)
        return .macOS
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPadOS
        }
        return .iOS
        #elseif os(watchOS)
        return .watchOS
        #elseif os(visionOS)
        return .visionOS
        #else
        return .iOS
        #endif
    }
    
    // MARK: - Device Identifier
    
    private static func deviceIdentifier() -> String {
        #if os(macOS)
        return macOSHardwareUUID() ?? UUID().uuidString
        #else
        // iOS: Use identifierForVendor (persists across app reinstalls for same vendor)
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #endif
    }
    
    #if os(macOS)
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
    #endif
    
    // MARK: - Device Name
    
    private static func deviceName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return UIDevice.current.name
        #endif
    }
    
    // MARK: - Device Model
    
    private static func deviceModel() -> String {
        #if os(macOS)
        return macOSModelName() ?? "Mac"
        #else
        return UIDevice.current.model
        #endif
    }
    
    #if os(macOS)
    private static func macOSModelName() -> String? {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
    }
    #endif
    
    // MARK: - OS Version
    
    private static func osVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

// MARK: - Formatting

extension DeviceInfo {
    /// Display string like "MacBook Pro (macOS 26.1)"
    var displayDescription: String {
        "\(model) (\(platform.displayName) \(osVersion))"
    }
    
    /// Short display like "Mac" or "iPhone"
    var shortDescription: String {
        platform.displayName
    }
}
