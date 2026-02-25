import Foundation

// MARK: - Export Filter Preset

/// A saved export filter configuration for granular data exports.
/// Users can define specific apps, time ranges, and weekdays to export.
struct ExportFilterPreset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    
    // App filtering
    var selectedApps: Set<String>
    var appFilterMode: AppFilterMode
    
    // Time-of-day filtering
    var timeRanges: [TimeRangeConfig]
    
    // Weekday filtering
    var selectedWeekdays: Set<Int>  // 0=Sun, 1=Mon, ..., 6=Sat (matches strftime %w)
    
    // Duration filtering
    var minDurationSeconds: Double?
    var maxDurationSeconds: Double?
    
    // Quick description
    var description: String?
    
    init(
        id: UUID = UUID(),
        name: String,
        selectedApps: Set<String> = [],
        appFilterMode: AppFilterMode = .include,
        timeRanges: [TimeRangeConfig] = [],
        selectedWeekdays: Set<Int> = Set(0...6),
        minDurationSeconds: Double? = nil,
        maxDurationSeconds: Double? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.selectedApps = selectedApps
        self.appFilterMode = appFilterMode
        self.timeRanges = timeRanges
        self.selectedWeekdays = selectedWeekdays
        self.minDurationSeconds = minDurationSeconds
        self.maxDurationSeconds = maxDurationSeconds
        self.description = description
    }
    
    /// Whether this preset filters anything (has any restrictions)
    var hasFilters: Bool {
        !selectedApps.isEmpty ||
        !timeRanges.isEmpty ||
        selectedWeekdays.count < 7 ||
        minDurationSeconds != nil ||
        maxDurationSeconds != nil
    }
    
    /// Human-readable summary of the preset's filters
    var filterSummary: String {
        var parts: [String] = []
        
        if !selectedApps.isEmpty {
            let appCount = selectedApps.count
            let modeLabel = appFilterMode == .include ? "only" : "excluding"
            parts.append("\(appCount) app\(appCount == 1 ? "" : "s") \(modeLabel)")
        }
        
        if !timeRanges.isEmpty {
            if timeRanges.count == 1 {
                parts.append(timeRanges[0].displayName)
            } else {
                parts.append("\(timeRanges.count) time ranges")
            }
        }
        
        if selectedWeekdays.count < 7 {
            let dayNames = selectedWeekdays.sorted().compactMap { weekdayShortName($0) }
            if selectedWeekdays == Set([1, 2, 3, 4, 5]) {
                parts.append("Weekdays")
            } else if selectedWeekdays == Set([0, 6]) {
                parts.append("Weekends")
            } else {
                parts.append(dayNames.joined(separator: ", "))
            }
        }
        
        if let min = minDurationSeconds {
            parts.append("≥ \(formatDuration(min))")
        }
        
        if let max = maxDurationSeconds {
            parts.append("≤ \(formatDuration(max))")
        }
        
        return parts.isEmpty ? "No filters" : parts.joined(separator: " • ")
    }
    
    private func weekdayShortName(_ day: Int) -> String? {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard day >= 0 && day <= 6 else { return nil }
        return names[day]
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds >= 3600 {
            return String(format: "%.1fh", seconds / 3600)
        } else if seconds >= 60 {
            return String(format: "%.0fm", seconds / 60)
        } else {
            return String(format: "%.0fs", seconds)
        }
    }
    
    /// Apply this preset to a FilterSnapshot
    func apply(to filters: inout FilterSnapshot) {
        // Apply app filter
        if appFilterMode == .include && !selectedApps.isEmpty {
            filters.selectedApps = selectedApps
        }
        // Note: exclude mode is handled at query time
        
        // Apply time ranges
        filters.timeOfDayRanges = timeRanges.map { config in
            TimeOfDayRange(startHour: config.startHour, endHour: config.endHour)
        }
        
        // Apply weekday filter
        if selectedWeekdays.count < 7 {
            filters.weekdayFilter = selectedWeekdays
        }
        
        // Apply duration filters
        filters.minDurationSeconds = minDurationSeconds
        filters.maxDurationSeconds = maxDurationSeconds
    }
    
    /// Get filtered apps based on mode
    func filteredApps(from allApps: Set<String>) -> Set<String> {
        if selectedApps.isEmpty {
            return allApps
        }
        
        switch appFilterMode {
        case .include:
            return selectedApps
        case .exclude:
            return allApps.subtracting(selectedApps)
        }
    }
}

// MARK: - App Filter Mode

enum AppFilterMode: String, Codable, CaseIterable, Identifiable {
    case include
    case exclude
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .include: return "Include only"
        case .exclude: return "Exclude"
        }
    }
    
    var description: String {
        switch self {
        case .include: return "Export only selected apps"
        case .exclude: return "Export all apps except selected"
        }
    }
}

