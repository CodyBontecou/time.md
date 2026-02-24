import Charts
import SwiftUI

/// Displays web browsing history synced from Mac devices
struct WebHistoryView: View {
    @EnvironmentObject private var appState: IOSAppState
    
    @State private var webData: WebBrowsingSyncData?
    @State private var sourceMac: DeviceInfo?
    @State private var isLoading = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isLoading {
                    loadingView
                } else if let data = webData, data.totalVisits > 0 {
                    contentView(data)
                } else {
                    emptyStateView
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await loadWebHistory()
        }
        .refreshable {
            await loadWebHistory()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading web history...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Web History")
                .font(.title2.bold())
            
            Text("Web browsing history is collected from your Mac and synced via iCloud. Open Timeprint on your Mac to start tracking.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            HStack(spacing: 8) {
                Image(systemName: "desktopcomputer")
                    .foregroundColor(.accentColor)
                Text("Supported browsers: Safari, Chrome, Arc, Brave, Edge")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private func contentView(_ data: WebBrowsingSyncData) -> some View {
        // Source info
        if let mac = sourceMac {
            sourceInfoCard(mac, lastUpdated: data.lastUpdated)
        }
        
        // Metrics
        metricsSection(data)
        
        // Top domains
        topDomainsSection(data.topDomains)
        
        // Daily activity chart
        dailyActivitySection(data.dailyCounts)
    }
    
    // MARK: - Source Info Card
    
    private func sourceInfoCard(_ device: DeviceInfo, lastUpdated: Date) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Synced from \(device.name)")
                    .font(.subheadline.weight(.medium))
                
                Text("Last updated \(lastUpdated, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "icloud.fill")
                .foregroundColor(.accentColor)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Metrics Section
    
    private func metricsSection(_ data: WebBrowsingSyncData) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(
                icon: "globe",
                title: "Total Visits",
                value: "\(data.totalVisits)"
            )
            
            metricCard(
                icon: "link",
                title: "Domains",
                value: "\(data.topDomains.count)"
            )
            
            metricCard(
                icon: "chart.line.uptrend.xyaxis",
                title: "Daily Avg",
                value: dailyAvgString(data)
            )
            
            metricCard(
                icon: "calendar",
                title: "Days Tracked",
                value: "\(data.dailyCounts.count)"
            )
        }
    }
    
    private func metricCard(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.accentColor)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2.weight(.bold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func dailyAvgString(_ data: WebBrowsingSyncData) -> String {
        let days = max(data.dailyCounts.count, 1)
        let avg = Double(data.totalVisits) / Double(days)
        return String(format: "%.0f", avg)
    }
    
    // MARK: - Top Domains Section
    
    private func topDomainsSection(_ domains: [DomainSyncSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TOP DOMAINS")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            VStack(spacing: 0) {
                ForEach(Array(domains.prefix(10).enumerated()), id: \.element.id) { index, domain in
                    domainRow(domain, rank: index + 1, maxCount: domains.first?.visitCount ?? 1)
                    
                    if index < min(domains.count, 10) - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    private func domainRow(_ domain: DomainSyncSummary, rank: Int, maxCount: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.caption.weight(.medium).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(domain.domain)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                
                // Progress bar
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(domain.visitCount) / CGFloat(max(maxCount, 1)))
                }
                .frame(height: 4)
                .cornerRadius(2)
            }
            
            Spacer()
            
            Text("\(domain.visitCount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // MARK: - Daily Activity Section
    
    private func dailyActivitySection(_ counts: [DailyWebVisitCount]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DAILY ACTIVITY")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            if counts.isEmpty {
                Text("No activity data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
            } else {
                Chart(counts) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Visits", point.visitCount)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(2)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(counts.count / 5, 1))) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.abbreviated).day())
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let v = value.as(Int.self) {
                                Text("\(v)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 180)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadWebHistory() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let syncService = iCloudSyncService(containerIdentifier: "iCloud.com.codybontecou.Timeprint")
            let payload = try await syncService.fetchPayload()
            
            // Find Mac device with web browsing data
            for device in payload.devices {
                if device.device.platform == .macOS, device.hasWebBrowsingData {
                    webData = device.webBrowsing
                    sourceMac = device.device
                    break
                }
            }
        } catch {
            print("[WebHistory] Failed to load: \(error)")
        }
    }
}

#Preview {
    NavigationStack {
        WebHistoryView()
            .navigationTitle("Web History")
    }
    .environmentObject(IOSAppState())
}
