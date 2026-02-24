import SwiftUI

/// Apps list view showing synced app usage from Mac
struct AppsListView: View {
    @EnvironmentObject private var appState: IOSAppState
    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .mostUsed
    
    enum SortOrder: String, CaseIterable {
        case mostUsed = "Most Used"
        case leastUsed = "Least Used"
        case alphabetical = "A-Z"
        case sessions = "Sessions"
    }
    
    var body: some View {
        Group {
            if allApps.isEmpty {
                emptyStateView
            } else {
                appsList
            }
        }
        .searchable(text: $searchText, prompt: "Search apps")
        .refreshable {
            await appState.refreshFromCloud()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Aggregated apps from all devices
    private var allApps: [AggregatedAppUsage] {
        // Collect all app usage from all devices
        var appMap: [String: AggregatedAppUsage] = [:]
        
        for device in appState.syncPayload.devices {
            for usage in device.appUsage {
                let key = usage.bundleId
                if var existing = appMap[key] {
                    existing.totalSeconds += usage.totalSeconds
                    existing.sessionCount += usage.sessionCount
                    existing.deviceCount += 1
                    appMap[key] = existing
                } else {
                    appMap[key] = AggregatedAppUsage(
                        bundleId: usage.bundleId,
                        displayName: usage.displayName,
                        category: usage.category,
                        totalSeconds: usage.totalSeconds,
                        sessionCount: usage.sessionCount,
                        deviceCount: 1
                    )
                }
            }
        }
        
        return Array(appMap.values)
    }
    
    /// Total screen time across all apps
    private var totalScreenTime: Double {
        allApps.reduce(0) { $0 + $1.totalSeconds }
    }
    
    /// Filtered and sorted apps
    private var filteredApps: [AggregatedAppUsage] {
        var apps = allApps
        
        // Filter by search
        if !searchText.isEmpty {
            apps = apps.filter { app in
                app.displayName.localizedCaseInsensitiveContains(searchText) ||
                app.bundleId.localizedCaseInsensitiveContains(searchText) ||
                (app.category?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Sort
        switch sortOrder {
        case .mostUsed:
            apps.sort { $0.totalSeconds > $1.totalSeconds }
        case .leastUsed:
            apps.sort { $0.totalSeconds < $1.totalSeconds }
        case .alphabetical:
            apps.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .sessions:
            apps.sort { $0.sessionCount > $1.sessionCount }
        }
        
        return apps
    }
    
    /// Group apps by category
    private var groupedApps: [(category: String, apps: [AggregatedAppUsage])] {
        let grouped = Dictionary(grouping: filteredApps) { $0.category ?? "Uncategorized" }
        return grouped
            .map { (category: $0.key, apps: $0.value) }
            .sorted { $0.apps.reduce(0, { $0 + $1.totalSeconds }) > $1.apps.reduce(0, { $0 + $1.totalSeconds }) }
    }
    
    // MARK: - Views
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.grid.2x2.slash")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            
            Text("No App Data")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Sync from your Mac to see app usage here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                Task { await appState.refreshFromCloud() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var appsList: some View {
        List {
            // Summary header
            summarySection
            
            // Apps by category
            ForEach(groupedApps, id: \.category) { group in
                Section {
                    ForEach(group.apps) { app in
                        AppUsageRow(
                            app: app,
                            totalScreenTime: totalScreenTime
                        )
                    }
                } header: {
                    HStack {
                        Text(group.category)
                        Spacer()
                        Text(TimeFormatters.formatDuration(
                            group.apps.reduce(0) { $0 + $1.totalSeconds },
                            style: .compact
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .listStyle(.insetGrouped)
    }
    
    private var summarySection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(filteredApps.count) Apps")
                        .font(.headline)
                    
                    Text("Across \(appState.syncPayload.devices.count) device\(appState.syncPayload.devices.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(TimeFormatters.formatDuration(totalScreenTime, style: .compact))
                        .font(.headline)
                    
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var sortMenu: some View {
        Menu {
            ForEach(SortOrder.allCases, id: \.self) { order in
                Button {
                    sortOrder = order
                } label: {
                    HStack {
                        Text(order.rawValue)
                        if sortOrder == order {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
    }
}

// MARK: - Supporting Types

/// Aggregated app usage across devices
struct AggregatedAppUsage: Identifiable {
    let bundleId: String
    let displayName: String
    let category: String?
    var totalSeconds: Double
    var sessionCount: Int
    var deviceCount: Int
    
    var id: String { bundleId }
}

// MARK: - App Row

struct AppUsageRow: View {
    let app: AggregatedAppUsage
    let totalScreenTime: Double
    
    private var percentage: Double {
        guard totalScreenTime > 0 else { return 0 }
        return (app.totalSeconds / totalScreenTime) * 100
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            appIconPlaceholder
            
            // App info
            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("\(app.sessionCount) session\(app.sessionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if app.deviceCount > 1 {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        
                        Text("\(app.deviceCount) devices")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Usage stats
            VStack(alignment: .trailing, spacing: 4) {
                Text(TimeFormatters.formatDuration(app.totalSeconds, style: .compact))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                
                Text(String(format: "%.1f%%", percentage))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.displayName), \(TimeFormatters.formatDuration(app.totalSeconds, style: .full)), \(String(format: "%.1f", percentage)) percent of total")
    }
    
    private var appIconPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
            
            Image(systemName: categoryIcon)
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .frame(width: 44, height: 44)
    }
    
    private var categoryIcon: String {
        switch app.category?.lowercased() {
        case "productivity":
            return "hammer.fill"
        case "social":
            return "person.2.fill"
        case "entertainment":
            return "tv.fill"
        case "games":
            return "gamecontroller.fill"
        case "developer":
            return "chevron.left.forwardslash.chevron.right"
        case "communication":
            return "message.fill"
        case "business":
            return "briefcase.fill"
        case "education":
            return "graduationcap.fill"
        case "utilities":
            return "wrench.and.screwdriver.fill"
        case "music":
            return "music.note"
        case "photo & video":
            return "photo.fill"
        case "news":
            return "newspaper.fill"
        case "finance":
            return "dollarsign.circle.fill"
        case "health & fitness":
            return "heart.fill"
        case "shopping":
            return "cart.fill"
        case "travel":
            return "airplane"
        case "food & drink":
            return "fork.knife"
        default:
            return "app.fill"
        }
    }
}

#Preview {
    NavigationStack {
        AppsListView()
            .navigationTitle("Apps")
    }
    .environmentObject(IOSAppState())
}
