import WidgetKit
import SwiftUI

/// time.md Home Screen Widget
/// Displays screen time data synced from Mac via iCloud
@main
struct TimeMdWidgetBundle: WidgetBundle {
    var body: some Widget {
        TimeMdWidget()
    }
}

// MARK: - Widget Definition

struct TimeMdWidget: Widget {
    let kind: String = "TimeMdWidget"
    
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TimeMdTimelineProvider()) { entry in
            TimeMdWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Screen Time")
        .description("See your screen time at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Timeline Entry

struct TimeMdEntry: TimelineEntry {
    let date: Date
    let todayTotal: Double
    let weekTotal: Double
    let deviceCount: Int
    let trend: [Double] // Last 7 days
    let isPlaceholder: Bool
    
    static var placeholder: TimeMdEntry {
        TimeMdEntry(
            date: Date(),
            todayTotal: 7200,
            weekTotal: 25200,
            deviceCount: 2,
            trend: [3600, 4200, 3000, 5400, 4800, 3600, 7200],
            isPlaceholder: true
        )
    }
    
    static var empty: TimeMdEntry {
        TimeMdEntry(
            date: Date(),
            todayTotal: 0,
            weekTotal: 0,
            deviceCount: 0,
            trend: [],
            isPlaceholder: false
        )
    }
}

// MARK: - Timeline Provider

struct TimeMdTimelineProvider: TimelineProvider {
    
    func placeholder(in context: Context) -> TimeMdEntry {
        .placeholder
    }
    
    func getSnapshot(in context: Context, completion: @escaping (TimeMdEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
        } else {
            let entry = loadEntry()
            completion(entry)
        }
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<TimeMdEntry>) -> Void) {
        let entry = loadEntry()
        
        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        
        completion(timeline)
    }
    
    // MARK: - Data Loading
    
    private func loadEntry() -> TimeMdEntry {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        var todayTotal: Double = 0
        var weekTotal: Double = 0
        var deviceCount = 0
        var dailyTotals: [Date: Double] = [:]
        
        // Load synced data from iCloud
        if let payload = loadSyncPayload() {
            let todayTotals = payload.allDeviceDailyTotals(from: today, to: today)
            todayTotal += todayTotals[today] ?? 0
            
            let weekTotals = payload.allDeviceDailyTotals(from: weekAgo, to: today)
            weekTotal += weekTotals.values.reduce(0, +)
            
            deviceCount = payload.devices.count
            dailyTotals = weekTotals
        }
        
        // Also load local iPhone data from App Group (if available)
        if let localData = loadLocalUsageData() {
            let localTodayUsage = localData.usage(for: today)
            let localWeekUsage = localData.usage(from: weekAgo, to: today)
            
            if let localToday = localTodayUsage {
                todayTotal += localToday.totalSeconds
            }
            
            for usage in localWeekUsage {
                weekTotal += usage.totalSeconds
                let day = usage.date
                dailyTotals[day, default: 0] += usage.totalSeconds
            }
            
            // Count local iPhone as a device if there's data
            if !localWeekUsage.isEmpty && deviceCount == 0 {
                deviceCount = 1
            }
        }
        
        // Build trend (last 7 days)
        var trend: [Double] = []
        for dayOffset in (0..<7).reversed() {
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: today)!
            let seconds = dailyTotals[date] ?? 0
            trend.append(seconds)
        }
        
        if todayTotal == 0 && weekTotal == 0 && deviceCount == 0 {
            return .empty
        }
        
        return TimeMdEntry(
            date: Date(),
            todayTotal: todayTotal,
            weekTotal: weekTotal,
            deviceCount: max(deviceCount, 1),
            trend: trend,
            isPlaceholder: false
        )
    }
    
    private func loadSyncPayload() -> SyncPayload? {
        // Try iCloud container first
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.codybontecou.Timeprint") {
            let fileURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(SyncPayload.filename)
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return try? SyncPayload.load(from: fileURL)
            }
        }
        
        // Fallback to app group shared container (for sync file)
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.codybontecou.Timeprint") {
            let fileURL = groupURL.appendingPathComponent(SyncPayload.filename)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return try? SyncPayload.load(from: fileURL)
            }
        }
        
        return nil
    }
    
    private func loadLocalUsageData() -> StoredUsageData? {
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.codybontecou.Timeprint") else {
            return nil
        }
        
        let fileURL = groupURL.appendingPathComponent("timeprint-usage.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(StoredUsageData.self, from: data)
        } catch {
            return nil
        }
    }
}

// MARK: - Widget Views

struct TimeMdWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: TimeMdEntry
    
    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: TimeMdEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("TODAY")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            
            Text(formatDuration(entry.todayTotal))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            
            Spacer()
            
            if entry.deviceCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.caption2)
                    Text("\(entry.deviceCount) devices")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            } else if !entry.isPlaceholder {
                Text("Sync from Mac")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: TimeMdEntry
    
    var body: some View {
        HStack(spacing: 16) {
            // Left side - today's total
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                    Text("TODAY")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                
                Text(formatDuration(entry.todayTotal))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(entry.weekTotal))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Right side - mini trend chart
            if !entry.trend.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("7-DAY TREND")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    
                    MiniTrendChart(data: entry.trend)
                        .frame(height: 50)
                    
                    Spacer()
                    
                    if entry.deviceCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "macbook.and.iphone")
                                .font(.caption2)
                            Text("\(entry.deviceCount) devices")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

// MARK: - Mini Trend Chart

struct MiniTrendChart: View {
    let data: [Double]
    
    private var maxValue: Double {
        data.max() ?? 1
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                    let height = maxValue > 0 ? (value / maxValue) * geometry.size.height : 0
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index == data.count - 1 ? Color.accentColor : Color.accentColor.opacity(0.5))
                        .frame(height: max(4, height))
                }
            }
        }
    }
}

// MARK: - Lock Screen Widgets

struct RectangularWidgetView: View {
    let entry: TimeMdEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Time")
                    .font(.headline)
                Text(formatDuration(entry.todayTotal))
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            Image(systemName: "clock.fill")
                .font(.title)
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

struct CircularWidgetView: View {
    let entry: TimeMdEntry
    
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "clock.fill")
                .font(.title3)
            Text(formatDurationShort(entry.todayTotal))
                .font(.headline)
                .fontWeight(.bold)
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }
}

// MARK: - Formatting Helpers

private func formatDuration(_ seconds: Double) -> String {
    let totalMinutes = Int(seconds / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    
    if hours > 0 {
        return "\(hours)h \(minutes)m"
    }
    return "\(minutes)m"
}

private func formatDurationShort(_ seconds: Double) -> String {
    let totalMinutes = Int(seconds / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    
    if hours > 0 {
        return "\(hours)h"
    }
    return "\(minutes)m"
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TimeMdWidget()
} timeline: {
    TimeMdEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    TimeMdWidget()
} timeline: {
    TimeMdEntry.placeholder
}

#Preview("Rectangular", as: .accessoryRectangular) {
    TimeMdWidget()
} timeline: {
    TimeMdEntry.placeholder
}

#Preview("Circular", as: .accessoryCircular) {
    TimeMdWidget()
} timeline: {
    TimeMdEntry.placeholder
}
