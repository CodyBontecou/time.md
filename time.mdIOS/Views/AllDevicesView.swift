import SwiftUI
import Charts
import FamilyControls
import DeviceActivity

/// Shows combined screen time across selected devices with toggle controls
struct AllDevicesView: View {
    @EnvironmentObject private var appState: IOSAppState
    @StateObject private var filterStore = IOSFilterStore()
    @State private var showFilters = false
    
    /// Check if Screen Time tracking is authorized (for local iPhone)
    private var hasLocalScreenTimeAccess: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Filter controls
                filterHeader
                
                // Combined total for selected devices
                combinedTotalCard
                
                // Active filters indicator
                if filterStore.hasActiveFilters {
                    activeFiltersRow
                }
                
                // Device toggles section
                deviceTogglesSection
                
                // Combined trend for selected devices
                combinedTrendCard
                
                // Top apps from selected devices
                if !appState.filteredTopApps.isEmpty {
                    filteredTopAppsCard
                }
            }
            .padding()
        }
        .scrollIndicators(.never)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await appState.refreshFromCloud()
        }
        .onAppear {
            appState.initializeDeviceSelectionIfNeeded()
        }
        .sheet(isPresented: $showFilters) {
            IOSTimeFiltersView(filterStore: filterStore)
        }
    }
    
    // MARK: - Filter Header
    
    private var filterHeader: some View {
        HStack(spacing: 12) {
            // Granularity picker
            Menu {
                ForEach(TimeGranularity.allCases) { granularity in
                    Button {
                        withAnimation {
                            filterStore.granularity = granularity
                        }
                    } label: {
                        HStack {
                            Text(granularity.title)
                            if filterStore.granularity == granularity {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(filterStore.granularity.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: Capsule())
            }
            .buttonStyle(.plain)
            
            // Date label
            Text(LocalizedStringKey(filterStore.dateRangeLabel))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Filter button
            Button {
                showFilters = true
            } label: {
                Image(systemName: filterStore.hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .font(.title3)
                    .foregroundStyle(filterStore.hasActiveFilters ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Active Filters Row
    
    private var activeFiltersRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption)
            
            if let label = filterStore.activeFiltersLabel {
                Text(LocalizedStringKey(label))
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            Button {
                withAnimation {
                    filterStore.clearAllFilters()
                }
            } label: {
                Text("Clear")
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: Date()) else {
            return DeviceActivityFilter()
        }
        return DeviceActivityFilter(segment: .daily(during: interval))
    }
    
    // MARK: - Combined Total Card
    
    private var combinedTotalCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: deviceIcon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                Text(LocalizedStringKey(headerText))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }

            Text(verbatim: appState.filteredTodayFormatted)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3), value: appState.filteredTodayTotalSeconds)

            Text(LocalizedStringKey(subtitleText))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
    
    private var deviceIcon: String {
        // Only count synced devices (not iPhone) for the combined total display
        let syncedSelectedCount = appState.selectedDeviceIds.filter { id in
            id != appState.currentDevice.id && appState.syncPayload.devices.contains { $0.id == id }
        }.count
        
        if syncedSelectedCount == 0 {
            return "rectangle.slash"
        } else if syncedSelectedCount == 1 {
            if let deviceId = appState.selectedDeviceIds.first(where: { $0 != appState.currentDevice.id }),
               let device = appState.syncPayload.devices.first(where: { $0.id == deviceId }) {
                return device.device.platform.icon
            }
            return "desktopcomputer"
        } else {
            return "macbook.and.iphone"
        }
    }
    
    private var headerText: String {
        // Only count synced devices for header
        let syncedSelectedCount = appState.selectedDeviceIds.filter { id in
            id != appState.currentDevice.id && appState.syncPayload.devices.contains { $0.id == id }
        }.count
        
        if syncedSelectedCount == 0 {
            return "NO SYNCED DEVICES"
        } else if syncedSelectedCount == 1 {
            if let deviceId = appState.selectedDeviceIds.first(where: { $0 != appState.currentDevice.id }),
               let device = appState.syncPayload.devices.first(where: { $0.id == deviceId }) {
                return device.device.name.uppercased()
            }
            return "1 DEVICE"
        } else {
            return "\(syncedSelectedCount) DEVICES"
        }
    }
    
    private var subtitleText: String {
        let syncedSelectedCount = appState.selectedDeviceIds.filter { id in
            id != appState.currentDevice.id && appState.syncPayload.devices.contains { $0.id == id }
        }.count
        
        if syncedSelectedCount == 0 {
            return "Enable synced devices to see combined data"
        } else if syncedSelectedCount == 1 {
            return "Today's screen time"
        } else {
            return "Today's combined screen time"
        }
    }
    
    // MARK: - Device Toggles Section
    
    private var deviceTogglesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Devices")
                    .font(.headline)
                
                Spacer()
                
                // Select All / None toggle
                if totalDeviceCount > 1 {
                    Button {
                        if appState.allDevicesSelected {
                            appState.deselectAllDevices()
                        } else {
                            appState.selectAllDevices()
                        }
                    } label: {
                        Text(appState.allDevicesSelected ? "Clear All" : "Select All")
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                }
            }
            
            if appState.syncPayload.devices.isEmpty && !hasLocalScreenTimeAccess {
                emptyDevicesView
            } else {
                VStack(spacing: 0) {
                    // Local iPhone (this device)
                    if hasLocalScreenTimeAccess {
                        localDeviceToggle
                        
                        if !appState.syncPayload.devices.isEmpty {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                    
                    // Synced devices (excluding current device since it's shown above with live data)
                    let otherDevices = appState.syncPayload.devices.filter { $0.id != appState.currentDevice.id }
                    ForEach(Array(otherDevices.enumerated()), id: \.element.id) { index, deviceData in
                        deviceToggle(deviceData)
                        
                        if index < otherDevices.count - 1 {
                            Divider()
                                .padding(.leading, 56)
                        }
                    }
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private var totalDeviceCount: Int {
        // Count other devices (excluding current device) plus this device if Screen Time access
        let otherDevicesCount = appState.syncPayload.devices.filter { $0.id != appState.currentDevice.id }.count
        return otherDevicesCount + (hasLocalScreenTimeAccess ? 1 : 0)
    }
    
    private var emptyDevicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            
            Text("No devices synced yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text("Open time.md on your Mac to sync data")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
    
    private var localDeviceToggle: some View {
        let isSelected = appState.selectedDeviceIds.contains(appState.currentDevice.id)
        
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Device icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "iphone")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                
                // Device info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(verbatim: appState.currentDevice.name)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("This device")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                    
                    Text("iPhone • Live Screen Time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Toggle
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in appState.toggleDevice(appState.currentDevice.id) }
                ))
                .labelsHidden()
                .tint(.accentColor)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    appState.toggleDevice(appState.currentDevice.id)
                }
            }
            
            // Show DeviceActivityReport only when iPhone is toggled ON
            if isSelected {
                VStack(alignment: .leading, spacing: 8) {
                    // Privacy explanation
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        
                        Text("Displayed separately due to iOS privacy restrictions")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 4)
                    
                    // DeviceActivityReport displays iPhone screen time
                    DeviceActivityReport(
                        DeviceActivityReport.Context(rawValue: "TotalActivity"),
                        filter: todayFilter
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.leading, 56)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
    
    private func deviceToggle(_ deviceData: DeviceSyncData) -> some View {
        let isSelected = appState.isDeviceSelected(deviceData.id)
        let isCurrentDevice = deviceData.id == appState.currentDevice.id
        let todaySeconds = deviceData.dailySummaries
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.totalSeconds }
        
        return HStack(spacing: 12) {
            // Device icon
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                    .frame(width: 44, height: 44)
                
                Image(systemName: deviceData.device.platform.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            
            // Device info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(verbatim: deviceData.device.name)
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
                
                Text("\(deviceData.device.platform.displayName) • \(TimeFormatters.relativeDate(deviceData.lastSyncDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Today's total and toggle
            VStack(alignment: .trailing, spacing: 4) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in appState.toggleDevice(deviceData.id) }
                ))
                .labelsHidden()
                .tint(.accentColor)
                
                if todaySeconds > 0 {
                    Text(TimeFormatters.formatDuration(todaySeconds, style: .compact))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.3)) {
                appState.toggleDevice(deviceData.id)
            }
        }
    }
    
    // MARK: - Combined Trend Card
    
    private var combinedTrendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weekly Trend")
                    .font(.headline)
                
                Spacer()
                
                let syncedCount = appState.selectedDeviceIds.filter { id in
                    id != appState.currentDevice.id && appState.syncPayload.devices.contains { $0.id == id }
                }.count
                Text("\(syncedCount) synced device\(syncedCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if appState.selectedDeviceIds.isEmpty || appState.selectedDeviceIds == Set([appState.currentDevice.id]) {
                Text("Select synced devices to see trends")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else if appState.filteredRecentTrend.allSatisfy({ $0.totalSeconds == 0 }) {
                Text("No data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(appState.filteredRecentTrend) { point in
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
                .animation(.spring(response: 0.3), value: appState.filteredRecentTrend.map { $0.totalSeconds })
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Filtered Top Apps Card
    
    private var filteredTopAppsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Apps")
                    .font(.headline)
                
                Spacer()
                
                Text("From synced devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(appState.filteredTopApps.prefix(5), id: \.appName) { app in
                HStack {
                    // App icon placeholder
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemGray4))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Text(verbatim: String(app.appName.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: app.appName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text("\(app.sessionCount) sessions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(TimeFormatters.formatDuration(app.totalSeconds, style: .compact))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    NavigationStack {
        AllDevicesView()
            .navigationTitle("Devices")
    }
    .environmentObject(IOSAppState())
}
