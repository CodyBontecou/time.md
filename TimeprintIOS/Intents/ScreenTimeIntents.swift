import AppIntents
import SwiftUI

// MARK: - Get Screen Time Intent

/// Siri Shortcut: "How much screen time do I have?"
struct GetScreenTimeIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Screen Time"
    static var description = IntentDescription("Check your screen time for today or this week")
    
    @Parameter(title: "Time Period", default: .today)
    var period: ScreenTimePeriod
    
    static var parameterSummary: some ParameterSummary {
        Summary("Get screen time for \(\.$period)")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let data = loadScreenTimeData()
        
        let seconds: Double
        let periodText: String
        
        switch period {
        case .today:
            seconds = data.todayTotal
            periodText = "today"
        case .thisWeek:
            seconds = data.weekTotal
            periodText = "this week"
        }
        
        let formatted = formatDuration(seconds)
        let dialog = "You've had \(formatted) of screen time \(periodText)."
        
        return .result(
            dialog: IntentDialog(stringLiteral: dialog),
            view: ScreenTimeSnippetView(seconds: seconds, period: periodText, deviceCount: data.deviceCount)
        )
    }
    
    private func loadScreenTimeData() -> ScreenTimeData {
        // Try iCloud container
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.codybontecou.Timeprint") {
            let fileURL = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("timeprint-sync.json")
            
            if let data = try? Data(contentsOf: fileURL),
               let payload = try? JSONDecoder().decode(SyncPayloadLite.self, from: data) {
                return calculateTotals(from: payload)
            }
        }
        
        return ScreenTimeData(todayTotal: 0, weekTotal: 0, deviceCount: 0)
    }
    
    private func calculateTotals(from payload: SyncPayloadLite) -> ScreenTimeData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        var todayTotal: Double = 0
        var weekTotal: Double = 0
        
        for device in payload.devices {
            for summary in device.dailySummaries {
                let summaryDay = calendar.startOfDay(for: summary.date)
                
                if summaryDay == today {
                    todayTotal += summary.totalSeconds
                }
                if summaryDay >= weekAgo && summaryDay <= today {
                    weekTotal += summary.totalSeconds
                }
            }
        }
        
        return ScreenTimeData(
            todayTotal: todayTotal,
            weekTotal: weekTotal,
            deviceCount: payload.devices.count
        )
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s") and \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s")"
    }
}

// MARK: - Period Enum

enum ScreenTimePeriod: String, AppEnum {
    case today
    case thisWeek
    
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time Period")
    
    static var caseDisplayRepresentations: [ScreenTimePeriod: DisplayRepresentation] = [
        .today: "Today",
        .thisWeek: "This Week"
    ]
}

// MARK: - Data Structures

struct ScreenTimeData {
    let todayTotal: Double
    let weekTotal: Double
    let deviceCount: Int
}

/// Lightweight sync payload for intent parsing
struct SyncPayloadLite: Codable {
    let devices: [DeviceLite]
}

struct DeviceLite: Codable {
    let dailySummaries: [DailySummaryLite]
}

struct DailySummaryLite: Codable {
    let date: Date
    let totalSeconds: Double
}

// MARK: - Snippet View

struct ScreenTimeSnippetView: View {
    let seconds: Double
    let period: String
    let deviceCount: Int
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                Text("Screen Time")
                    .fontWeight(.semibold)
            }
            
            Text(formatCompact(seconds))
                .font(.system(size: 36, weight: .bold, design: .rounded))
            
            Text(period.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if deviceCount > 0 {
                Text("\(deviceCount) device\(deviceCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }
    
    private func formatCompact(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - App Shortcuts Provider

struct TimeprintShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetScreenTimeIntent(),
            phrases: [
                "How much screen time do I have in \(.applicationName)",
                "Check my screen time with \(.applicationName)",
                "What's my screen time in \(.applicationName)",
                "\(.applicationName) screen time",
                "Show screen time from \(.applicationName)"
            ],
            shortTitle: "Get Screen Time",
            systemImageName: "clock.fill"
        )
    }
}

// MARK: - Preview

#Preview {
    ScreenTimeSnippetView(seconds: 7260, period: "today", deviceCount: 2)
}
