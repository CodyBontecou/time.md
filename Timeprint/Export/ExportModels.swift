import Foundation
import SwiftUI  // For IndexSet/Array move operations

// MARK: - Export Field Definitions

/// Defines all available fields for export, organized by scope.
enum ExportField: String, CaseIterable, Identifiable, Codable, Hashable {
    // Raw Session fields
    case appName = "app_name"
    case startTime = "start_time"
    case endTime = "end_time"
    case durationSeconds = "duration_seconds"
    
    // App/Category fields
    case totalSeconds = "total_seconds"
    case sessionCount = "session_count"
    case category = "category"
    
    // Trend/Date fields
    case date = "date"
    
    // Heatmap fields
    case weekday = "weekday"
    case hour = "hour"
    
    // Focus fields
    case focusBlocks = "focus_blocks"
    
    // Summary fields
    case metric = "metric"
    case value = "value"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .appName: return "App Name"
        case .startTime: return "Start Time"
        case .endTime: return "End Time"
        case .durationSeconds: return "Duration (seconds)"
        case .totalSeconds: return "Total Seconds"
        case .sessionCount: return "Session Count"
        case .category: return "Category"
        case .date: return "Date"
        case .weekday: return "Weekday"
        case .hour: return "Hour"
        case .focusBlocks: return "Focus Blocks"
        case .metric: return "Metric"
        case .value: return "Value"
        }
    }
    
    /// Fields available for Raw Sessions export
    static let rawSessionFields: [ExportField] = [.appName, .startTime, .endTime, .durationSeconds]
    
    /// Fields available for Apps export
    static let appFields: [ExportField] = [.appName, .totalSeconds, .sessionCount]
    
    /// Fields available for Categories export
    static let categoryFields: [ExportField] = [.category, .totalSeconds]
    
    /// Fields available for Trends export
    static let trendFields: [ExportField] = [.date, .totalSeconds]
    
    /// Fields available for Sessions (buckets) export
    static let sessionBucketFields: [ExportField] = [.metric, .sessionCount]
    
    /// Fields available for Heatmap export
    static let heatmapFields: [ExportField] = [.weekday, .hour, .totalSeconds]
    
    /// Fields available for Focus export
    static let focusFields: [ExportField] = [.date, .focusBlocks, .totalSeconds]
    
    /// Fields available for Overview summary export
    static let overviewFields: [ExportField] = [.metric, .value]
}

/// User's field selection for export
struct ExportFieldSelection: Codable, Equatable {
    var selectedFields: Set<ExportField>
    
    /// Returns fields filtered by selection, maintaining original order
    func filter(_ fields: [ExportField]) -> [ExportField] {
        fields.filter { selectedFields.contains($0) }
    }
    
    /// Initialize with all fields selected by default
    static func defaultSelection(for fields: [ExportField]) -> ExportFieldSelection {
        ExportFieldSelection(selectedFields: Set(fields))
    }
    
    /// Check if all fields are selected
    func allSelected(from fields: [ExportField]) -> Bool {
        Set(fields).isSubset(of: selectedFields)
    }
    
    /// Check if no fields are selected
    var isEmpty: Bool {
        selectedFields.isEmpty
    }
}

// MARK: - CSV Export Options

/// CSV format customization options
struct CSVExportOptions: Codable, Equatable {
    var delimiter: CSVDelimiter = .comma
    var quoteStyle: CSVQuoteStyle = .whenNeeded
    var includeHeader: Bool = true
    var includeMetadataComments: Bool = true
    
    enum CSVDelimiter: String, CaseIterable, Identifiable, Codable {
        case comma = ","
        case tab = "\t"
        case semicolon = ";"
        case pipe = "|"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .comma: return "Comma (,)"
            case .tab: return "Tab"
            case .semicolon: return "Semicolon (;)"
            case .pipe: return "Pipe (|)"
            }
        }
    }
    
    enum CSVQuoteStyle: String, CaseIterable, Identifiable, Codable {
        case always
        case whenNeeded
        case never
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .always: return "Always"
            case .whenNeeded: return "When Needed"
            case .never: return "Never"
            }
        }
    }
    
    /// Escape a value according to configured options
    func escape(_ value: String) -> String {
        switch quoteStyle {
        case .always:
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        case .whenNeeded:
            let needsQuoting = value.contains(delimiter.rawValue) ||
                              value.contains("\"") ||
                              value.contains("\n") ||
                              value.contains("\r")
            if needsQuoting {
                let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            return value
        case .never:
            return value
        }
    }
}

