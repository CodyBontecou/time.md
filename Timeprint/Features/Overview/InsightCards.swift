import Charts
import SwiftUI

// MARK: - Today Delta Card

/// Shows screen time for the selected period with a delta indicator.
struct TodayDeltaCard: View {
    let todaySeconds: Double
    let deltaPercent: Double
    var periodLabel: String = "TODAY"
    var comparisonLabel: String = "vs yesterday"

    private var isUp: Bool { deltaPercent > 0 }
    private var isFlat: Bool { abs(deltaPercent) < 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                Text(periodLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            AnimatedDuration(todaySeconds)

            if isFlat {
                HStack(spacing: 4) {
                    Image(systemName: "equal")
                        .font(.system(size: 10, weight: .bold))
                    Text("Same as \(comparisonLabel.replacingOccurrences(of: "vs ", with: ""))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(BrutalTheme.textTertiary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.0f%% %@", abs(deltaPercent), comparisonLabel))
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isUp ? BrutalTheme.danger : .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(periodLabel) screen time: \(DurationFormatter.short(todaySeconds)), \(isFlat ? "same as previous period" : String(format: "%.0f percent %@ previous period", abs(deltaPercent), isUp ? "more than" : "less than"))")
    }
}

// MARK: - Sparkline Card

/// Compact trend sparkline for the selected period.
struct SparklineCard: View {
    let points: [SparklinePoint]
    let title: String
    var totalSeconds: Double? = nil  // Optional override for total display

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.teal)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            if points.isEmpty {
                Text("No data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .frame(height: 50)
            } else {
                Chart(points) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Time", point.totalSeconds)
                    )
                    .foregroundStyle(.teal.opacity(0.2).gradient)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Time", point.totalSeconds)
                    )
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 50)
                .sparklineDrawAnimation()
            }

            let displaySeconds = totalSeconds ?? points.last?.totalSeconds ?? 0
            if displaySeconds > 0 {
                Text(DurationFormatter.short(displaySeconds))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(DurationFormatter.short(totalSeconds ?? points.last?.totalSeconds ?? 0))")
    }
}

// MARK: - Hourly Trend Card

/// Detailed hourly usage chart for Day granularity - matches the Trends view style.
struct HourlyTrendCard: View {
    let hourlyPoints: [SparklinePoint]  // 24 points, one per hour
    var totalSeconds: Double? = nil
    
    @State private var hoveredDate: Date?
    
    private var hoveredPoint: SparklinePoint? {
        guard let hoveredDate else { return nil }
        return hourlyPoints.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
    }
    
