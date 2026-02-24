# Cross-Device Sync Test Plan

This document outlines test scenarios for verifying the Timeprint cross-device sync functionality.

## Test Environment Requirements

### Devices Needed
- [ ] Mac with macOS 14+ (for Timeprint Mac app)
- [ ] iPhone with iOS 16+ (for Timeprint iOS app)
- [ ] Both devices signed into same iCloud account

### Pre-Test Setup
1. Install Timeprint on Mac
2. Install TimeprintIOS on iPhone
3. Ensure iCloud Drive is enabled on both devices
4. Verify iCloud sync is working (check Files app)

---

## Test Suite 1: Basic Sync Operations

### Test 1.1: Mac → iCloud Upload
**Objective:** Verify Mac uploads local data to iCloud

**Steps:**
1. Use Mac normally for 30+ minutes
2. Open Timeprint Mac app
3. Wait for sync to complete (check sync indicator)
4. Open Files app on iPhone → iCloud Drive → Timeprint

**Expected:**
- [ ] `timeprint-sync.json` file exists
- [ ] File contains Mac device data
- [ ] `lastModified` timestamp is recent

### Test 1.2: iPhone → iCloud Upload
**Objective:** Verify iPhone uploads local Screen Time data

**Prerequisites:** FamilyControls authorized on iPhone

**Steps:**
1. Use iPhone for 30+ minutes
2. Open TimeprintIOS app
3. Pull to refresh / tap Sync Now
4. Check iCloud Drive for updated sync file

**Expected:**
- [ ] Sync file updated with iPhone data
- [ ] iPhone device appears in devices array
- [ ] `dailySummaries` contains iPhone usage

### Test 1.3: Mac ← iCloud Download
**Objective:** Verify Mac receives iPhone data

**Steps:**
1. Ensure iPhone has synced (Test 1.2)
2. Open Timeprint Mac app
3. Navigate to Overview
4. Check for Device Breakdown card

**Expected:**
- [ ] Device Breakdown card appears
- [ ] Shows both Mac and iPhone
- [ ] iPhone usage displayed with correct values

### Test 1.4: iPhone ← iCloud Download
**Objective:** Verify iPhone receives Mac data

**Steps:**
1. Ensure Mac has synced (Test 1.1)
2. Open TimeprintIOS app
3. Pull to refresh
4. Check All Devices view

**Expected:**
- [ ] Mac data visible in app
- [ ] Combined totals include Mac usage
- [ ] Last sync timestamp updated

---

## Test Suite 2: Data Integrity

### Test 2.1: Data Merging
**Objective:** Verify data from multiple devices merges correctly

**Steps:**
1. Generate usage on Mac: 2 hours Safari
2. Generate usage on iPhone: 1 hour Instagram
3. Sync both devices
4. Check combined totals on both

**Expected:**
- [ ] Total = 3 hours (Mac + iPhone)
- [ ] Safari shows 2 hours
- [ ] Instagram shows 1 hour
- [ ] Per-device breakdown is accurate

### Test 2.2: Conflict Resolution
**Objective:** Verify newer data wins in conflicts

**Steps:**
1. Sync Mac (creates baseline)
2. Take iPhone offline
3. Use Mac for 1 hour more
4. Sync Mac again
5. Bring iPhone online
6. Sync iPhone

**Expected:**
- [ ] Mac's newer data preserved
- [ ] iPhone data merged without loss
- [ ] No duplicate entries

### Test 2.3: Historical Data
**Objective:** Verify historical data syncs correctly

**Steps:**
1. Use devices for multiple days
2. Sync after each day
3. Check 7-day trend on both devices

**Expected:**
- [ ] Same trend data on both devices
- [ ] All days represented
- [ ] No gaps in data

---

## Test Suite 3: Error Handling

### Test 3.1: Offline Sync Attempt
**Objective:** Verify graceful handling of offline state

**Steps:**
1. Put device in Airplane Mode
2. Open app
3. Attempt to sync

