# ExportKit integration

`time.md` uses the standalone MIT SwiftPM package at `https://github.com/CodyBontecou/ExportKit` for reusable export mechanics while keeping all screen-time-specific data, copy, settings, and UI in this app.

## Package products

- `ExportKit` is linked into the macOS app and regression-test target for format descriptors, renderer registry, path planning, destination-relative write safety, file writing, previews, and run orchestration.
- `ExportAutomationKit` is linked because `time.md` has scheduled exports. It is used for generic daily schedule timing snapshots/date math; `time.md` still owns monthly/weekly UI behavior, destination resolution, data fetching, and schedule persistence.

## Exportable domain model audit

`time.md` exports local activity data from app-owned stores:

- Screen-time reports built from `ScreenTimeDataServing` (`DashboardSummary`, top apps/categories, trends, sessions, heatmap, focus/context-switch analytics, and raw sessions).
- Browsing reports built from `BrowsingHistoryServing` (history visits and top domains).
- Optional input-tracking aggregates/raw rows.

Existing app-owned settings remain in `ExportSettings`, `CombinedExportConfig`, `ExportSectionSelection`, `ExportFieldSelection`, and `ExportSchedule`. Existing destinations remain user-selected folders or `~/Downloads/time.md Exports`, with security-scoped bookmark resolution in `SecurityScopedBookmark` / `ExportSettings` / `ScheduledExportRunner`.

Supported text formats are preserved: CSV, JSON, YAML, Markdown, and Obsidian-flavored Markdown. Preview UI is currently limited to the export screen/status UI; the new adapter exposes `ExportPreviewBuilder` for no-write previews and tests.

## App adapter mapping

`time.md/Export/TimeMdExportKitAdapter.swift` contains the app-specific adapter layer:

- `TimeMdExportRecord`: app-owned `ExportRecord` wrapper around `ExportCoordinator.ExportReport` or an ordered combined report dictionary. It stores filters/settings so renderers can preserve existing time.md copy and formatting.
- `TimeMdExportKitAdapter.descriptor(for:)`: maps the app `ExportFormat` enum to `ExportFormatDescriptor` IDs (`timemd-csv`, `timemd-json`, etc.).
- ExportKit renderers: `rendererRegistry()` registers closures that render `TimeMdExportRecord` into the existing CSV/JSON/YAML/Markdown/Obsidian output shapes.
- Path planning: `planFile(...)` uses `ExportPathTemplate` with `.rejectTraversalAndAbsolutePaths`, preserving nested relative filenames while rejecting `..`, absolute paths, and NULs.
- Destination writing: `write(...)` and `runExport(...)` use `ExportFileWriter`/`FileManagerExportFileSystem` and `ExportDestination` rooted at the resolved output directory.
- Orchestration: `runExport(...)` wraps a single app export record in `ExportRunOrchestrator` so success/failure mapping uses ExportKit result primitives.
- Preview: `buildPreview(...)` uses `ExportPreviewBuilder` without writing files.

`ExportCoordinator.export(...)` and `exportCombined(...)` still fetch/build screen-time reports locally, then hand the app-owned payload to the ExportKit adapter for rendering, path planning, orchestration, and writing. Raw session field-selection exports keep their specialized legacy writer for compatibility.

## Automation mapping

`ExportSchedule` exposes an `automationSchedule` snapshot for `ExportAutomationKit.AutomationSchedule`. Daily `mostRecentFireDate`/`nextRunDate` use `AutomationScheduleDateMath`; weekly/monthly trigger details remain app-local to preserve current behavior. Notification copy/payloads are not integrated because `time.md` does not currently schedule export notifications.

## Tests

`time.mdRegressionTests/TimeMdExportKitAdapterTests.swift` covers renderer output, path traversal rejection, writer modes, preview generation, orchestration success/partial/failure behavior, scheduled timing bridging, and a non-domain invoice sample proving ExportKit remains generic.
