# Phase 7: Cross-Platform (iPhone/iPad Companion)

## Executive Summary

Build an iOS companion app for Timeprint that displays Screen Time data from iPhone/iPad, with the ability to see a unified view across all Apple devices.

---

## Architecture Overview

### Current State (macOS)
- Direct SQLite access to `knowledgeC.db` or normalized `screentime.db`
- Full historical data access
- No special entitlements required (just Full Disk Access for dev)

### iOS Challenges
The iOS Screen Time API is fundamentally different:

1. **DeviceActivityReport** - SwiftUI views that display Screen Time data
   - Runs in an extension, not the main app
   - Apple controls the rendering
   - Limited customization

2. **DeviceActivityMonitor** - Background monitoring
   - Schedules and thresholds
   - Good for "notify when X hours reached"

3. **ManagedSettings** - Parental controls / app blocking
   - Not relevant for analytics

4. **FamilyActivityPicker** - Select apps to monitor
   - User must explicitly choose apps

### Key Constraints on iOS
- ❌ No direct database access (knowledgeC.db is sandboxed)
- ❌ No historical data beyond what DeviceActivityReport provides
- ❌ Cannot extract raw numbers programmatically (reports are rendered views)
- ✅ Can use `DeviceActivityReport` extension to show Apple's built-in visualizations
- ✅ Can track "time spent" going forward with custom monitoring

---

## Recommended Approach

### Option A: DeviceActivityReport Extension (Recommended for v1)

**Pros:**
- Uses Apple's official API
- No App Store rejection risk
- Works immediately with existing Screen Time data

**Cons:**
- Limited customization (Apple's design)
- Can't export or sync the data elsewhere
- Report views are rendered by iOS, not us

**Implementation:**
1. Add iOS target with `FamilyControls` entitlement
2. Create `DeviceActivityReportExtension`
3. Use `DeviceActivityReport` to display built-in charts
4. Add our own summary header using custom SwiftUI

### Option B: Forward-Looking Manual Tracking

**Pros:**
- Full control over data
- Can sync to macOS
- Custom visualizations

**Cons:**
- Only tracks data from when user installs app
- No historical data
- Requires user to grant app monitoring permissions

**Implementation:**
1. Use `DeviceActivityMonitor` to track usage
2. Store data in local SQLite
3. Sync to iCloud Drive (shared with macOS)
4. Build unified dashboard

### Option C: Hybrid (v1.5+)

Combine both:
- DeviceActivityReport for "official" historical view
- Manual tracking for custom analytics going forward
- iCloud sync for cross-device aggregation

---

## Phase 7 Implementation Plan

### 7.1 — Shared Data Layer (Foundation)
Extract platform-agnostic code into shared module:

```
Timeprint/
├── Shared/                          # NEW - Shared between macOS & iOS
│   ├── Models/
│   │   ├── AnalyticsModels.swift    # Moved from Data/
│   │   ├── FilterModels.swift
│   │   └── DeviceIdentifier.swift   # NEW
│   ├── Formatting/
│   │   └── TimeFormatters.swift     # Duration/date formatting
│   └── Protocols/
│       └── DataProviding.swift      # Abstract data protocol
├── macOS/                           # macOS-specific
│   └── Data/
│       └── SQLiteDataService.swift
└── iOS/                             # iOS-specific  
    └── Data/
        └── DeviceActivityDataService.swift
```

### 7.2 — iOS App Target
Add new target to Xcode project:

- **Target name:** `Timeprint iOS`
- **Bundle ID:** `com.codybontecou.Timeprint.iOS`
- **Minimum iOS:** 17.0 (DeviceActivity API)
- **Capabilities:**
  - Family Controls (entitlement)
  - iCloud (CloudKit or Documents)

### 7.3 — DeviceActivityReport Extension
Create report extension:

- **Extension name:** `TimeprintReportExtension`
- **Purpose:** Render Screen Time reports in-app
- **Customization:** Header with TIMEPRINT branding

### 7.4 — iOS UI (Adaptive)
Port key views with compact layouts:

| macOS View | iOS Equivalent |
|------------|----------------|
| Overview Dashboard | Compact card stack |
| Trends Chart | Simplified line chart |
| Heatmap | Scrollable compact grid |
| Top Apps | List with progress bars |

### 7.5 — Cross-Device Sync (v1.5)
iCloud-based sync architecture:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  iPhone     │     │   iCloud     │     │   Mac       │
│  Timeprint  │◄───►│   Drive      │◄───►│  Timeprint  │
│             │     │  sync.json   │     │             │
└─────────────┘     └──────────────┘     └─────────────┘
```

Sync file format:
```json
{
  "devices": [
    {
      "id": "uuid",
      "name": "Cody's iPhone",
      "type": "iPhone",
      "lastSync": "2026-02-23T12:00:00Z",
      "dailySummaries": [
        {"date": "2026-02-22", "totalSeconds": 14400, "topApps": [...]}
      ]
    }
  ]
}
```

---

## Files to Create/Modify

### New Files
1. `Timeprint/Shared/Models/DeviceInfo.swift` - Device identification
2. `Timeprint/Shared/Models/SyncPayload.swift` - Cross-device sync format
3. `Timeprint/Shared/Protocols/ScreenTimeProviding.swift` - Abstract protocol
4. `TimeprintIOS/` - iOS app folder
5. `TimeprintIOS/TimeprintIOSApp.swift` - iOS app entry
6. `TimeprintIOS/Views/CompactOverviewView.swift` - Mobile dashboard
7. `TimeprintReportExtension/` - DeviceActivity report extension

### Modified Files
1. `Timeprint.xcodeproj/project.pbxproj` - Add iOS target + extension
2. `Timeprint/Data/AnalyticsModels.swift` - Move to Shared/

---

## Entitlements Required

### iOS App (`Timeprint.iOS.entitlements`)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.codybontecou.Timeprint</string>
    </array>
</dict>
</plist>
```

### DeviceActivityReport Extension
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.deviceactivityui.report</string>
    <key>NSExtensionPrincipalClass</key>
    <string>TimeprintReportExtension.ReportExtension</string>
</dict>
```

---

## Implementation Order

1. **Week 1:** Create Shared module, extract models
2. **Week 2:** Add iOS target, basic app shell
3. **Week 3:** Implement DeviceActivityReport extension
4. **Week 4:** Build compact iOS views
5. **Week 5:** Add iCloud sync infrastructure
6. **Week 6:** Unified "all devices" dashboard
7. **Week 7:** Polish & TestFlight

---

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Family Controls entitlement rejection | Apply early, have fallback mode without Screen Time |
| DeviceActivityReport API changes | Abstract behind protocol, pin iOS version |
| iCloud sync conflicts | Use CRDTs or last-write-wins per device |
| Performance on older iPhones | Lazy loading, pagination |

---

## Success Metrics

- [ ] iOS app builds and launches on device
- [ ] DeviceActivityReport shows Screen Time data
- [ ] Data syncs from iPhone to Mac within 5 minutes
- [ ] Unified view shows combined screen time
- [ ] App Store approval (TestFlight first)

---

## Next Steps (Immediate)

1. Create `Shared/` folder structure
2. Move `AnalyticsModels.swift` to shared location
3. Create `DeviceInfo` model
4. Add iOS target to Xcode project
5. Request Family Controls entitlement from Apple Developer Portal