**Expected:**
- [ ] App doesn't crash
- [ ] Error message displayed
- [ ] Local data still accessible

### Test 3.2: iCloud Not Signed In
**Objective:** Verify handling when iCloud unavailable

**Steps:**
1. Sign out of iCloud
2. Open app
3. Check sync status

**Expected:**
- [ ] Sync disabled gracefully
- [ ] Message indicates iCloud required
- [ ] Local data still works

### Test 3.3: Corrupted Sync File
**Objective:** Verify recovery from corrupted data

**Steps:**
1. Manually corrupt sync file in iCloud Drive
2. Open app
3. Attempt to sync

**Expected:**
- [ ] Error logged
- [ ] App doesn't crash
- [ ] Option to reset sync data

---

## Test Suite 4: Performance

### Test 4.1: Large Dataset Sync
**Objective:** Verify sync handles 30+ days of data

**Steps:**
1. Accumulate 30 days of usage data
2. Perform full sync
3. Measure sync time

**Expected:**
- [ ] Sync completes in < 10 seconds
- [ ] No UI freezing
- [ ] Memory usage reasonable

### Test 4.2: Frequent Sync
**Objective:** Verify multiple rapid syncs work

**Steps:**
1. Sync 5 times in quick succession
2. Check data consistency

**Expected:**
- [ ] All syncs complete
- [ ] No duplicate data
- [ ] No race conditions

---

## Test Suite 5: Edge Cases

### Test 5.1: New Device Added
**Objective:** Verify adding a third device works

**Steps:**
1. Have Mac and iPhone syncing
2. Add iPad to same iCloud account
3. Install and open Timeprint on iPad

**Expected:**
- [ ] iPad sees Mac + iPhone data
- [ ] iPad can add its own data
- [ ] Three devices in breakdown

### Test 5.2: Device Removed
**Objective:** Verify handling of removed device

**Steps:**
1. Sync Mac and iPhone
2. Uninstall from iPhone
3. Check Mac continues to show iPhone historical data

**Expected:**
- [ ] Historical iPhone data preserved
- [ ] No new iPhone data appears
- [ ] Mac sync continues working

### Test 5.3: Time Zone Changes
**Objective:** Verify date handling across time zones

**Steps:**
1. Change iPhone time zone
2. Generate usage
3. Sync
4. Check dates align on Mac

**Expected:**
- [ ] Dates correct on both devices
- [ ] No duplicate days
- [ ] Daily boundaries respected

---

## Regression Checklist

After any sync-related changes, verify:

- [ ] Mac upload works
- [ ] iPhone upload works
- [ ] Mac download works
- [ ] iPhone download works
- [ ] Data integrity maintained
- [ ] Error handling graceful
- [ ] Performance acceptable

---

## Logging Commands

**View sync activity on Mac:**
```bash
log stream --predicate 'subsystem == "com.codybontecou.Timeprint"' --info
```

**View sync activity on iPhone:**
Connect via Xcode → Window → Devices and Simulators → Open Console

**Check iCloud sync file:**
```bash
# On Mac
cat ~/Library/Mobile\ Documents/iCloud~com~codybontecou~Timeprint/Documents/timeprint-sync.json | jq .
```

---

## Test Results Template

| Test ID | Description | Pass/Fail | Notes | Date |
|---------|-------------|-----------|-------|------|
| 1.1 | Mac → iCloud Upload | | | |
| 1.2 | iPhone → iCloud Upload | | | |
| 1.3 | Mac ← iCloud Download | | | |
| 1.4 | iPhone ← iCloud Download | | | |
| 2.1 | Data Merging | | | |
| 2.2 | Conflict Resolution | | | |
| 2.3 | Historical Data | | | |
| 3.1 | Offline Sync | | | |
| 3.2 | No iCloud | | | |
| 3.3 | Corrupted File | | | |
| 4.1 | Large Dataset | | | |
| 4.2 | Frequent Sync | | | |
| 5.1 | New Device | | | |
| 5.2 | Device Removed | | | |
| 5.3 | Time Zones | | | |
