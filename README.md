# time.md

> **Open source, privacy-first screen time analytics for macOS — your data stays on your Mac.**

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)](#requirements)
[![Swift](https://img.shields.io/badge/swift-5.9-orange)](#building)
[![CI](https://github.com/codybontecou/time.md/actions/workflows/ci.yml/badge.svg)](https://github.com/codybontecou/time.md/actions/workflows/ci.yml)

time.md is a screen time analytics app for macOS. It reads Apple's `knowledgeC.db` system database, surfaces your daily, weekly, and monthly habits as charts, calendars, and heatmaps, and **keeps every byte of your data on-device**. No accounts. No cloud sync. No third-party dependencies. No analytics. Just you, your Mac, and your history.

**[🌐 timemd.isolated.tech](https://timemd.isolated.tech)** · **[📦 Download](https://github.com/codybontecou/time.md/releases)** · **[🛠 Contribute](CONTRIBUTING.md)** · **[⭐ Star this repo](https://github.com/codybontecou/time.md)**

## Screenshots

| Track your digital day | Own your data | Export to Obsidian |
|---|---|---|
| ![Overview dashboard with daily totals and top apps](screenshots/aso-mac/en/01-track.png) | ![Settings showing on-device iCloud sync](screenshots/aso-mac/en/02-own.png) | ![Export view with JSON, CSV, and Markdown options](screenshots/aso-mac/en/03-export.png) |

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

### 🌐 Web Browsing History
- Per-domain visit counts and time on site across Safari, Chrome, Arc, Brave, and Edge
- Daily averages and peak browsing hours

### 🔒 Privacy First
- **Local-Only** — All raw data stays on your Mac, never leaves your device
- **No Account Required** — No sign-up, no servers, no tracking
- **Your Data, Your Control** — Export anytime, delete anytime

## Requirements

- macOS 14.0+ (Sonoma)
- Full Disk Access (for `knowledgeC.db` access)
- Xcode 15.0+ (for building)

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

3. Build and run (⌘R)

### macOS Setup

The first time you run time.md, you'll need to grant Full Disk Access:

1. Open **System Settings → Privacy & Security → Full Disk Access**
2. Click the **+** button
3. Navigate to `/Applications/time.md.app` and add it
4. Restart time.md

This allows time.md to read Apple's Screen Time database (`knowledgeC.db`) and your browsers' history files.

## Architecture

```
time.md/
├── time.md/                 # macOS app
│   ├── App/                   # App entry, navigation, state
│   ├── Components/            # Reusable views
│   ├── Data/                  # SQLite services, analytics models
│   ├── DesignSystem/          # Theme, glass cards, formatters
│   ├── Export/                # Export coordinator and models
│   ├── Features/              # Views (Overview, Calendar, Trends, etc.)
│   └── Shared/                # Models, formatters, storage helpers
└── time.md.xcodeproj/       # Xcode project
```

### Data Refresh

time.md reads Screen Time data from Apple's `knowledgeC.db` system database:

| Trigger | Interval | Details |
|---------|----------|---------|
| App launch | Immediate | Forces a sync on startup |
| In-app polling | 15 minutes | Throttled to avoid excessive database reads |
| Background sync | 4 hours | Launch Agent syncs even when the app isn't running |

Apple updates `knowledgeC.db` roughly every 15–30 minutes during active use (undocumented), so polling more frequently than 15 minutes would rarely yield new data.

### Key Components

| Component | Purpose |
|-----------|---------|
| `SQLiteScreenTimeDataService` | Reads raw Screen Time data from `knowledgeC.db` |
| `SQLiteBrowsingHistoryService` | Reads browser history databases (Safari, Chrome, Arc, Brave, Edge) |
| `ActiveAppTracker` | Captures real-time app switch events |
| `GlobalFilterStore` | Manages date range and filter selections |

## Building

```bash
make build-mac
```

Or directly:

```bash
xcodebuild -scheme time.md -destination 'platform=macOS' build
```

See `make help` for the full list of build/release targets.

## Configuration

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `SCREENTIME_DB_PATH` | Override default `knowledgeC.db` path (for testing) |

### Build Settings

| Setting | Value |
|---------|-------|
| Bundle ID | `com.bontecou.time.md` |
| Team ID | `67KC823C9A` |

## Privacy

time.md is designed with privacy as a core principle:

- **No Analytics** — We don't track how you use time.md
- **No Server** — There's no backend; time.md never makes network requests for your data
- **Local-First** — All data stays on your Mac
- **Open Source** — Audit the code yourself

## Distribution

time.md is distributed directly via [GitHub Releases](https://github.com/codybontecou/time.md/releases) and [isolated.tech](https://timemd.isolated.tech). Auto-updates are delivered through [Sparkle](https://sparkle-project.org).

## Documentation

| Document | Description |
|----------|-------------|
| [`CHANGELOG.md`](CHANGELOG.md) | Version history and release notes |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | How to contribute |
| [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md) | Community guidelines |
| [`SECURITY.md`](SECURITY.md) | Security policy and reporting |

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

## License

GNU Affero General Public License v3.0 — see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with SwiftUI and Swift Charts
- Uses Apple's Screen Time data (`knowledgeC.db`)
- Design inspired by brutalist web aesthetics

---

**Made with ❤️ by [Cody Bontecou](https://codybontecou.com)**
