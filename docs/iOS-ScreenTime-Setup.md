# iOS Screen Time Integration Setup Guide

This guide covers the remaining setup steps to enable iPhone Screen Time tracking in time.md.

## Table of Contents
1. [Add Extension Targets in Xcode](#1-add-extension-targets-in-xcode)
2. [Request FamilyControls Entitlement](#2-request-familycontrols-entitlement)
3. [Configure App Groups](#3-configure-app-groups)
4. [Test the Integration](#4-test-the-integration)
5. [TestFlight Submission](#5-testflight-submission)

---

## 1. Add Extension Targets in Xcode

The source files for both extensions are ready. You need to create the targets in Xcode.

### DeviceActivityReport Extension

1. Open `time.md.xcodeproj` in Xcode
2. File → New → Target
3. Search for "Device Activity Report Extension"
4. Name it: `time.mdDeviceActivityReport`
5. Bundle ID: `com.codybontecou.time.mdIOS.DeviceActivityReport`
6. Embed in: `time.mdIOS`
7. Click Finish

**After creation:**
- Delete the auto-generated Swift files
- Add existing files from `time.mdDeviceActivityReport/`:
  - `DeviceActivityReportExtension.swift`
  - `TotalActivityReport.swift`
  - `TotalActivityView.swift`
  - `TopAppsReport.swift`
  - `TopAppsView.swift`
- Replace the generated `Info.plist` with `time.mdDeviceActivityReport/Info.plist`
- Replace entitlements with `time.mdDeviceActivityReport/time.mdDeviceActivityReport.entitlements`

### DeviceActivityMonitor Extension

1. File → New → Target
2. Search for "Device Activity Monitor Extension"
3. Name it: `time.mdDeviceActivityMonitor`
4. Bundle ID: `com.codybontecou.time.mdIOS.DeviceActivityMonitor`
5. Embed in: `time.mdIOS`
6. Click Finish

**After creation:**
- Delete the auto-generated Swift files
- Add existing file from `time.mdDeviceActivityMonitor/`:
  - `DeviceActivityMonitorExtension.swift`
- Replace the generated `Info.plist` with `time.mdDeviceActivityMonitor/Info.plist`
- Replace entitlements with `time.mdDeviceActivityMonitor/time.mdDeviceActivityMonitor.entitlements`

### Verify Extension Setup

After adding both extensions:
1. Build the iOS scheme: `⌘B`
2. Check that both extensions appear under "Products" in the navigator
3. Verify extensions are embedded in time.mdIOS (Target → Build Phases → Embed App Extensions)

---

## 2. Request FamilyControls Entitlement

**Important:** FamilyControls requires explicit approval from Apple. This process can take days to weeks.

### Step 1: Prepare Your Request

Before requesting, ensure you have:
- [ ] A clear explanation of why you need Screen Time data
- [ ] Privacy policy URL explaining data handling
- [ ] App description showing user benefit

### Step 2: Request via Apple Developer Portal

1. Go to [Apple Developer Account](https://developer.apple.com/account)
2. Navigate to: Certificates, Identifiers & Profiles → Identifiers
3. Select your App ID: `com.codybontecou.time.mdIOS`
4. Enable "Family Controls" capability
5. If prompted, submit a request explaining:

**Sample Request Text:**
```
time.md is a privacy-first screen time analytics app that helps users understand 
their digital habits. We need FamilyControls access to:

1. Display users' own screen time data in our app
2. Provide personalized insights based on usage patterns
3. Sync usage data across user's devices via iCloud

We do NOT:
- Collect or transmit data to external servers
- Use parental controls features
- Track other family members' devices

All data stays on-device or in user's private iCloud container.
Privacy Policy: https://timeprint.app/privacy
```

### Step 3: Wait for Approval

- Apple typically responds within 1-2 weeks
- You may receive clarifying questions
- Once approved, the capability will be available in your provisioning profiles

### Step 4: Update Provisioning Profiles

After approval:
1. Go to Profiles in Apple Developer Portal
2. Regenerate your development and distribution profiles
3. Download and install new profiles
4. In Xcode: Preferences → Accounts → Download Manual Profiles

---

## 3. Configure App Groups

App Groups are required for the main app and extensions to share data.

### Verify App Group Configuration

The App Group `group.com.codybontecou.time.md` should be configured in:
- [ ] `time.mdIOS.entitlements`
- [ ] `time.mdDeviceActivityReport.entitlements`
- [ ] `time.mdDeviceActivityMonitor.entitlements`

### Register App Group (if not already done)

1. Apple Developer Portal → Identifiers → App Groups
2. Click "+" to register new App Group
3. Description: "time.md Data Sharing"
4. Identifier: `group.com.codybontecou.time.md`
5. Click Continue → Register

### Add to App IDs

For each App ID (main app + both extensions):
1. Edit the App ID
2. Enable "App Groups" capability
3. Select `group.com.codybontecou.time.md`
4. Save

---

## 4. Test the Integration

### Prerequisites for Testing
- Physical iPhone (Screen Time doesn't work in Simulator)
- FamilyControls entitlement approved
- Extensions properly embedded

### Test Checklist

#### Authorization Flow
- [ ] Launch app → Onboarding appears
- [ ] "Grant Permission" shows system dialog
- [ ] After approval, onboarding completes
- [ ] Settings shows "Authorized" status

#### Data Collection
- [ ] Daily monitoring starts after authorization
- [ ] Use iPhone for 10+ minutes
- [ ] Check App Group container for data:
  ```bash
  # On device via Xcode
  # Window → Devices and Simulators → [Device] → time.md → Download Container
  ```

#### Sync Flow
- [ ] iPhone uploads data during sync
- [ ] Mac receives iPhone data via iCloud
- [ ] Device breakdown shows both devices
- [ ] Totals combine correctly

#### Extension Testing
- [ ] DeviceActivityReport renders in app
- [ ] Monitor extension fires at interval end
- [ ] Data persists to App Group

### Debug Tips

**Check authorization status:**
```swift
print(AuthorizationCenter.shared.authorizationStatus)
```

**Check App Group data:**
```swift
let defaults = UserDefaults(suiteName: "group.com.codybontecou.time.md")
print(defaults?.dictionaryRepresentation())
```

**Monitor extension logs:**
```bash
# In Terminal while device connected
log stream --predicate 'subsystem == "com.codybontecou.time.md.Monitor"'
```

---

## 5. TestFlight Submission

### Pre-Submission Checklist

#### App Configuration
- [ ] Version number updated (`MARKETING_VERSION`)
- [ ] Build number incremented (`CURRENT_PROJECT_VERSION`)
- [ ] All entitlements properly configured
- [ ] Extensions embedded and signed

#### App Store Connect Setup
- [ ] App record created
- [ ] Privacy policy URL added
- [ ] App description written
- [ ] Screenshots prepared (if updating)

#### Build & Upload

```bash
# Archive the app
xcodebuild -scheme time.mdIOS \
  -destination 'generic/platform=iOS' \
  -archivePath build/time.mdIOS.xcarchive \
  archive

# Export for App Store
xcodebuild -exportArchive \
  -archivePath build/time.mdIOS.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

Or use Xcode:
1. Product → Archive
2. Distribute App → App Store Connect
3. Upload

#### TestFlight Configuration
1. Go to App Store Connect → TestFlight
2. Select the uploaded build
3. Add export compliance information
4. Submit for Beta App Review (if using FamilyControls)
5. Add internal/external testers

### FamilyControls Review Notes

Apple may review FamilyControls usage more carefully. Include:
- Explanation of Screen Time data usage
- Confirmation data stays on-device/iCloud
- Note that this is personal use, not parental controls

---

## Troubleshooting

### "FamilyControls capability not available"
- Entitlement not approved yet
- Check Apple Developer Portal status

### "Extension not loading"
- Verify extension is embedded in main app target
- Check extension bundle ID matches Info.plist
- Rebuild after clean (`⌘⇧K` then `⌘B`)

### "No data appearing"
- Ensure authorization was granted
- Check monitoring is scheduled (Settings → Tracking Status)
- Verify App Group data is being written

### "Sync not working"
- Check iCloud account is signed in
- Verify iCloud container exists
- Check network connectivity

---

## Architecture Reference

```
┌─────────────────────────────────────────────────────────────┐
│                      time.mdIOS                            │
│  ┌──────────────────┐  ┌──────────────────┐                 │
│  │ AuthorizationSvc │  │ IOSScreenTimeSvc │                 │
│  └────────┬─────────┘  └────────┬─────────┘                 │
│           │                     │                            │
│           ▼                     ▼                            │
│  ┌────────────────────────────────────────┐                 │
│  │         SharedDataStore                 │                 │
│  │    (App Group Container)                │                 │
│  └────────────────────────────────────────┘                 │
│                      ▲                                       │
└──────────────────────┼───────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
        ▼              │              ▼
┌───────────────┐      │      ┌───────────────┐
│ Report Ext    │      │      │ Monitor Ext   │
│ (UI Display)  │      │      │ (Background)  │
└───────────────┘      │      └───────────────┘
                       │
                       ▼
              ┌───────────────┐
              │ iCloud Sync   │
              │ (SyncPayload) │
              └───────┬───────┘
                      │
                      ▼
              ┌───────────────┐
              │ time.md Mac │
              └───────────────┘
```