// MARK: - JSON Export Options

/// JSON format customization options
struct JSONExportOptions: Codable, Equatable {
    var structure: JSONStructure = .nested
    var prettyPrint: Bool = true
    var includeMetadata: Bool = true
    var sortKeys: Bool = true
    
    enum JSONStructure: String, CaseIterable, Identifiable, Codable {
        case flat       // Array of simple objects
        case nested     // Wrapped with metadata
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .flat: return "Flat Array"
            case .nested: return "Nested with Metadata"
            }
        }
        
        var description: String {
            switch self {
            case .flat: return "[{...}, {...}]"
            case .nested: return "{\"data\": [...], \"meta\": {...}}"
            }
        }
    }
    
    var writingOptions: JSONSerialization.WritingOptions {
        var options: JSONSerialization.WritingOptions = []
        if prettyPrint { options.insert(.prettyPrinted) }
        if sortKeys { options.insert(.sortedKeys) }
        return options
    }
}

// MARK: - Export Sections (for Combined Exports)

/// Individual data sections that can be included in a combined export
enum ExportSection: String, CaseIterable, Identifiable, Codable {
    // Basic data sections
    case summary = "summary"
    case apps = "apps"
    case categories = "categories"
    case trends = "trends"
    case sessions = "sessions"
    case heatmap = "heatmap"
    case rawSessions = "raw_sessions"
    
    // Analytics sections
    case contextSwitches = "context_switches"
    case appTransitions = "app_transitions"
    case periodComparison = "period_comparison"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .summary: return "Summary"
        case .apps: return "Top Apps"
        case .categories: return "Categories"
        case .trends: return "Trends"
        case .sessions: return "Session Distribution"
        case .heatmap: return "Heatmap"
        case .rawSessions: return "Raw Sessions"
        case .contextSwitches: return "Context Switches"
        case .appTransitions: return "App Transitions"
        case .periodComparison: return "Period Comparison"
        }
    }
    
    var systemImage: String {
        switch self {
        case .summary: return "chart.bar.doc.horizontal"
        case .apps: return "app.badge"
        case .categories: return "folder"
        case .trends: return "chart.line.uptrend.xyaxis"
        case .sessions: return "clock"
        case .heatmap: return "square.grid.3x3"
        case .rawSessions: return "list.bullet"
        case .contextSwitches: return "arrow.triangle.swap"
        case .appTransitions: return "arrow.right.arrow.left"
        case .periodComparison: return "chart.bar.xaxis.ascending"
        }
    }
    
    var description: String {
        switch self {
        case .summary: return "Total time and averages"
        case .apps: return "Usage time per application"
        case .categories: return "Usage time by category"
        case .trends: return "Daily/weekly usage over time"
        case .sessions: return "Session length distribution"
        case .heatmap: return "Usage by weekday and hour"
        case .rawSessions: return "Individual session records"
        case .contextSwitches: return "App switching frequency by hour"
        case .appTransitions: return "Most common app-to-app switches"
        case .periodComparison: return "Current vs previous period delta"
        }
    }
    
    /// Estimated row count weight for this section (relative)
    var rowWeight: Int {
        switch self {
        case .summary: return 1
        case .apps: return 50
        case .categories: return 10
        case .trends: return 30
        case .sessions: return 6
        case .heatmap: return 168  // 7 days * 24 hours
        case .rawSessions: return 1000  // Can be very large
        case .contextSwitches: return 100
        case .appTransitions: return 50
        case .periodComparison: return 20
        }
    }
    
    /// Whether this section supports field customization
    var supportsFieldSelection: Bool {
        switch self {
        case .rawSessions: return true
        default: return false  // Most sections have fixed fields
        }
    }
    
    /// Whether this is an analytics (computed) section
    var isAnalytics: Bool {
        switch self {
        case .contextSwitches, .appTransitions, .periodComparison:
            return true
        default:
            return false
        }
    }
    
    /// Basic data sections only
    static let basicSections: [ExportSection] = [
        .summary, .apps, .categories, .trends, .sessions, .heatmap, .rawSessions
    ]
    
    /// Analytics sections only
    static let analyticsSections: [ExportSection] = [
        .contextSwitches, .appTransitions, .periodComparison
    ]
}

/// A set of sections to include in a combined export
struct ExportSectionSelection: Codable, Equatable {
    var sections: [ExportSection]  // Ordered list (order matters for output)
    
    init(sections: [ExportSection] = ExportSection.allCases.filter { $0 != .rawSessions }) {
        self.sections = sections
    }
    