    private func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.teal)
                Text("HOURLY USAGE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }
            
            if hourlyPoints.isEmpty {
                Text("No data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .frame(height: 80)
            } else {
                Chart {
                    ForEach(hourlyPoints) { point in
                        AreaMark(
                            x: .value("Hour", point.date),
                            y: .value("Seconds", point.totalSeconds)
                        )
                        .foregroundStyle(.teal.opacity(0.2).gradient)
                        .interpolationMethod(.catmullRom)
                        
                        LineMark(
                            x: .value("Hour", point.date),
                            y: .value("Seconds", point.totalSeconds)
                        )
                        .foregroundStyle(.teal)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                    
                    // Hover indicator
                    if let hoveredPoint {
                        RuleMark(x: .value("Hour", hoveredPoint.date))
                            .foregroundStyle(BrutalTheme.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        
                        PointMark(
                            x: .value("Hour", hoveredPoint.date),
                            y: .value("Seconds", hoveredPoint.totalSeconds)
                        )
                        .symbolSize(40)
                        .foregroundStyle(.teal)
                    }
                }
                .chartYScale(domain: 0...(hourlyPoints.map(\.totalSeconds).max() ?? 0) * 1.15)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                            .foregroundStyle(BrutalTheme.border)
                        AxisValueLabel {
                            if let seconds = value.as(Double.self) {
                                Text(DurationFormatter.short(seconds))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                            .foregroundStyle(BrutalTheme.border)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(hourLabel(date))
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case let .active(location):
                                    if let plotFrame = proxy.plotFrame {
                                        let plotRect = geometry[plotFrame]
                                        let relativeX = location.x - plotRect.origin.x
                                        if relativeX >= 0, relativeX <= plotRect.width,
                                           let date: Date = proxy.value(atX: relativeX) {
                                            hoveredDate = date
                                        } else {
                                            hoveredDate = nil
                                        }
                                    }
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                    }
                }
                .frame(height: 80)
                .animation(.easeInOut(duration: 0.3), value: hourlyPoints.map(\.totalSeconds))
            }
            
            // Bottom row: total + hovered point
            HStack {
                if let total = totalSeconds, total > 0 {
                    Text(DurationFormatter.short(total))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                }
                
                Spacer()
                
                if let hoveredPoint {
                    HStack(spacing: 4) {
                        Text(hourLabel(hoveredPoint.date))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                        Text(DurationFormatter.short(hoveredPoint.totalSeconds))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.teal)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: hoveredPoint?.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hourly usage: \(DurationFormatter.short(totalSeconds ?? 0)) total")
    }
}

// MARK: - Peak Hour Card

struct PeakHourCard: View {
    let hour: Int
    let seconds: Double

    private var hourLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return formatter.string(from: date).lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Text("PEAK HOUR")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            Text(hourLabel)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(BrutalTheme.textPrimary)

            AnimatedDuration(seconds, font: .system(size: 13, weight: .bold, design: .monospaced), color: BrutalTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Peak hour: \(hourLabel), \(DurationFormatter.short(seconds))")
    }
}

// MARK: - Apps Used Card

struct AppsUsedCard: View {
    let count: Int
    var contextLabel: String = "today"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.indigo)
                Text("APPS USED")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            AnimatedNumber(
                Double(count),
                font: .system(size: 28, weight: .heavy, design: .rounded)
            )

            Text(contextLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) apps used \(contextLabel)")
    }
}

// MARK: - Top App Spotlight

struct TopAppSpotlightCard: View {
    let appName: String
    let seconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.yellow)
                Text("TOP APP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            AppNameText(appName)
                .font(.system(size: 18, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)

            AnimatedDuration(seconds, font: .system(size: 13, weight: .bold, design: .monospaced), color: BrutalTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top app: \(appName), \(DurationFormatter.short(seconds))")
    }
}

// MARK: - Focus Streak Badge

struct FocusStreakCard: View {
    let streakDays: Int
    let focusBlocks: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.orange)
                Text("FOCUS STREAK")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                AnimatedNumber(Double(streakDays), font: .system(size: 28, weight: .heavy, design: .rounded))
                Text(streakDays == 1 ? "day" : "days")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
            }

            Text("\(focusBlocks) focus blocks")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(streakDays) day focus streak, \(focusBlocks) focus blocks")
    }
}

// MARK: - Longest Session Card

struct LongestSessionCard: View {
    let session: LongestSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.red)
                Text("LONGEST SESSION")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            if let session {
                AnimatedDuration(session.durationSeconds, font: .system(size: 22, weight: .heavy, design: .rounded))

                AppNameText(session.appName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .lineLimit(1)
            } else {
                Text("No sessions")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Longest session: \(session.map { "\(DurationFormatter.short($0.durationSeconds)) in \($0.appName)" } ?? "None")")
    }
}

// MARK: - Mini Heatmap Card

struct MiniHeatmapCard: View {
    let cells: [HeatmapCell]
    let maxSeconds: Double

    private let weekdays = 7
    private let hours = 24
    private let cellSize: CGFloat = 5
    private let cellSpacing: CGFloat = 1.5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.cyan)
                Text("ACTIVITY MAP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }

            Canvas { context, size in
                let totalW = CGFloat(hours) * (cellSize + cellSpacing)
                let totalH = CGFloat(weekdays) * (cellSize + cellSpacing)
                let offsetX = (size.width - totalW) / 2
                let offsetY = max(0, (size.height - totalH) / 2)

                for cell in cells {
                    let x = offsetX + CGFloat(cell.hour) * (cellSize + cellSpacing)
                    let y = offsetY + CGFloat(cell.weekday) * (cellSize + cellSpacing)
                    let rect = CGRect(x: x, y: y, width: cellSize, height: cellSize)
                    let intensity = maxSeconds > 0 ? min(cell.totalSeconds / maxSeconds, 1.0) : 0
                    let color = BrutalTheme.heatmapColor(intensity: intensity)
                    context.fill(
                        RoundedRectangle(cornerRadius: 1).path(in: rect),
                        with: .color(color)
                    )
                }
            }
            .frame(height: CGFloat(weekdays) * (cellSize + cellSpacing) + 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity heatmap: \(cells.count) cells")
    }
}

