# time.md Widget

iOS Home Screen and Lock Screen widget that displays screen time data synced from Mac.

## Features

- **Small Widget** - Shows today's total screen time and device count
- **Medium Widget** - Shows today's total, weekly total, and 7-day trend chart
- **Lock Screen (Rectangular)** - Shows screen time with icon
- **Lock Screen (Circular)** - Compact screen time display

## Setup in Xcode

Since the widget extension requires Xcode configuration, follow these steps:

### 1. Add Widget Extension Target

1. Open `time.md.xcodeproj` in Xcode
2. Go to **File → New → Target**
3. Select **Widget Extension** under iOS
4. Configure:
   - **Product Name**: `time.mdWidget`
   - **Team**: Your development team
   - **Bundle Identifier**: `bontecou.time.mdIOS.time.mdWidget`
   - **Include Configuration App Intent**: No
   - **Embed in Application**: `time.mdIOS`
5. Click **Finish**

### 2. Replace Generated Files

After Xcode creates the widget target:

1. Delete the auto-generated Swift files in the `time.mdWidget` folder
2. Keep only:
   - `time.mdWidget.swift` (from this repo)
   - `Info.plist`
   - `time.mdWidget.entitlements`

### 3. Configure Entitlements

1. Select the `time.mdWidget` target
2. Go to **Signing & Capabilities**
3. Add **iCloud** capability:
   - Check "CloudKit" under Services
   - Add container: `iCloud.com.codybontecou.time.md`
4. Add **App Groups** capability:
   - Add group: `group.bontecou.time.md`

### 4. Add Shared Code

The widget needs access to `SyncPayload` and related models. Configure:

1. In Build Phases → Compile Sources, add:
   - `time.md/Shared/Models/SyncPayload.swift`
   - `time.md/Shared/Models/DeviceInfo.swift`
   - Any other shared models needed

Or create a shared framework target for better organization.

### 5. Update Main App

Add App Groups to `time.mdIOS` for data sharing:

1. Select `time.mdIOS` target
2. **Signing & Capabilities** → Add **App Groups**
3. Add: `group.bontecou.time.md`

## How It Works

The widget reads screen time data from iCloud Documents:

```
iCloud Container (iCloud.com.codybontecou.time.md)
└── Documents/
    └── timeprint-sync.json  ← Widget reads this
```

The macOS time.md app writes to this location, and the widget reads from it.

### Data Flow

```
macOS App → iCloud Documents → Widget reads → Displays on Home Screen
```

### Refresh Schedule

- Widget refreshes every 15 minutes
- User can also manually refresh by editing the widget

## Widget Sizes

| Family | Size | Content |
|--------|------|---------|
| Small | 2×2 | Today's total, device count |
| Medium | 4×2 | Today + week total, 7-day trend |
| Rectangular | Lock screen | Screen time with label |
| Circular | Lock screen | Compact time display |

## Troubleshooting

### "Sync from Mac" shown

The widget couldn't find sync data. Check:
- iCloud is signed in
- time.md macOS app has synced at least once
- iCloud container is properly configured

### Widget not updating

- Widgets have limited refresh budget
- Force refresh: Long-press → Edit Widget → Done
- Check iCloud sync status in main app

## Bundle Identifiers

| Target | Bundle ID |
|--------|-----------|
| Main iOS App | `bontecou.time.mdIOS` |
| Widget Extension | `bontecou.time.mdIOS.time.mdWidget` |

## Files

```
time.mdWidget/
├── time.mdWidget.swift      # Main widget code
├── Info.plist                 # Extension configuration
├── time.mdWidget.entitlements # iCloud + App Groups
└── README.md                  # This file
```