    var isEmpty: Bool { sections.isEmpty }
    var count: Int { sections.count }
    
    func contains(_ section: ExportSection) -> Bool {
        sections.contains(section)
    }
    
    mutating func toggle(_ section: ExportSection) {
        if let index = sections.firstIndex(of: section) {
            sections.remove(at: index)
        } else {
            sections.append(section)
        }
    }
    
    mutating func move(from source: IndexSet, to destination: Int) {
        sections.move(fromOffsets: source, toOffset: destination)
    }
    
    static let allExceptRaw = ExportSectionSelection(
        sections: ExportSection.basicSections.filter { $0 != .rawSessions }
    )
    
    static let quickSummary = ExportSectionSelection(
        sections: [.summary, .apps, .trends]
    )
    
    static let full = ExportSectionSelection(
        sections: ExportSection.allCases
    )
    
    /// All basic data sections (no analytics)
    static let basicOnly = ExportSectionSelection(
        sections: ExportSection.basicSections
    )
    
    /// Analytics sections only
    static let analyticsOnly = ExportSectionSelection(
        sections: ExportSection.analyticsSections
    )
    
    /// Standard data + analytics (no raw sessions)
    static let withAnalytics = ExportSectionSelection(
        sections: ExportSection.basicSections.filter { $0 != .rawSessions } + ExportSection.analyticsSections
    )
}

/// Configuration for a combined export operation
struct CombinedExportConfig: Codable {
    var sections: ExportSectionSelection
    var format: ExportFormat
    var filenameTemplate: String
    var includeTimestamp: Bool
    
    init(
        sections: ExportSectionSelection = .allExceptRaw,
        format: ExportFormat = .csv,
        filenameTemplate: String = "timeprint-export",
        includeTimestamp: Bool = true
    ) {
        self.sections = sections
        self.format = format
        self.filenameTemplate = filenameTemplate
        self.includeTimestamp = includeTimestamp
    }
    
    /// Generate the filename for this export
    func generateFilename(date: Date = Date()) -> String {
        var name = filenameTemplate
        
        if includeTimestamp {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            name += "-\(formatter.string(from: date))"
        }
        
        return name
    }
}

// MARK: - Timestamp Formats

/// Configurable timestamp format for export output.
enum ExportTimestampFormat: String, CaseIterable, Identifiable, Codable {
    case iso8601Full       // 2026-02-23T17:53:16-04:00
    case iso8601DateHour   // 2026-02-23T17
    case dateOnly          // 2026-02-23
    case unixEpoch         // 1740343996

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iso8601Full: return "ISO 8601 Full"
        case .iso8601DateHour: return "ISO 8601 Date+Hour"
        case .dateOnly: return "Date Only"
        case .unixEpoch: return "Unix Timestamp"
        }
    }

    var example: String {
        format(Date())
    }

    func format(_ date: Date) -> String {
        switch self {
        case .iso8601Full:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = .current
            return formatter.string(from: date)

        case .iso8601DateHour:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd'T'HH"
            return formatter.string(from: date)

        case .dateOnly:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)

        case .unixEpoch:
            return String(Int(date.timeIntervalSince1970))
        }
    }
}

// MARK: - Export Estimation

/// File size and row count estimation for pending exports.
struct ExportEstimate: Sendable {
    let rowCount: Int
    let estimatedBytes: Int

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(estimatedBytes), countStyle: .file)
    }

    var formattedRowCount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: rowCount)) ?? "\(rowCount)"
    }

    var isLarge: Bool {
        rowCount > 1000
    }

    /// Rough estimate: CSV ~50 bytes/row, JSON ~80 bytes/row
    static func estimate(rowCount: Int, format: ExportFormat) -> ExportEstimate {
        let bytesPerRow: Int
        switch format {
        case .csv: bytesPerRow = 50
        case .json: bytesPerRow = 80
        case .png, .pdf: bytesPerRow = 0 // Images don't scale linearly with rows
        }

        let estimated = rowCount * bytesPerRow
        return ExportEstimate(rowCount: rowCount, estimatedBytes: estimated)
    }
}

// MARK: - Export Progress

/// Progress tracking for long-running exports.
@MainActor
@Observable
final class ExportProgress {
    var currentRow: Int = 0
    var totalRows: Int = 0
    var isCancelled: Bool = false
    var isComplete: Bool = false

    var fractionComplete: Double {
        guard totalRows > 0 else { return 0 }
        return Double(currentRow) / Double(totalRows)
    }