// MARK: - Device Breakdown Card

/// Shows screen time breakdown by device from sync payload
struct DeviceBreakdownCard: View {
    let devices: [DeviceSyncData]
    let selectedDate: Date
    
    private var todayDeviceBreakdown: [(device: DeviceInfo, seconds: Double)] {
        let calendar = Calendar.current
        let targetDay = calendar.startOfDay(for: selectedDate)
        
        return devices.compactMap { deviceData -> (DeviceInfo, Double)? in
            let dayTotal = deviceData.dailySummaries
                .filter { calendar.startOfDay(for: $0.date) == targetDay }
                .reduce(0) { $0 + $1.totalSeconds }
            
            guard dayTotal > 0 else { return nil }
            return (deviceData.device, dayTotal)
        }
        .sorted { $0.seconds > $1.seconds }
    }
    
    private var totalSeconds: Double {
        todayDeviceBreakdown.reduce(0) { $0 + $1.seconds }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "macbook.and.iphone")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.purple)
                Text("ALL DEVICES")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }
            
            if todayDeviceBreakdown.isEmpty {
                Text("No device data")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                // Device list
                VStack(spacing: 8) {
                    ForEach(todayDeviceBreakdown, id: \.device.id) { item in
                        DeviceRow(
                            device: item.device,
                            seconds: item.seconds,
                            percentage: totalSeconds > 0 ? item.seconds / totalSeconds : 0
                        )
                    }
                }
                
                // Total
                Divider()
                    .padding(.vertical, 4)
                
                HStack {
                    Text("Total")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Spacer()
                    AnimatedDuration(
                        totalSeconds,
                        font: .system(size: 13, weight: .bold, design: .monospaced),
                        color: BrutalTheme.textPrimary
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(todayDeviceBreakdown.count) devices, total \(DurationFormatter.short(totalSeconds))")
    }
}

private struct DeviceRow: View {
    let device: DeviceInfo
    let seconds: Double
    let percentage: Double
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                // Device icon
                Image(systemName: device.platform.icon)
                    .font(.system(size: 14))
                    .foregroundColor(device.platform.color)
                    .frame(width: 20)
                
                // Device name
                VStack(alignment: .leading, spacing: 1) {
                    Text(device.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textPrimary)
                        .lineLimit(1)
                    
                    Text(device.platform.displayName)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                
                Spacer()
                
                // Duration and percentage
                VStack(alignment: .trailing, spacing: 1) {
                    Text(DurationFormatter.short(seconds))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                    
                    Text(String(format: "%.0f%%", percentage * 100))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 3)
                    
                    Rectangle()
                        .fill(device.platform.color)
                        .frame(width: geometry.size.width * percentage, height: 3)
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5))
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Sync Status Card

/// Shows iCloud sync status and last sync time
struct SyncStatusCard: View {
    let lastSyncDate: Date?
    let deviceCount: Int
    let isSyncing: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isSyncing ? "arrow.triangle.2.circlepath" : "icloud.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .symbolEffect(.rotate, isActive: isSyncing)
                Text("SYNC STATUS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(1)
            }
            
            if let lastSync = lastSyncDate {
                Text(TimeFormatters.relativeDate(lastSync))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)
            } else {
                Text("Not synced")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.green)
                Text("\(deviceCount) device\(deviceCount == 1 ? "" : "s") synced")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        
        .hoverScale()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status: \(deviceCount) devices, last synced \(lastSyncDate.map { TimeFormatters.relativeDate($0) } ?? "never")")
    }
}

// MARK: - Platform Extension

extension DeviceInfo.Platform {
    var color: Color {
        switch self {
        case .macOS:
            return .blue
        case .iOS:
            return .green
        case .iPadOS:
            return .orange
        case .watchOS:
            return .red
        case .visionOS:
            return .indigo
        }
    }
}
