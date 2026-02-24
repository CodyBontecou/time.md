import SwiftUI
import Charts

/// Shows combined screen time across all synced devices
struct AllDevicesView: View {
    @EnvironmentObject private var appState: IOSAppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Combined total
                combinedTotalCard
                
                // Device list
                deviceListSection
                
                // Combined trend
                combinedTrendCard
            }
            .padding()
        }
        .scrollIndicators(.never)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await appState.refreshFromCloud()
        }
    }
    
    // MARK: - Combined Total
    
    private var combinedTotalCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "macbook.and.iphone")
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                Text("ALL DEVICES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
            
            Text(TimeFormatters.formatDuration(appState.syncPayload.todayTotalAllDevices, style: .compact))
                .font(.system(size: 48, weight: .bold, design: .rounded))
            
            Text("Today's combined screen time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    // MARK: - Device List
    
    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Devices")
                .font(.headline)
            
            if appState.syncPayload.devices.isEmpty {
                emptyDevicesView
            } else {
                ForEach(appState.syncPayload.devices) { deviceData in
                    deviceRow(deviceData)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var emptyDevicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("No devices synced yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Open Timeprint on your Mac to sync data")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    private func deviceRow(_ deviceData: DeviceSyncData) -> some View {
        let isCurrentDevice = deviceData.id == appState.currentDevice.id
        let todaySeconds = deviceData.dailySummaries
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.totalSeconds }
        
        return HStack(spacing: 12) {
            // Device icon
            ZStack {
                Circle()
                    .fill(isCurrentDevice ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                    .frame(width: 44, height: 44)
                
                Image(systemName: deviceData.device.platform.icon)
                    .font(.title3)
                    .foregroundStyle(isCurrentDevice ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            
            // Device info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(deviceData.device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if isCurrentDevice {
                        Text("This device")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
                
                Text("\(deviceData.device.platform.displayName) • Last sync \(TimeFormatters.relativeDate(deviceData.lastSyncDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Today's total
            VStack(alignment: .trailing, spacing: 2) {
                Text(TimeFormatters.formatDuration(todaySeconds, style: .compact))
                    .font(.headline)
                    .monospacedDigit()
                
                Text("today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Combined Trend
    
    private var combinedTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Combined Weekly Trend")
                .font(.headline)
            
            if appState.recentTrend.allSatisfy({ $0.totalSeconds == 0 }) {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(appState.recentTrend) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.totalSeconds / 3600)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        if let date = value.as(Date.self) {
                            AxisValueLabel {
                                Text(TimeFormatters.dayOfWeek(date))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        AllDevicesView()
            .navigationTitle("All Devices")
    }
    .environmentObject(IOSAppState())
}