    var statusText: String {
        if isComplete {
            return "Export complete"
        }
        if isCancelled {
            return "Export cancelled"
        }
        if totalRows == 0 {
            return "Preparing..."
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let currentStr = formatter.string(from: NSNumber(value: currentRow)) ?? "\(currentRow)"
        let totalStr = formatter.string(from: NSNumber(value: totalRows)) ?? "\(totalRows)"
        return "Exporting \(currentStr) of \(totalStr)..."
    }

    func cancel() {
        isCancelled = true
    }

    func reset() {
        currentRow = 0
        totalRows = 0
        isCancelled = false
        isComplete = false
    }

    func update(current: Int, total: Int) {
        currentRow = current
        totalRows = total
    }

    func markComplete() {
        isComplete = true
        currentRow = totalRows
    }
}

// MARK: - Export Settings

/// User preferences for export behavior. Persisted to UserDefaults.
struct ExportSettings: Codable {
    var timestampFormat: ExportTimestampFormat = .iso8601Full
    var csvOptions: CSVExportOptions = CSVExportOptions()
    var jsonOptions: JSONExportOptions = JSONExportOptions()
    
    /// Per-scope field selections (persisted separately for flexibility)
    var fieldSelections: [String: ExportFieldSelection] = [:]
    
    private static let key = "com.timeprint.exportSettings"

    static func load() -> ExportSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(ExportSettings.self, from: data) else {
            return ExportSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
    
    /// Get field selection for a specific scope, with defaults
    func fieldSelection(for scope: NavigationDestination) -> ExportFieldSelection {
        if let selection = fieldSelections[scope.rawValue] {
            return selection
        }
        // Return default (all fields selected)
        return ExportFieldSelection.defaultSelection(for: availableFields(for: scope))
    }
    
    /// Update field selection for a specific scope
    mutating func setFieldSelection(_ selection: ExportFieldSelection, for scope: NavigationDestination) {
        fieldSelections[scope.rawValue] = selection
    }
    
    /// Get available fields for a given scope
    func availableFields(for scope: NavigationDestination) -> [ExportField] {
        switch scope {
        case .rawSessions:
            return ExportField.rawSessionFields
        case .appsCategories:
            return ExportField.appFields + ExportField.categoryFields
        case .trends:
            return ExportField.trendFields
        case .sessions:
            return ExportField.sessionBucketFields
        case .heatmap:
            return ExportField.heatmapFields
        case .overview:
            return ExportField.overviewFields + ExportField.trendFields
        case .calendar:
            return ExportField.heatmapFields
        case .webHistory, .exports, .settings:
            return []
        }
    }
}

// MARK: - Export Presets

/// The type of date range to use in a preset
enum PresetDateRangeType: String, Codable, CaseIterable, Identifiable {
    case relative
    case absolute
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .relative: return "Relative"
        case .absolute: return "Fixed Dates"
        }
    }
}

/// Relative date range options
enum RelativeDateRange: String, Codable, CaseIterable, Identifiable {
    case today
    case yesterday
    case last7Days
    case last30Days
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisYear
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .thisWeek: return "This Week"
        case .lastWeek: return "Last Week"
        case .thisMonth: return "This Month"
        case .lastMonth: return "Last Month"
        case .thisYear: return "This Year"
        }
    }
    
    func dateRange(from date: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = date
        
        switch self {
        case .today:
            return (calendar.startOfDay(for: now), now)
        case .yesterday:
            let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
            return (calendar.startOfDay(for: yesterday), calendar.startOfDay(for: now))
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -7, to: now)!
            return (calendar.startOfDay(for: start), now)
        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -30, to: now)!
            return (calendar.startOfDay(for: start), now)
        case .thisWeek:
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)!
            return (weekInterval.start, now)
        case .lastWeek:
            let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: now)!
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: lastWeek)!
            return (weekInterval.start, weekInterval.end)
        case .thisMonth:
            let monthInterval = calendar.dateInterval(of: .month, for: now)!
            return (monthInterval.start, now)
        case .lastMonth:
            let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!
            let monthInterval = calendar.dateInterval(of: .month, for: lastMonth)!
            return (monthInterval.start, monthInterval.end)
        case .thisYear:
            let yearInterval = calendar.dateInterval(of: .year, for: now)!
            return (yearInterval.start, now)
        }
    }
}

