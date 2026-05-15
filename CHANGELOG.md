# Changelog

All notable changes to time.md will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.5.0] - 2026-05-15

### Added
- Firefox web history support, including standard local Firefox profile databases.
- Automatic local screen-time snapshot at `~/Library/Application Support/time.md/screen-time-snapshot.json`, refreshed without running an export.
- Live formatted auto-export (`screen-time-auto.<ext>`) that follows the user's last selected export format, sections, and relative date range.
- Global MCP server on/off switch in Settings, backed by a runtime guard in `timemd-mcp`.

### Changed
- Web History now reads browser history databases directly again for direct-distribution builds, removing per-browser Apple Events prompts when Safari, Chrome, Firefox, Arc, Brave, or Edge becomes active.

## [2.3.0] - 2026-05-05

### Added
- **Input tracking (opt-in)** — capture keystrokes and cursor activity locally to power per-app typing intensity, top-typed-words, top-typed-keys, and a per-screen cursor heatmap. Off by default; gated behind Accessibility + Input Monitoring permissions. Granular tracking levels for both streams and a global ⌥⌘P pause hotkey.
- Privacy guards: Secure Input mode auto-redacts characters; configurable per-app exclusion list (1Password, Bitwarden, Keychain Access, etc. by default); raw events pruned on a configurable retention window (default 14 days keystrokes / 7 days mouse).
- Input data is exposed to the timemd-mcp server via new tools: `get_cursor_heatmap`, `get_top_typed_words`, `get_top_typed_keys`, `get_typing_intensity`, `get_input_event_counts`.
- Export coordinator can include raw keystroke / mouse rows and the derived aggregates.

### Changed
- Input-tracking tables now live in a sibling `input-tracking.db` rather than the main `screentime.db`. Dashboard and menu-bar queries that take a snapshot copy of the main DB no longer carry the high-volume `mouse_events` rows, restoring snappy load times. A one-time migration moves any existing rows out of `screentime.db` and reclaims the freed pages.

## [2.2.0] - 2026-05-05

### Changed
- **time.md is now free.** All paywall and subscription functionality has been removed; no purchase, account, or trial is required.
- **Direct distribution only.** The app is no longer published to the Mac App Store. Releases are notarized and distributed via [GitHub Releases](https://github.com/codybontecou/time.md/releases) and [isolated.tech](https://timemd.isolated.tech), with auto-updates delivered through Sparkle.

### Removed
- StoreKit / in-app purchase code (`PaywallView`, `SubscriptionStore`, `StoreKitConfiguration.storekit`)
- App Store distribution scaffolding (`fastlane/`, `metadata/`, `ExportOptions-AppStore.plist`)
- iOS app and related documentation — time.md is macOS-only

### Why
The Mac App Store sandbox prevents reading other apps' history files, so web-history tracking can't ship through the store. Going direct lets us keep that feature and drop the paywall in the same release.

## [2.0.1] - 2026-04-12

### Added
- Automated isolated.tech publishing via `.github/workflows/isolated-publish.yml`

### Changed
- Build bumped to 11

## [2.0.0] - 2026-04-11

### Added
- **Overview** — Color-coded timeline bar of app usage blocks, summary stat cards (total time, daily avg, peak hour, apps used), and top apps breakdown
- **Review** — Switchable bar/pie/trend charts, app vs category grouping, activity heatmap, and full data tables
- **Details** — Vertical session timeline with timestamps, icons, duration bars; sidebar with session stats, top transitions, and context-switch analysis
- **Projects** — Hierarchical project/category view with expandable groups, distribution pie chart, search, and inline category editing
- **Rules** — Bulk category assignment with search, unmapped-only filter, coverage tracking, and category suggestions
- **Reports** — Time distribution charts, weekday averages, grouping by app/category/day, and CSV/JSON/Markdown export

### Changed
- Complete UI rebuild inspired by the Timing app
- Reorganized sidebar: Tracking / Organize / Data / System
- Keyboard shortcuts updated to ⌘1–⌘8

## [1.1.1] - 2026-02-26

### Added
- Refresh data button in sidebar for local database sync

## [1.1.0] - 2026-02-25

### Added
- iOS companion app with cross-device sync
- iPhone Screen Time tracking via DeviceActivity framework
- iCloud sync for viewing combined usage across all Apple devices
- Home Screen widgets (small, medium, lock screen)
- Siri Shortcuts integration ("How much screen time do I have?")
- Device breakdown cards showing usage per device
- Sync status indicators
- Screen Time onboarding flow for iOS
- Export to CSV, JSON, and PDF formats
- Focus streak tracking

### Changed
- Improved overview dashboard with cleaner design
- Enhanced trend charts with Swift Charts
- Better category mapping for apps

### Fixed
- Various UI polish and accessibility improvements

## [1.0.0] - 2026-02-24

### Added
- Initial release
- macOS Screen Time analytics
- Overview dashboard with daily stats
- Trends view with daily/weekly/monthly charts
- Calendar view with day, week, and month modes
- Apps & Categories breakdown
- Session analysis with duration buckets
- Heatmap visualizations
- Custom date range filtering
- App category customization
- Full Disk Access integration for knowledgeC.db
- Privacy-first local-only data processing
- Beautiful glass-morphism design system

---

## Version History

| Version | Date | Highlights |
|---------|------|------------|
| 2.5.0 | 2026-05-15 | Firefox web history, live auto-export snapshots, MCP server toggle |
| 2.2.0 | 2026-05-05 | Free to use; direct distribution; macOS-only |
| 2.0.1 | 2026-04-12 | Automated isolated.tech publishing |
| 2.0.0 | 2026-04-11 | Timing-inspired UI rebuild — new Overview, Review, Details, Projects, Rules, Reports |
| 1.1.1 | 2026-02-26 | Refresh data button for local sync |
| 1.1.0 | 2026-02-25 | iOS companion app, iCloud sync, widgets, export features |
| 1.0.0 | 2026-02-24 | Initial release with macOS analytics |

[Unreleased]: https://github.com/codybontecou/time.md/compare/v2.5.0...HEAD
[2.5.0]: https://github.com/codybontecou/time.md/releases/tag/v2.5.0
[2.2.0]: https://github.com/codybontecou/time.md/releases/tag/v2.2.0
[2.0.1]: https://github.com/codybontecou/time.md/releases/tag/v2.0.1
[2.0.0]: https://github.com/codybontecou/time.md/releases/tag/v2.0.0
[1.1.1]: https://github.com/codybontecou/time.md/releases/tag/v1.1.1
[1.1.0]: https://github.com/codybontecou/time.md/releases/tag/v1.1
[1.0.0]: https://github.com/codybontecou/time.md/releases/tag/v1.0.0
