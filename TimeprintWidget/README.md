# Timeprint Widget

iOS Home Screen and Lock Screen widget that displays screen time data synced from Mac.

## Features

- **Small Widget** - Shows today's total screen time and device count
- **Medium Widget** - Shows today's total, weekly total, and 7-day trend chart
- **Lock Screen (Rectangular)** - Shows screen time with icon
- **Lock Screen (Circular)** - Compact screen time display

## Setup in Xcode

Since the widget extension requires Xcode configuration, follow these steps:

### 1. Add Widget Extension Target

1. Open `Timeprint.xcodeproj` in Xcode
2. Go to **File → New → Target**
3. Select **Widget Extension** under iOS
4. Configure:
   - **Product Name**: `TimeprintWidget`
   - **Team**: Your development team
   - **Bundle Identifier**: `bontecou.TimeprintIOS.TimeprintWidget`
   - **Include Configuration App Intent**: No
   - **Embed in Application**: `TimeprintIOS`
5. Click **Finish**

### 2. Replace Generated Files

After Xcode creates the widget target:

1. Delete the auto-generated Swift files in the `TimeprintWidget` folder
2. Keep only:
   - `TimeprintWidget.swift` (from this repo)
   - `Info.plist`
   - `TimeprintWidget.entitlements`

### 3. Configure Entitlements

1. Select the `TimeprintWidget` target
2. Go to **Signing & Capabilities**
3. Add **iCloud** capability:
   - Check "CloudKit" under Services
   - Add container: `iCloud.com.codybontecou.Timeprint`
4. Add **App Groups** capability:
   - Add group: `group.bontecou.Timeprint`

### 4. Add Shared Code

The widget needs access to `SyncPayload` and related models. Configure:

1. In Build Phases → Compile Sources, add:
   - `Timeprint/Shared/Models/SyncPayload.swift`
   - `Timeprint/Shared/Models/DeviceInfo.swift`
   - Any other shared models needed

Or create a shared framework target for better organization.

### 5. Update Main App

Add App Groups to `TimeprintIOS` for data sharing:

1. Select `TimeprintIOS` target
2. **Signing & Capabilities** → Add **App Groups**
3. Add: `group.bontecou.Timeprint`

## How It Works

The widget reads screen time data from iCloud Documents:

```
iCloud Container (iCloud.com.codybontecou.Timeprint)
└── Documents/
    └── timeprint-sync.json  ← Widget reads this
```

The macOS Timeprint app writes to this location, and the widget reads from it.

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
- Timeprint macOS app has synced at least once
- iCloud container is properly configured

### Widget not updating

- Widgets have limited refresh budget
- Force refresh: Long-press → Edit Widget → Done
- Check iCloud sync status in main app

## Bundle Identifiers

| Target | Bundle ID |
|--------|-----------|
| Main iOS App | `bontecou.TimeprintIOS` |
| Widget Extension | `bontecou.TimeprintIOS.TimeprintWidget` |

## Files

```
TimeprintWidget/
├── TimeprintWidget.swift      # Main widget code
├── Info.plist                 # Extension configuration
├── TimeprintWidget.entitlements # iCloud + App Groups
└── README.md                  # This file
```
