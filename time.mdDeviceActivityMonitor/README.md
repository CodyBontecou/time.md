# time.md Device Activity Monitor Extension

This extension runs in the background to capture Screen Time data at scheduled intervals using Apple's DeviceActivity framework.

## Setup in Xcode

### 1. Create the Target

1. Open `time.md.xcodeproj`
2. File → New → Target
3. Search for **"Device Activity Monitor Extension"**
4. Configure:
   - Product Name: `time.mdDeviceActivityMonitor`
   - Bundle Identifier: `com.codybontecou.time.mdIOS.DeviceActivityMonitor`
   - Embed in Application: `time.mdIOS`
5. Click **Finish**

### 2. Replace Generated Files

After Xcode creates the target with template files:

1. **Delete** the auto-generated Swift files from the new target
2. **Add** this existing file to the target:
   - `DeviceActivityMonitorExtension.swift`

### 3. Configure Info.plist

Replace the generated Info.plist content with this file's `Info.plist`:
- NSExtensionPointIdentifier: `com.apple.deviceactivity.monitor-extension`
- NSExtensionPrincipalClass: `$(PRODUCT_MODULE_NAME).time.mdMonitor`

### 4. Configure Entitlements

1. Select the target → Signing & Capabilities
2. Add **App Groups** capability
3. Add group: `group.com.codybontecou.time.md`

Or replace the entitlements file with `time.mdDeviceActivityMonitor.entitlements`

### 5. Build Settings

Ensure these match the main app:
- iOS Deployment Target: 16.0+
- Swift Language Version: 5.9

## Files

| File | Purpose |
|------|---------|
| `DeviceActivityMonitorExtension.swift` | Monitor subclass with interval callbacks |
| `Info.plist` | Extension configuration |
| `*.entitlements` | App Group for data sharing |

## How It Works

The main app schedules monitoring using `DeviceActivityCenter`:

```swift
let schedule = DeviceActivitySchedule(
    intervalStart: DateComponents(hour: 0, minute: 0),
    intervalEnd: DateComponents(hour: 23, minute: 59),
    repeats: true
)
try DeviceActivityCenter().startMonitoring(.daily, during: schedule)
```

The extension receives callbacks:

```swift
class time.mdMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        // Called when monitoring interval begins
    }
    
    override func intervalDidEnd(for activity: DeviceActivityName) {
        // Called when interval ends - aggregate and store data
    }
    
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, ...) {
        // Called when usage threshold reached
    }
}
```

## Data Flow

```
DeviceActivityCenter (main app schedules monitoring)
        │
        ▼
System tracks usage in background
        │
        ▼
time.mdMonitor.intervalDidEnd() called
        │
        ▼
Writes to App Group UserDefaults/Container
        │
        ▼
Main app reads via SharedDataStore
        │
        ▼
Syncs to iCloud
```

## Scheduled Activities

| Activity Name | Schedule | Purpose |
|--------------|----------|---------|
| `.daily` | 00:00 - 23:59 | Full day tracking |
| `.hourly` | Each hour | Finer granularity |
| `.workHours` | 09:00 - 17:00 | Work time focus |
| `.evening` | 18:00 - 23:00 | Evening tracking |

## Debugging

Monitor extension logs:
```bash
log stream --predicate 'subsystem == "com.codybontecou.time.md.Monitor"'
```

Check if monitoring is active:
```swift
let activities = DeviceActivityCenter().activities
print(activities.map { $0.rawValue })
```
