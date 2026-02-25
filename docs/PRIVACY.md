# Privacy Policy

**time.md**  
*Last updated: February 2026*

## Overview

time.md is a privacy-first screen time analytics app. We believe your data belongs to you, and we've designed our app to keep it that way.

## Data We Collect

**We do not collect any personal data.**

time.md operates entirely on your device. We have no servers, no analytics, and no way to see your screen time data.

## How time.md Works

### On macOS
- time.md reads Apple's Screen Time database (`knowledgeC.db`) that's already stored locally on your Mac
- This data was collected by Apple's Screen Time feature, not by time.md
- time.md processes this data locally to show you analytics and visualizations
- No data is sent to us

### On iOS
- time.md displays screen time data synced from your Mac via iCloud
- This sync happens between your own devices through your personal iCloud account
- We have no access to your iCloud data

## iCloud Sync

If you enable iCloud sync:
- Only **aggregated daily summaries** are synced (total time per day, top apps)
- **Individual sessions are NOT synced** — timestamps and detailed usage patterns stay local
- Sync occurs through Apple's iCloud Documents, which is encrypted end-to-end
- We cannot access your iCloud data

## Data Storage

| Data Type | Where Stored | Who Can Access |
|-----------|--------------|----------------|
| Raw screen time sessions | Your Mac only | Only you |
| Daily aggregates | iCloud (if enabled) | Only you (and your Apple ID) |
| Category mappings | Your Mac only | Only you |
| App preferences | Your device only | Only you |

## Third-Party Services

time.md uses the following Apple services:
- **iCloud Documents** — For optional cross-device sync
- **Screen Time (macOS)** — Source of usage data

We do not use any third-party analytics, advertising, or tracking services.

## Data Deletion

You can delete your time.md data at any time:

1. **Delete app data**: Remove time.md from your device
2. **Delete sync data**: Go to Settings → Apple ID → iCloud → Manage Storage → time.md
3. **Delete preferences**: Remove `~/Library/Application Support/time.md/` on macOS

## Children's Privacy

time.md does not knowingly collect data from children under 13. The app displays data that Apple's Screen Time has already collected through iOS/macOS parental controls.

## Changes to This Policy

We may update this privacy policy from time to time. We will notify you of any changes by posting the new policy on this page and updating the "Last updated" date.

## Contact

If you have questions about this privacy policy, please contact:

**Email**: privacy@codybontecou.com  
**Website**: https://codybontecou.com

---

## App Store Privacy Details

For the App Store privacy "nutrition label":

### Data Not Collected
time.md does not collect any data from users.

### Data Not Linked to You
N/A — No data is collected.

### Tracking
time.md does not track users across apps or websites owned by other companies.
