# Timeprint Device Activity Report Extension

This extension provides SwiftUI views that display Screen Time data using Apple's DeviceActivity framework.

## Setup in Xcode

### 1. Create the Target

1. Open `Timeprint.xcodeproj`
2. File → New → Target
3. Search for **"Device Activity Report Extension"**
4. Configure:
   - Product Name: `TimeprintDeviceActivityReport`
   - Bundle Identifier: `com.codybontecou.TimeprintIOS.DeviceActivityReport`
   - Embed in Application: `TimeprintIOS`
5. Click **Finish**

### 2. Replace Generated Files

After Xcode creates the target with template files:

1. **Delete** the auto-generated Swift files from the new target
2. **Add** these existing files to the target:
   - `DeviceActivityReportExtension.swift`
   - `TotalActivityReport.swift`
   - `TotalActivityView.swift`
   - `TopAppsReport.swift`
   - `TopAppsView.swift`

### 3. Configure Info.plist

Replace the generated Info.plist content with this file's `Info.plist`:
- NSExtensionPointIdentifier: `com.apple.deviceactivityui.report-extension`
- NSExtensionPrincipalClass: `$(PRODUCT_MODULE_NAME).TimeprintReportExtension`

### 4. Configure Entitlements

1. Select the target → Signing & Capabilities
2. Add **App Groups** capability
3. Add group: `group.com.codybontecou.Timeprint`

Or replace the entitlements file with `TimeprintDeviceActivityReport.entitlements`

### 5. Build Settings

Ensure these match the main app:
- iOS Deployment Target: 16.0+
- Swift Language Version: 5.9

## Files

| File | Purpose |
|------|---------|
| `DeviceActivityReportExtension.swift` | Main entry point, registers report scenes |
| `TotalActivityReport.swift` | Computes total activity from DeviceActivityResults |
| `TotalActivityView.swift` | SwiftUI view for total activity display |
| `TopAppsReport.swift` | Computes top apps usage data |
| `TopAppsView.swift` | SwiftUI view for top apps list |
| `Info.plist` | Extension configuration |
| `*.entitlements` | App Group for data sharing |

## Usage

The main app embeds this extension's views using:

```swift
import DeviceActivity

DeviceActivityReport(
    DeviceActivityReport.Context(rawValue: "TotalActivity"),
    filter: DeviceActivityFilter(
        segment: .daily(during: todayInterval)
    )
)
```

## Data Flow

```
DeviceActivity Framework
        │
        ▼
TotalActivityReport.makeConfiguration()
        │
        ▼
TotalActivityContext (computed data)
        │
        ▼
TotalActivityView (rendered UI)
        │
        ▼
Also writes to App Group UserDefaults for sync
```
