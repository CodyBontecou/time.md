import SwiftUI
import UserNotifications
import FamilyControls
import StoreKit

/// Settings view for iOS Timeprint
struct IOSSettingsView: View {
    @EnvironmentObject private var appState: IOSAppState
    @StateObject private var authService = AuthorizationService()
    @StateObject private var monitoringScheduler = MonitoringScheduler()
    @Environment(\.requestReview) private var requestReview
    @State private var showingAbout = false
    @State private var showingOnboarding = false
    @State private var notificationSettings = NotificationSettings.load()
    @State private var notificationAuthStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingShareSheet = false
    @State private var showingExportSheet = false
    @State private var shareItems: [Any] = []
    @State private var exportURL: URL?
    
    var body: some View {
        List {
            // Device section
            Section {
                deviceInfoRow
            } header: {
                Text("This Device")
            }
            
            // iCloud sync section
            Section {
                syncStatusRow
                
                if appState.isSyncEnabled {
                    syncNowRow
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Sync allows you to see combined screen time from all your devices in one place.")
            }
            
            // Screen Time section
            Section {
                screenTimeAuthorizationRow
                
                if authService.isAuthorized {
                    monitoringStatusRow
                    monitoringToggleRow
                }
            } header: {
                Text("iPhone Screen Time")
            } footer: {
                if authService.isAuthorized {
                    Text("Screen Time tracking is active. Your iPhone usage data will be captured and synced.")
                } else {
                    Text("Enable Screen Time access to track your iPhone usage alongside your Mac data.")
                }
            }
            
            // Notifications section
            Section {
                notificationSettingsRows
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get reminders to check your screen time.")
            }
            
            // Data section
            Section {
                dataRows
            } header: {
                Text("Data")
            } footer: {
                Text("Export your synced screen time data or share summaries.")
            }
            
            // About section
            Section {
                aboutRow
                privacyRow
                rateAppRow
            } header: {
                Text("About")
            }
            
            // Debug section (only in debug builds)
            #if DEBUG
            Section {
                debugInfoRow
            } header: {
                Text("Debug")
            }
            #endif
        }
        .scrollIndicators(.never)
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: shareItems)
        }
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
        .task {
            notificationAuthStatus = await NotificationService.shared.checkAuthorizationStatus()
            await authService.checkCurrentStatus()
        }
        .sheet(isPresented: $showingOnboarding) {
            ScreenTimeOnboardingView(isPresented: $showingOnboarding) { authorized in
                if authorized {
                    try? monitoringScheduler.startDailyMonitoring()
                }
            }
        }
    }
    
    // MARK: - Data Rows
    
    @ViewBuilder
    private var dataRows: some View {
        // Share Today's Summary
        Button {
            let summary = ExportService.shared.generateShareableSummary(from: appState.syncPayload)
            shareItems = [summary]
            showingShareSheet = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Today's Summary")
                    Text("Share a text summary of today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(appState.syncPayload.devices.isEmpty)
        
        // Share Weekly Summary
        Button {
            let summary = ExportService.shared.generateWeeklySummary(from: appState.syncPayload)
            shareItems = [summary]
            showingShareSheet = true
        } label: {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share Weekly Summary")
                    Text("Share your week's screen time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(appState.syncPayload.devices.isEmpty)
        
        // Export as CSV
        Button {
            if let url = ExportService.shared.exportData(from: appState.syncPayload, format: .csv) {
                exportURL = url
                showingExportSheet = true
            }
        } label: {
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(.green)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export as CSV")
                    Text("Spreadsheet-compatible format")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(appState.syncPayload.devices.isEmpty)
        
        // Export as JSON
        Button {
            if let url = ExportService.shared.exportData(from: appState.syncPayload, format: .json) {
                exportURL = url
                showingExportSheet = true
            }
        } label: {
            HStack {
                Image(systemName: "curlybraces")
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export as JSON")
                    Text("For developers and automation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(appState.syncPayload.devices.isEmpty)
    }
    
    // MARK: - Notification Settings
    
    @ViewBuilder
    private var notificationSettingsRows: some View {
        // Authorization status
        if notificationAuthStatus == .denied {
            HStack {
                Image(systemName: "bell.slash")
                    .foregroundStyle(.orange)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notifications Disabled")
                    Text("Enable in Settings app")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption)
            }
        } else {
            // Daily summary toggle
            Toggle(isOn: $notificationSettings.dailySummaryEnabled) {
                HStack {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(.tint)
                        .frame(width: 32)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Summary")
                        Text("Reminder at \(formattedTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: notificationSettings.dailySummaryEnabled) { _, enabled in
                Task {
                    if enabled {
                        let granted = await NotificationService.shared.requestAuthorization()
                        if granted {
                            await NotificationService.shared.scheduleDailySummary(
                                at: notificationSettings.dailySummaryHour,
                                minute: notificationSettings.dailySummaryMinute
                            )
                        } else {
                            notificationSettings.dailySummaryEnabled = false
                        }
                    } else {
                        NotificationService.shared.cancelDailySummary()
                    }
                    notificationSettings.save()
                }
            }
            
            // Time picker (when enabled)
            if notificationSettings.dailySummaryEnabled {
                DatePicker(
                    "Reminder Time",
                    selection: Binding(
                        get: {
                            Calendar.current.date(from: DateComponents(
                                hour: notificationSettings.dailySummaryHour,
                                minute: notificationSettings.dailySummaryMinute
                            )) ?? Date()
                        },
                        set: { newDate in
                            let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                            notificationSettings.dailySummaryHour = components.hour ?? 21
                            notificationSettings.dailySummaryMinute = components.minute ?? 0
                            notificationSettings.save()
                            
                            Task {
                                await NotificationService.shared.scheduleDailySummary(
                                    at: notificationSettings.dailySummaryHour,
                                    minute: notificationSettings.dailySummaryMinute
                                )
                            }
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
            }
            
        }
    }
    
    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let date = Calendar.current.date(from: DateComponents(
            hour: notificationSettings.dailySummaryHour,
            minute: notificationSettings.dailySummaryMinute
        )) ?? Date()
        return formatter.string(from: date)
    }
    
    // MARK: - Device Info
    
    private var deviceInfoRow: some View {
        HStack {
            Image(systemName: appState.currentDevice.platform.icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.currentDevice.name)
                    .font(.body)
                
                Text("\(appState.currentDevice.model) • \(appState.currentDevice.platform.displayName) \(appState.currentDevice.osVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Sync
    
    private var syncStatusRow: some View {
        HStack {
            Image(systemName: appState.isSyncEnabled ? "icloud.fill" : "icloud.slash")
                .foregroundStyle(appState.isSyncEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud Sync")
                
                Text(appState.isSyncEnabled ? "Connected" : "Not available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if appState.isSyncEnabled {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
    
    private var syncNowRow: some View {
        Button {
            Task { await appState.triggerSync() }
        } label: {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .frame(width: 32)
                
                Text("Sync Now")
                
                Spacer()
                
                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let lastSync = appState.lastSyncDate {
                    Text(TimeFormatters.relativeDate(lastSync))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(appState.isLoading)
    }
    
    // MARK: - Screen Time Permission
    
    private var screenTimeAuthorizationRow: some View {
        HStack {
            Image(systemName: authService.authorizationStatus.systemImageName)
                .foregroundStyle(authStatusColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Authorization Status")
                
                Text(authService.authorizationStatus.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !authService.isAuthorized {
                Button {
                    Task {
                        await authService.requestAuthorization()
                        if authService.isAuthorized {
                            try? monitoringScheduler.startDailyMonitoring()
                        }
                    }
                } label: {
                    Text("Enable")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }
    
    private var monitoringStatusRow: some View {
        HStack {
            Image(systemName: monitoringScheduler.isMonitoringActive ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(monitoringScheduler.isMonitoringActive ? .green : .secondary)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Tracking Status")
                
                Text(monitoringScheduler.isMonitoringActive ? "Active" : "Inactive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if !monitoringScheduler.activeSchedules.isEmpty {
                Text("\(monitoringScheduler.activeSchedules.count) schedules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var monitoringToggleRow: some View {
        Toggle(isOn: Binding(
            get: { monitoringScheduler.isMonitoringActive },
            set: { enabled in
                if enabled {
                    try? monitoringScheduler.startDailyMonitoring()
                } else {
                    monitoringScheduler.stopAllMonitoring()
                }
            }
        )) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Tracking")
                    Text("Track usage 24/7")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var authStatusColor: Color {
        switch authService.authorizationStatus {
        case .approved: return .green
        case .denied: return .red
        case .notDetermined: return .secondary
        }
    }
    
    private var screenTimeSetupRow: some View {
        Button {
            showingOnboarding = true
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup Screen Time")
                    Text("Step-by-step guide")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
    
    // MARK: - About
    
    private var aboutRow: some View {
        Button {
            showingAbout = true
        } label: {
            HStack {
                Image(systemName: "info.circle")
                    .frame(width: 32)
                
                Text("About Timeprint")
                
                Spacer()
                
                Text("v1.0")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
    }
    
    private var privacyRow: some View {
        Link(destination: URL(string: "https://timeprint.app/privacy")!) {
            HStack {
                Image(systemName: "hand.raised")
                    .frame(width: 32)
                
                Text("Privacy Policy")
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
    
    private var rateAppRow: some View {
        Button {
            requestReview()
        } label: {
            HStack {
                Image(systemName: "star")
                    .frame(width: 32)
                
                Text("Rate on App Store")
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
    
    // MARK: - Debug
    
    #if DEBUG
    private var debugInfoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device ID")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(appState.currentDevice.id)
                .font(.caption2)
                .monospaced()
            
            Divider()
            
            Text("Synced Devices: \(appState.syncPayload.devices.count)")
                .font(.caption)
            
            Text("Today Total: \(appState.todayTotalSeconds)s")
                .font(.caption)
            
            Divider()
            
            Button("Reset Onboarding") {
                UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
            }
            .font(.caption)
            .foregroundStyle(.red)
        }
        .padding(.vertical, 4)
    }
    #endif
}

// MARK: - About View

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                    
                    // Title
                    VStack(spacing: 4) {
                        Text("Timeprint")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Screen Time Analytics")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Description
                    Text("Understand your digital habits with beautiful visualizations of your screen time data. Privacy-first, local-only analytics for your Apple devices.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                    
                    // Features
                    VStack(alignment: .leading, spacing: 16) {
                        featureRow(icon: "lock.shield", title: "Privacy First", description: "All data stays on your device")
                        featureRow(icon: "chart.bar.xaxis", title: "Rich Analytics", description: "Trends, heatmaps, and insights")
                        featureRow(icon: "macbook.and.iphone", title: "Cross-Device", description: "See all devices in one view")
                    }
                    .padding()
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 16))
                    
                    // Version
                    Text("Version 1.0.0 (Build 1)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Text("© 2026 Cody Bontecou")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .scrollIndicators(.never)
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        IOSSettingsView()
            .navigationTitle("Settings")
    }
    .environmentObject(IOSAppState())
}
