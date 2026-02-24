import Foundation
import SwiftUI

/// Service for exporting and sharing screen time data from iOS
final class ExportService {
    static let shared = ExportService()
    
    private init() {}
    
    // MARK: - Export Formats
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case text = "Plain Text"
        
        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .json: return "json"
            case .text: return "txt"
            }
        }
        
        var mimeType: String {
            switch self {
            case .csv: return "text/csv"
            case .json: return "application/json"
            case .text: return "text/plain"
            }
        }
    }
    
    // MARK: - Export Data
    
    /// Export synced data to a file
    func exportData(from payload: SyncPayload, format: ExportFormat) -> URL? {
        let content: String
        
        switch format {
        case .csv:
            content = generateCSV(from: payload)
        case .json:
            content = generateJSON(from: payload)
        case .text:
            content = generateText(from: payload)
        }
        
        // Write to temporary file
        let fileName = "timeprint-export-\(dateString()).\(format.fileExtension)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        
        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            print("[Export] Failed to write file: \(error)")
            return nil
        }
    }
    
    // MARK: - Generate Shareable Summary
    
    /// Generate a shareable text summary of today's screen time
    func generateShareableSummary(from payload: SyncPayload) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var todayTotal: Double = 0
        var appTotals: [String: Double] = [:]
        
        for device in payload.devices {
            // Get today's daily summary total
            for summary in device.dailySummaries {
                let summaryDay = calendar.startOfDay(for: summary.date)
                if summaryDay == today {
                    todayTotal += summary.totalSeconds
                }
            }
            
            // Get app usage for today
            for app in device.appUsage {
                let appDay = calendar.startOfDay(for: app.date)
                if appDay == today {
                    appTotals[app.displayName, default: 0] += app.totalSeconds
                }
            }
        }
        
        let topApps = appTotals
            .sorted { $0.value > $1.value }
            .prefix(5)
        
        var lines: [String] = []
        lines.append("📱 My Screen Time Today")
        lines.append("")
        lines.append("Total: \(formatDuration(todayTotal))")
        lines.append("")
        
        if !topApps.isEmpty {
            lines.append("Top Apps:")
            for (app, seconds) in topApps {
                lines.append("• \(app): \(formatDuration(seconds))")
            }
        }
        
        lines.append("")
        lines.append("Tracked with Timeprint")
        
        return lines.joined(separator: "\n")
    }
    
    /// Generate a weekly summary for sharing
    func generateWeeklySummary(from payload: SyncPayload) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today)!
        
        var dailyTotals: [Date: Double] = [:]
        var weekTotal: Double = 0
        
        for device in payload.devices {
            for summary in device.dailySummaries {
                let summaryDay = calendar.startOfDay(for: summary.date)
                if summaryDay >= weekAgo && summaryDay <= today {
                    dailyTotals[summaryDay, default: 0] += summary.totalSeconds
                    weekTotal += summary.totalSeconds
                }
            }
        }
        
        let dailyAverage = dailyTotals.isEmpty ? 0 : weekTotal / Double(dailyTotals.count)
        
        var lines: [String] = []
        lines.append("📊 My Weekly Screen Time")
        lines.append("")
        lines.append("Total: \(formatDuration(weekTotal))")
        lines.append("Daily Average: \(formatDuration(dailyAverage))")
        lines.append("Days Tracked: \(dailyTotals.count)")
        lines.append("")
        lines.append("Tracked with Timeprint")
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - CSV Generation
    
    private func generateCSV(from payload: SyncPayload) -> String {
        var lines: [String] = []
        
        // Header
        lines.append("Date,Device,App,Category,Duration (seconds),Duration (formatted)")
        
        for device in payload.devices {
            let deviceName = device.device.name
            
            // Export app usage data
            for app in device.appUsage.sorted(by: { $0.date > $1.date }) {
                let dateStr = ISO8601DateFormatter().string(from: app.date)
                
                let row = [
                    dateStr,
                    escapeCSV(deviceName),
                    escapeCSV(app.displayName),
                    escapeCSV(app.category ?? "Unknown"),
                    String(format: "%.0f", app.totalSeconds),
                    formatDuration(app.totalSeconds)
                ].joined(separator: ",")
                
                lines.append(row)
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
    
    // MARK: - JSON Generation
    
    private func generateJSON(from payload: SyncPayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{\"error\": \"Failed to encode data\"}"
        }
    }
    
    // MARK: - Plain Text Generation
    
    private func generateText(from payload: SyncPayload) -> String {
        var lines: [String] = []
        
        lines.append("TIMEPRINT EXPORT")
        lines.append("Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))")
        lines.append(String(repeating: "=", count: 50))
        lines.append("")
        
        for device in payload.devices {
            lines.append("DEVICE: \(device.device.name)")
            lines.append(String(repeating: "-", count: 40))
            
            for summary in device.dailySummaries.sorted(by: { $0.date > $1.date }) {
                let dateStr = DateFormatter.localizedString(from: summary.date, dateStyle: .medium, timeStyle: .none)
                lines.append("")
                lines.append("\(dateStr) - Total: \(formatDuration(summary.totalSeconds))")
                
                // Get apps for this date
                let calendar = Calendar.current
                let summaryDay = calendar.startOfDay(for: summary.date)
                let dayApps = device.appUsage
                    .filter { calendar.startOfDay(for: $0.date) == summaryDay }
                    .sorted { $0.totalSeconds > $1.totalSeconds }
                    .prefix(10)
                
                for app in dayApps {
                    lines.append("  • \(app.displayName): \(formatDuration(app.totalSeconds))")
                }
            }
            
            lines.append("")
        }
        
        return lines.joined(separator: "\n")
    }
    
    // MARK: - Helpers
    
    private func dateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

// MARK: - Share Activity

/// UIActivityViewController wrapper for SwiftUI
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
