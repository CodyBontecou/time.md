# time.md

**Personal Screen Time Analytics for macOS and iOS**

time.md is a privacy-first screen time analytics app that gives you beautiful, detailed insights into your digital habits across all your Apple devices.

[![CI](https://github.com/codybontecou/time.md/actions/workflows/ci.yml/badge.svg)](https://github.com/codybontecou/time.md/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue)
![Swift](https://img.shields.io/badge/swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

### 📊 Rich Analytics
- **Overview Dashboard** — Today's total, weekly trends, top apps at a glance
- **Trends View** — Daily, weekly, monthly usage patterns with beautiful charts
- **Apps & Categories** — See which apps consume your time, with custom category mappings
- **Session Analysis** — Understand your usage patterns with session duration buckets
- **Focus Streaks** — Track your productivity momentum

### 🗓️ Calendar Integration
- **Day View** — Hour-by-hour breakdown of any day
- **Week View** — See patterns across the week
- **Month Grid** — Bird's eye view of your monthly habits
- **Heatmaps** — Discover your most active hours and days

### 🔒 Privacy First
- **Local-Only** — Raw data never leaves your device
- **No Account Required** — No sign-up, no tracking
- **Your Data, Your Control** — Export anytime, delete anytime

### 📱 Cross-Device Sync
- **iCloud Sync** — View combined usage from Mac, iPhone, and iPad
- **iPhone Screen Time** — Native iOS Screen Time tracking via DeviceActivity
- **Aggregated Only** — Only daily summaries sync, not raw sessions
- **Automatic** — Syncs in background

## Screenshots

*Screenshots coming soon*

## Requirements

### macOS App
- macOS 14.0+ (Sonoma)
- Full Disk Access (for knowledgeC.db access)
- Xcode 15.0+ (for building)

### iOS App  
- iOS 17.0+
- iPhone or iPad
- iCloud enabled (for sync)

## Installation

### From Source

1. Clone the repository:
   ```bash
   git clone https://github.com/codybontecou/time.md.git
   cd time.md
   ```

2. Open in Xcode:
   ```bash
   open time.md.xcodeproj
   ```

3. Select target:
   - **time.md** — macOS app
   - **time.mdIOS** — iOS app

4. Build and run (⌘R)

### macOS Setup

The first time you run time.md on macOS, you'll need to grant Full Disk Access:

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click the **+** button
3. Navigate to `/Applications/time.md.app` and add it
4. Restart time.md

This allows time.md to read Apple's Screen Time database (`knowledgeC.db`).

## Architecture

```
time.md/
├── time.md/                 # macOS app
│   ├── App/                   # App entry, navigation, state
│   ├── Data/                  # SQLite services, analytics models
│   ├── Features/              # Views (Overview, Calendar, Trends, etc.)
│   ├── DesignSystem/          # Theme, glass cards, formatters
│   ├── Export/                # Export coordinator and models
│   └── Shared/                # Cross-platform code
│       ├── Models/            # DeviceInfo, SyncPayload, SharedAnalyticsModels
│       ├── Protocols/         # ScreenTimeProviding
│       ├── Formatting/        # TimeFormatters
│       └── Sync/              # iCloudSyncService
├── time.mdIOS/              # iOS app
│   ├── App/                   # time.mdIOSApp, IOSAppState
│   ├── Views/                 # CompactOverviewView, AllDevicesView, AppsListView
│   └── Assets.xcassets/       # iOS-specific assets
└── time.md.xcodeproj/       # Xcode project with both targets
```

### Data Flow

```
macOS: knowledgeC.db → SQLiteScreenTimeDataService → SyncCoordinator → iCloud
                                                                         ↕
iOS:   DeviceActivity → Report Extension → App Group → IOSAppState → iCloud Documents
```

Sync is **bidirectional** — the Mac uploads its rich data to iCloud, and the iOS app can contribute its own device data back. Both devices merge payloads per-device ID.

### Data Refresh

**macOS** reads Screen Time data from Apple's `knowledgeC.db` system database:

| Trigger | Interval | Details |
|---------|----------|---------|
| App launch | Immediate | Forces a sync on startup |
| In-app polling | 15 minutes | Throttled to avoid excessive database reads |
| Background sync | 4 hours | Launch Agent syncs even when the app isn't running |

Apple updates `knowledgeC.db` roughly every 15–30 minutes during active use (undocumented), so polling more frequently than 15 minutes would rarely yield new data.

**iOS** uses the `DeviceActivity` framework, which is event-driven rather than poll-based. The system delivers callbacks at interval boundaries (hourly, daily) and usage thresholds.

### Key Components

| Component | Purpose |
|-----------|---------|
| `SQLiteScreenTimeDataService` | Reads raw Screen Time data from macOS |
| `SyncCoordinator` | Merges local data and uploads to iCloud |
| `iCloudSyncService` | Handles iCloud Documents file operations |
| `IOSAppState` | iOS app state, reads sync data from iCloud |
| `GlobalFilterStore` | Manages date range and filter selections |

## Building

### macOS
```bash
xcodebuild -scheme time.md -destination 'platform=macOS' build
```

### iOS Simulator
```bash
xcodebuild -scheme time.mdIOS -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### iOS Device
```bash
xcodebuild -scheme time.mdIOS -destination 'generic/platform=iOS' archive
```

## iOS Screen Time Integration

The iOS app can track local iPhone Screen Time data using Apple's DeviceActivity framework. This requires:

1. **FamilyControls Entitlement** — Must be requested from Apple
2. **DeviceActivity Extensions** — Report and Monitor extensions
3. **User Authorization** — User must grant permission

See [`docs/iOS-ScreenTime-Setup.md`](docs/iOS-ScreenTime-Setup.md) for detailed setup instructions.

### Extension Targets

| Extension | Purpose |
|-----------|---------|
| `time.mdDeviceActivityReport` | Reads Screen Time data and writes top apps to App Group storage |
| `time.mdDeviceActivityMonitor` | Receives usage event callbacks (cannot write data due to sandbox) |

Source files are in `time.mdDeviceActivityReport/` and `time.mdDeviceActivityMonitor/`. See their respective READMEs for Xcode setup.

### Platform Data Comparison

The macOS and iOS apps have very different data collection capabilities due to Apple's API restrictions:

| Capability | macOS | iOS |
|------------|-------|-----|
| Per-app usage times | ✅ Full history via knowledgeC.db | ✅ Forward-looking only (no historical backfill) |
| App names & bundle IDs | ✅ | ✅ |
| Session-level detail | ✅ Individual sessions with timestamps | ❌ Daily totals + pickup counts only |
| Web browsing history | ✅ Safari, Chrome, Arc, Brave, Edge | ❌ No iOS API available |
| Category breakdown | ✅ Human-readable names | ⚠️ Opaque category tokens only |
| Hourly breakdown | ✅ | ✅ |
| Notification counts | ❌ | ✅ |
| Pickup counts | ❌ | ✅ |
| Arbitrary date ranges | ✅ Query any past date | ❌ Current monitoring period only |

### iOS Data Flow Detail

iOS data collection is constrained by Apple's sandbox model:

1. **Report Extension** (`DeviceActivityReport`) — the only component that can read the full Screen Time API. Writes the top 20 apps to the App Group `UserDefaults`.
2. **Monitor Extension** (`DeviceActivityMonitor`) — receives lifecycle and threshold callbacks but **cannot write to any shared storage** due to sandbox restrictions.
3. **Main App** — reads from App Group via `IOSScreenTimeDataService`, merges with iCloud data, and uploads the combined payload on sync.
4. **Mac App** — picks up the updated iCloud file and merges the iPhone's data into its device list.

The Report Extension is the bottleneck — data only accumulates when it runs, and it can only write to `UserDefaults` (not the JSON sync file directly).

## Configuration

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `SCREENTIME_DB_PATH` | Override default knowledgeC.db path (for testing) |

### Build Settings

| Setting | macOS | iOS |
|---------|-------|-----|
| Bundle ID | `bontecou.time.md` | `bontecou.time.mdIOS` |
| Team ID | `67KC823C9A` | `67KC823C9A` |
| iCloud Container | `iCloud.com.codybontecou.time.md` | `iCloud.com.codybontecou.time.md` |

## Privacy

time.md is designed with privacy as a core principle:

- **No Analytics** — We don't track how you use time.md
- **No Server** — There's no backend server; iCloud is the only network service
- **Local-First** — All raw data stays on your device
- **Sync is Optional** — You can use macOS-only without iCloud
- **Open Source** — Audit the code yourself

### What syncs to iCloud?

Only aggregated daily summaries per device:
- Total screen time per day
- Top apps with name, bundle ID, and total time
- Hourly usage breakdown
- Web browsing domains and visit counts (macOS only)

What **doesn't** sync:
- Individual sessions or timestamps
- Raw database access
- App icons or metadata
- Notification/pickup data

## Documentation

| Document | Description |
|----------|-------------|
| [`CHANGELOG.md`](CHANGELOG.md) | Version history and release notes |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Community guidelines |
| [`SECURITY.md`](SECURITY.md) | Security policy and reporting |
| [`docs/iOS-ScreenTime-Setup.md`](docs/iOS-ScreenTime-Setup.md) | iOS Screen Time integration setup guide |
| [`docs/Sync-Test-Plan.md`](docs/Sync-Test-Plan.md) | Cross-device sync testing procedures |
| [`time.mdDeviceActivityReport/README.md`](time.mdDeviceActivityReport/README.md) | Report extension setup |
| [`time.mdDeviceActivityMonitor/README.md`](time.mdDeviceActivityMonitor/README.md) | Monitor extension setup |

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with SwiftUI and Swift Charts
- Uses Apple's Screen Time data (knowledgeC.db)
- Design inspired by brutalist web aesthetics

---

**Made with ❤️ by [Cody Bontecou](https://codybontecou.com)**