// MARK: - Time Range Config

/// A time range configuration that can be persisted
struct TimeRangeConfig: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var startHour: Int  // 0-23
    var endHour: Int    // 0-23
    
    init(id: UUID = UUID(), name: String = "", startHour: Int = 9, endHour: Int = 17) {
        self.id = id
        self.name = name
        self.startHour = max(0, min(23, startHour))
        self.endHour = max(0, min(23, endHour))
    }
    
    var displayName: String {
        if !name.isEmpty { return name }
        return "\(formatHour(startHour)) – \(formatHour(endHour))"
    }
    
    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
    }
    
    func contains(hour: Int) -> Bool {
        if startHour <= endHour {
            return hour >= startHour && hour < endHour
        } else {
            // Wraps around midnight (e.g., 10 PM - 6 AM)
            return hour >= startHour || hour < endHour
        }
    }
    
    // Common presets
    static let workHours = TimeRangeConfig(name: "Work Hours", startHour: 9, endHour: 17)
    static let earlyMorning = TimeRangeConfig(name: "Early Morning", startHour: 5, endHour: 9)
    static let evening = TimeRangeConfig(name: "Evening", startHour: 17, endHour: 22)
    static let lateNight = TimeRangeConfig(name: "Late Night", startHour: 22, endHour: 5)
}

// MARK: - Weekday Helpers

struct WeekdaySelection {
    static let all: Set<Int> = Set(0...6)
    static let weekdays: Set<Int> = Set([1, 2, 3, 4, 5])  // Mon-Fri (0=Sun, 1=Mon...)
    static let weekends: Set<Int> = Set([0, 6])  // Sun, Sat
    
    static func name(for day: Int) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard day >= 0 && day <= 6 else { return "" }
        return names[day]
    }
    
    static func shortName(for day: Int) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard day >= 0 && day <= 6 else { return "" }
        return names[day]
    }
    
    static func singleLetter(for day: Int) -> String {
        let names = ["S", "M", "T", "W", "T", "F", "S"]
        guard day >= 0 && day <= 6 else { return "" }
        return names[day]
    }
}

// MARK: - Preset Store

/// Manages persistence of export filter presets
@MainActor
@Observable
final class ExportFilterPresetStore {
    private(set) var presets: [ExportFilterPreset] = []
    private let storageURL: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let timeprintDir = appSupport.appendingPathComponent("Timeprint", isDirectory: true)
        try? FileManager.default.createDirectory(at: timeprintDir, withIntermediateDirectories: true)
        storageURL = timeprintDir.appendingPathComponent("export-filter-presets.json")
        loadPresets()
    }
    
    /// All presets including built-ins
    var allPresets: [ExportFilterPreset] {
        Self.builtInPresets + presets
    }
    
    /// User-created presets only
    var userPresets: [ExportFilterPreset] {
        presets
    }
    
    func addPreset(_ preset: ExportFilterPreset) {
        var newPreset = preset
        newPreset.modifiedAt = Date()
        presets.append(newPreset)
        savePresets()
    }
    
    func updatePreset(_ preset: ExportFilterPreset) {
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
    
    func duplicatePreset(_ preset: ExportFilterPreset) -> ExportFilterPreset {
        var duplicate = preset
        duplicate.id = UUID()
        duplicate.name = "\(preset.name) Copy"
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
            presets = try JSONDecoder().decode([ExportFilterPreset].self, from: data)
        } catch {
            print("Failed to load export filter presets: \(error)")
        }
    }
    
    private func savePresets() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(presets)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("Failed to save export filter presets: \(error)")
        }
    }
    
    // Built-in presets
    static let builtInPresets: [ExportFilterPreset] = [
        ExportFilterPreset(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Work Hours (9–5 Weekdays)",
            timeRanges: [TimeRangeConfig.workHours],
            selectedWeekdays: WeekdaySelection.weekdays,
            description: "Export only data from 9 AM to 5 PM, Monday through Friday"
        ),
        ExportFilterPreset(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "After Hours",
            timeRanges: [
                TimeRangeConfig(name: "After Hours", startHour: 17, endHour: 9)  // 5PM to 9AM (wraps around midnight)
            ],
            description: "Export data outside of typical work hours (5 PM – 9 AM)"
        ),
        ExportFilterPreset(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Weekends Only",
            selectedWeekdays: WeekdaySelection.weekends,
            description: "Export only Saturday and Sunday data"
        ),
        ExportFilterPreset(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Deep Work Sessions",
            minDurationSeconds: 30 * 60,  // 30 minutes minimum
            description: "Export only sessions lasting 30 minutes or longer"
        ),
        ExportFilterPreset(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Quick Tasks",
            maxDurationSeconds: 5 * 60,  // 5 minutes max
            description: "Export only brief sessions under 5 minutes"
        )
    ]
}