/// A saved export configuration that can be reused
struct ExportPreset: Identifiable, Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    
    // Export configuration
    var format: ExportFormat
    var sections: ExportSectionSelection
    var settings: ExportSettings
    
    // Date range configuration
    var dateRangeType: PresetDateRangeType
    var relativeDateRange: RelativeDateRange?
    var absoluteStartDate: Date?
    var absoluteEndDate: Date?
    
    // Metadata
    var isBuiltIn: Bool
    var description: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        format: ExportFormat = .csv,
        sections: ExportSectionSelection = .allExceptRaw,
        settings: ExportSettings = ExportSettings(),
        dateRangeType: PresetDateRangeType = .relative,
        relativeDateRange: RelativeDateRange? = .last7Days,
        absoluteStartDate: Date? = nil,
        absoluteEndDate: Date? = nil,
        isBuiltIn: Bool = false,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.format = format
        self.sections = sections
        self.settings = settings
        self.dateRangeType = dateRangeType
        self.relativeDateRange = relativeDateRange
        self.absoluteStartDate = absoluteStartDate
        self.absoluteEndDate = absoluteEndDate
        self.isBuiltIn = isBuiltIn
        self.description = description
    }
    
    /// Get the resolved date range for this preset
    func resolvedDateRange() -> (start: Date, end: Date) {
        switch dateRangeType {
        case .relative:
            if let relative = relativeDateRange {
                return relative.dateRange()
            }
            return RelativeDateRange.last7Days.dateRange()
        case .absolute:
            let start = absoluteStartDate ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!
            let end = absoluteEndDate ?? Date()
            return (start, end)
        }
    }
    
    // Built-in presets
    static let fullDataDump = ExportPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Full Data Dump",
        format: .json,
        sections: .full,
        dateRangeType: .relative,
        relativeDateRange: .last30Days,
        isBuiltIn: true,
        description: "All sections with all data in JSON format"
    )
    
    static let weeklySummary = ExportPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Weekly Summary",
        format: .pdf,
        sections: .quickSummary,
        dateRangeType: .relative,
        relativeDateRange: .thisWeek,
        isBuiltIn: true,
        description: "Summary, top apps, and trends for this week"
    )
    
    static let rawSessionsExport = ExportPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Raw Sessions",
        format: .csv,
        sections: ExportSectionSelection(sections: [.rawSessions]),
        dateRangeType: .relative,
        relativeDateRange: .last7Days,
        isBuiltIn: true,
        description: "Individual session records in CSV format"
    )
    
    static let analyticsReport = ExportPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Analytics Report",
        format: .json,
        sections: .analyticsOnly,
        dateRangeType: .relative,
        relativeDateRange: .last30Days,
        isBuiltIn: true,
        description: "Context switches, transitions, and patterns"
    )
    
    static let builtInPresets: [ExportPreset] = [
        .fullDataDump,
        .weeklySummary,
        .rawSessionsExport,
        .analyticsReport
    ]
}

/// Manages preset storage and retrieval
@MainActor
@Observable
final class ExportPresetStore {
    private(set) var presets: [ExportPreset] = []
    private let storageURL: URL
    
    init() {
        // Get Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let timeprintDir = appSupport.appendingPathComponent("Timeprint", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: timeprintDir, withIntermediateDirectories: true)
        
        storageURL = timeprintDir.appendingPathComponent("export-presets.json")
        
        loadPresets()
    }
    
    /// All presets including built-ins
    var allPresets: [ExportPreset] {
        ExportPreset.builtInPresets + presets
    }
    
    /// User-created presets only
    var userPresets: [ExportPreset] {
        presets
    }
    
    func addPreset(_ preset: ExportPreset) {
        var newPreset = preset
        newPreset.modifiedAt = Date()
        presets.append(newPreset)
        savePresets()
    }
    
    func updatePreset(_ preset: ExportPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        updated.modifiedAt = Date()
        presets[index] = updated
        savePresets()
    }
    
    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        savePresets()
    }
    
    func duplicatePreset(_ preset: ExportPreset) -> ExportPreset {
        var duplicate = preset
        duplicate.id = UUID()
        duplicate.name = "\(preset.name) Copy"
        duplicate.isBuiltIn = false
        duplicate.createdAt = Date()
        duplicate.modifiedAt = Date()
        
        presets.append(duplicate)
        savePresets()
        
        return duplicate
    }
    
    private func loadPresets() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: storageURL)
            presets = try JSONDecoder().decode([ExportPreset].self, from: data)
        } catch {
            print("Failed to load presets: \(error)")
        }
    }
    
    private func savePresets() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save presets: \(error)")
        }
    }
}

// MARK: - Export Schedules

/// How often a scheduled export runs
enum ScheduleFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }
}

