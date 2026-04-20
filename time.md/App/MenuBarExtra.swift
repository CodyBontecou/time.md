import Combine
import SwiftUI

#if os(macOS)
/// Menu bar extra showing today's screen time at a glance
struct TimeMdMenuBarExtra: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.openWindow) private var openWindow
    @State private var todayTotal: TimeInterval = 0
    @State private var topApps: [AppUsageSummary] = []
    @State private var isLoading = true

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with today's total
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.tint)
                    
                    Text("Today")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text(formatDuration(todayTotal))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }
            }
            .padding(.bottom, 4)
            
            Divider()
            
            // Top apps
            if topApps.isEmpty && !isLoading {
                Text("No screen time recorded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Text("Top Apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                ForEach(topApps) { app in
                    HStack(spacing: 8) {
                        AppIconView(bundleID: app.appName, size: 18)

                        Text(AppNameDisplay.displayName(for: app.appName, mode: .short))
                            .lineLimit(1)

                        Spacer()

                        Text(formatDuration(app.totalSeconds))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            
            Divider()
            
            // Actions
            Button {
                openMainWindow()
            } label: {
                Label("Open time.md", systemImage: "macwindow")
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 220)
        .task {
            await loadData()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await loadData()
            }
        }
    }
    
    private func loadData() async {
        isLoading = true

        do {
            // Fetch today's summary
            let summary = try await appEnvironment.dataService.fetchTodaySummary()
            todayTotal = summary.todayTotalSeconds
            
            // Fetch top apps for today
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let filters = FilterSnapshot(
                startDate: startOfDay,
                endDate: Date(),
                granularity: .day,
                selectedApps: [],
                selectedCategories: [],
                selectedHeatmapCells: [],
                timeOfDayRanges: [],
                weekdayFilter: [],
                minDurationSeconds: nil,
                maxDurationSeconds: nil
            )
            
            topApps = try await appEnvironment.dataService.fetchTopApps(filters: filters, limit: 5)
        } catch {
            print("[MenuBar] Failed to load data: \(error)")
        }
        
        isLoading = false
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func openMainWindow() {
        // Restore Dock presence in case user enabled "menu bar only on close"
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain && $0.isVisible }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var todayTotal: TimeInterval = 0

    private let refreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.fill")
            Text(formatCompact(todayTotal))
                .monospacedDigit()
        }
        .task {
            await loadTotal()
        }
        .onReceive(refreshTimer) { _ in
            Task {
                await loadTotal()
            }
        }
    }
    
    private func loadTotal() async {
        do {
            let summary = try await appEnvironment.dataService.fetchTodaySummary()
            todayTotal = summary.todayTotalSeconds
        } catch {
            print("[MenuBar] Failed to load total: \(error)")
        }
    }
    
    private func formatCompact(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours):\(String(format: "%02d", minutes))"
        }
        return "\(minutes)m"
    }
}

#Preview("Menu Bar Content") {
    TimeMdMenuBarExtra()
        .environment(\.appEnvironment, .live)
        .frame(width: 220)
}
#endif
