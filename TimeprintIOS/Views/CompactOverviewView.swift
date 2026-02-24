import SwiftUI
import Charts
import FamilyControls

/// Compact overview dashboard for iOS
struct CompactOverviewView: View {
    @EnvironmentObject private var appState: IOSAppState
    
    /// Check if Screen Time tracking is authorized
    private var hasScreenTimeAccess: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Hero stat card
                heroCard
                
                // Local iPhone Screen Time card (if authorized)
                if hasScreenTimeAccess {
                    LocalScreenTimeCard()
                }
                
                // Stats row
                statsRow
                
                // Streak indicator (if active)
                if appState.currentStreak > 1 {
                    streakCard
                }
                
                // Trend chart
                trendCard
                
                // Local top apps (if authorized)
                if hasScreenTimeAccess {
                    LocalTopAppsCard()
                }
                
                // Device breakdown
                if !appState.syncPayload.devices.isEmpty {
                    devicesCard
                }
                
                // Sync status
                syncStatusCard
            }
            .padding()
        }
        .scrollIndicators(.never)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await appState.refreshFromCloud()
            // Also refresh local device activity data
            appState.refreshLocalDeviceActivityData()
        }
        .onAppear {
            // Refresh local device activity data when view appears
            // Use a slight delay to allow DeviceActivityReport views to populate
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                appState.refreshLocalDeviceActivityData()
            }
        }
        .alert("Sync Error", isPresented: $appState.showErrorAlert) {
            Button("OK") {
                appState.dismissError()
            }
        } message: {
            Text(appState.error ?? "An unknown error occurred")
        }
        .overlay(alignment: .top) {
            if appState.syncSucceeded {
                syncSuccessBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: appState.syncSucceeded)
            }
        }
    }
    
    // MARK: - Sync Success Banner
    
    private var syncSuccessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Synced successfully")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.top, 8)
    }
    
    // MARK: - Streak Card
    
    private var streakCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(appState.currentStreak)-day streak!")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("Keep tracking your screen time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.15), .yellow.opacity(0.1)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're on a \(appState.currentStreak)-day streak! Keep tracking your screen time.")
    }
    
    // MARK: - Hero Card
    
    private var heroCard: some View {
        VStack(spacing: 8) {
            Text("TODAY")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .tracking(1)
            
            Text(appState.todayFormatted)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            
            Text("screen time")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's screen time: \(appState.todayFormatted)")
        .accessibilityHint("Shows your total screen time for today")
    }
    
    // MARK: - Stats Row
    
    private var statsRow: some View {
        HStack(spacing: 12) {
            statCell(
                title: "This Week",
                value: appState.weekFormatted,
                icon: "calendar"
            )
            
            statCell(
                title: "Daily Avg",
                value: appState.dailyAverageFormatted,
                icon: "chart.line.uptrend.xyaxis"
            )
            
            statCell(
                title: "Devices",
                value: "\(appState.syncPayload.devices.count)",
                icon: "macbook.and.iphone"
            )
        }
    }
    
    private func statCell(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
            
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
    
    // MARK: - Trend Card
    
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-Day Trend")
                    .font(.headline)
                
                Spacer()
                
                Text("All Devices")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if appState.recentTrend.isEmpty {
                Text("No data yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                Chart(appState.recentTrend) { point in
                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.totalSeconds / 3600)
                    )
                    .foregroundStyle(.tint.opacity(0.3))
                    
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.totalSeconds / 3600)
                    )
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
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
                .frame(height: 150)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Devices Card
    
    private var devicesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Per Device")
                .font(.headline)
            
            let breakdown = appState.syncPayload.perDeviceBreakdown(for: Date())
            
            if breakdown.isEmpty {
                Text("No data for today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                ForEach(breakdown, id: \.device.id) { item in
                    HStack {
                        Image(systemName: item.device.platform.icon)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.device.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text(item.device.platform.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(TimeFormatters.formatDuration(item.seconds, style: .compact))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Sync Status Card
    
    private var syncStatusCard: some View {
        HStack {
            ZStack {
                Image(systemName: appState.isSyncEnabled ? "icloud.fill" : "icloud.slash")
                    .foregroundStyle(appState.isSyncEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                
                // Success checkmark overlay
                if appState.syncSucceeded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .offset(x: 8, y: 8)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isSyncEnabled ? "iCloud Sync Active" : "iCloud Sync Disabled")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Last sync: \(appState.lastSyncFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if appState.isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button {
                    Task { await appState.triggerSync() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title3)
                }
                .disabled(appState.isLoading)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Focus Blocks Extension

extension IOSAppState {
    var focusBlocksFormatted: String {
        "\(focusBlocks)"
    }
    
    var currentStreakFormatted: String {
        "\(currentStreak) days"
    }
}

#Preview {
    NavigationStack {
        CompactOverviewView()
            .navigationTitle("Overview")
    }
    .environmentObject(IOSAppState())
}
