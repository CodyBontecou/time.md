import SwiftUI
import DeviceActivity
import FamilyControls

/// Wrapper view for embedding DeviceActivityReport in the main app
struct LocalScreenTimeCard: View {
    @StateObject private var authService = AuthorizationService()
    
    var body: some View {
        Group {
            if authService.isAuthorized {
                AuthorizedContent()
            } else {
                UnauthorizedContent(authService: authService)
            }
        }
        .task {
            await authService.checkCurrentStatus()
        }
    }
}

// MARK: - Authorized Content

private struct AuthorizedContent: View {
    @State private var isLoading = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Label("iPhone", systemImage: "iphone")
                    .font(.headline)
                
                Spacer()
                
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // DeviceActivityReport for total activity
            ZStack {
                // Loading placeholder shown while report loads
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading Screen Time...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120)
                }
                
                DeviceActivityReport(
                    DeviceActivityReport.Context(rawValue: "TotalActivity"),
                    filter: todayFilter
                )
                .onAppear {
                    // Give the extension time to load, then hide loading indicator
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            isLoading = false
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iPhone Screen Time for today")
    }
    
    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        let now = Date()
        
        // Get today's date interval
        guard let interval = calendar.dateInterval(of: .day, for: now) else {
            return DeviceActivityFilter()
        }
        
        return DeviceActivityFilter(
            segment: .daily(during: interval)
        )
    }
}

// MARK: - Unauthorized Content

private struct UnauthorizedContent: View {
    @ObservedObject var authService: AuthorizationService
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.badge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 4) {
                Text("iPhone Tracking Unavailable")
                    .font(.headline)
                
                Text("Enable Screen Time access to track iPhone usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                Task {
                    await authService.requestAuthorization()
                }
            } label: {
                Text("Enable Tracking")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .accessibilityLabel("Enable iPhone Screen Time tracking")
            .accessibilityHint("Requests permission to track your iPhone usage")
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("iPhone tracking is not enabled")
    }
}

// MARK: - Top Apps Report Card

struct LocalTopAppsCard: View {
    @StateObject private var authService = AuthorizationService()
    
    var body: some View {
        Group {
            if authService.isAuthorized {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("iPhone Apps", systemImage: "square.grid.2x2")
                            .font(.headline)
                        
                        Spacer()
                        
                        NavigationLink {
                            LocalAppsDetailView()
                        } label: {
                            Text("See All")
                                .font(.caption)
                        }
                    }
                    
                    DeviceActivityReport(
                        DeviceActivityReport.Context(rawValue: "TopApps"),
                        filter: todayFilter
                    )
                    .frame(minHeight: 200)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .task {
            await authService.checkCurrentStatus()
        }
    }
    
    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: Date()) else {
            return DeviceActivityFilter()
        }
        return DeviceActivityFilter(segment: .daily(during: interval))
    }
}

// MARK: - Weekly Report Card

struct LocalWeeklyReportCard: View {
    @StateObject private var authService = AuthorizationService()
    
    var body: some View {
        Group {
            if authService.isAuthorized {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("This Week", systemImage: "calendar")
                            .font(.headline)
                        
                        Spacer()
                    }
                    
                    DeviceActivityReport(
                        DeviceActivityReport.Context(rawValue: "TotalActivity"),
                        filter: weekFilter
                    )
                    .frame(minHeight: 150)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .task {
            await authService.checkCurrentStatus()
        }
    }
    
    private var weekFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return DeviceActivityFilter()
        }
        return DeviceActivityFilter(segment: .weekly(during: interval))
    }
}

// MARK: - Local Apps Detail View

struct LocalAppsDetailView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DeviceActivityReport(
                    DeviceActivityReport.Context(rawValue: "TopApps"),
                    filter: todayFilter
                )
                .frame(minHeight: 500)
            }
            .padding()
        }
        .navigationTitle("iPhone Apps")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var todayFilter: DeviceActivityFilter {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .day, for: Date()) else {
            return DeviceActivityFilter()
        }
        return DeviceActivityFilter(segment: .daily(during: interval))
    }
}

// MARK: - Preview

#Preview("Authorized") {
    LocalScreenTimeCard()
}

#Preview("Top Apps") {
    LocalTopAppsCard()
}