/// A scheduled export configuration
struct ExportSchedule: Identifiable, Codable {
    var id: UUID
    var presetId: UUID
    var frequency: ScheduleFrequency
    var hour: Int  // 0-23
    var minute: Int  // 0-59
    var dayOfWeek: Int?  // 1-7 for weekly (1=Sun)
    var dayOfMonth: Int?  // 1-31 for monthly
    var outputPath: String  // Path to output directory
    var isEnabled: Bool
    var lastRunAt: Date?
    var lastRunSuccess: Bool?
    var lastRunError: String?
    
    init(
        id: UUID = UUID(),
        presetId: UUID,
        frequency: ScheduleFrequency = .daily,
        hour: Int = 8,
        minute: Int = 0,
        dayOfWeek: Int? = nil,
        dayOfMonth: Int? = nil,
        outputPath: String = "",
        isEnabled: Bool = true
    ) {
        self.id = id
        self.presetId = presetId
        self.frequency = frequency
        self.hour = hour
        self.minute = minute
        self.dayOfWeek = dayOfWeek
        self.dayOfMonth = dayOfMonth
        self.outputPath = outputPath.isEmpty ? Self.defaultOutputPath : outputPath
        self.isEnabled = isEnabled
    }
    
    static var defaultOutputPath: String {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        return downloads.appendingPathComponent("Timeprint Exports", isDirectory: true).path
    }
    
    /// Human-readable schedule description
    var scheduleDescription: String {
        let timeStr = String(format: "%d:%02d", hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour), minute)
        let ampm = hour >= 12 ? "PM" : "AM"
        
        switch frequency {
        case .daily:
            return "Daily at \(timeStr) \(ampm)"
        case .weekly:
            let days = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
            let day = dayOfWeek.flatMap { $0 >= 1 && $0 <= 7 ? days[$0] : nil } ?? "Sunday"
            return "Every \(day) at \(timeStr) \(ampm)"
        case .monthly:
            let ordinal = dayOfMonth.map { "\($0)\(Self.ordinalSuffix($0))" } ?? "1st"
            return "Monthly on the \(ordinal) at \(timeStr) \(ampm)"
        }
    }
    
    private static func ordinalSuffix(_ n: Int) -> String {
        let ones = n % 10
        let tens = (n / 10) % 10
        if tens == 1 { return "th" }
        switch ones {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
    
    /// Calculate next run date from the current date
    func nextRunDate(from date: Date = Date()) -> Date? {
        let calendar = Calendar.current
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        
        switch frequency {
        case .daily:
            // Next occurrence of this time
            if let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date),
               today > date {
                return today
            }
            return calendar.date(byAdding: .day, value: 1, to: calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!)
            
        case .weekly:
            components.weekday = dayOfWeek ?? 1
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
            
        case .monthly:
            components.day = dayOfMonth ?? 1
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime)
        }
    }
}

/// Manages scheduled exports
@MainActor
@Observable
final class ExportScheduleStore {
    private(set) var schedules: [ExportSchedule] = []
    private let storageURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let timeprintDir = appSupport.appendingPathComponent("Timeprint", isDirectory: true)
        try? FileManager.default.createDirectory(at: timeprintDir, withIntermediateDirectories: true)
        storageURL = timeprintDir.appendingPathComponent("export-schedules.json")
        loadSchedules()
    }
    
    var enabledSchedules: [ExportSchedule] {
        schedules.filter(\.isEnabled)
    }
    
    func addSchedule(_ schedule: ExportSchedule) {
        schedules.append(schedule)
        saveSchedules()
    }
    
    func updateSchedule(_ schedule: ExportSchedule) {
        guard let index = schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        schedules[index] = schedule
        saveSchedules()
    }
    
    func deleteSchedule(id: UUID) {
        schedules.removeAll { $0.id == id }
        saveSchedules()
    }
    
    func toggleSchedule(id: UUID) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].isEnabled.toggle()
        saveSchedules()
    }
    
    func recordRun(id: UUID, success: Bool, error: String? = nil) {
        guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
        schedules[index].lastRunAt = Date()
        schedules[index].lastRunSuccess = success
        schedules[index].lastRunError = error
        saveSchedules()
    }
    
    private func loadSchedules() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            schedules = try JSONDecoder().decode([ExportSchedule].self, from: data)
        } catch {
            print("Failed to load schedules: \(error)")
        }
    }
    
    private func saveSchedules() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(schedules)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save schedules: \(error)")
        }
    }
}
