import AppKit
import Charts
import SwiftUI

// MARK: - Tab modes

private enum WebHistoryTab: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case domains = "Top Domains"
    case activity = "Activity"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .timeline: return "clock"
        case .domains: return "chart.bar.fill"
        case .activity: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - View

struct WebHistoryView: View {
    let filters: GlobalFilterStore

    @State private var tab: WebHistoryTab = .timeline
    @State private var browserFilter: BrowserSource = .all
    @State private var searchText: String = ""
    @State private var visits: [BrowsingVisit] = []
    @State private var topDomains: [DomainSummary] = []
    @State private var dailyCounts: [DailyVisitCount] = []
    @State private var hourlyCounts: [HourlyVisitCount] = []
    @State private var loadError: Error?
    @State private var isLoading = true  // Start true so skeleton shows immediately
    @State private var hasLoadedOnce = false
    @State private var availableBrowsers: [BrowserSource] = [.all]
    @State private var expandedDomains: Set<String> = []
    @State private var domainPages: [String: [PageSummary]] = [:]
    @State private var loadingDomains: Set<String> = []

    private let service: BrowsingHistoryServing = SQLiteBrowsingHistoryService()
    private let browserSettings = BrowserSettingsStore.shared
    
    /// Show skeleton only on initial load, not on subsequent filter changes
    private var showSkeleton: Bool {
        isLoading && !hasLoadedOnce
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // ─── Header ───
                headerSection

                if showSkeleton {
                    // ─── Skeleton loader during initial load ───
                    WebHistorySkeletonView()
                } else {
                    // ─── Metrics strip ───
                    metricsStrip

                    // ─── Error ───
                    if let loadError {
                        errorCard(loadError)
                    }

                    // ─── Tab content ───
                    tabContentSection
                }
            }
            .animation(.easeInOut(duration: 0.25), value: showSkeleton)
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task {
            // Move file system checks off main thread to avoid blocking navigation
            let (installed, enabled) = await Task.detached(priority: .userInitiated) { [service, browserSettings] in
                let installed = service.availableBrowsers()
                let enabled = browserSettings.enabledBrowsers(from: installed)
                return (installed, enabled)
            }.value
            
            availableBrowsers = enabled.isEmpty ? installed : enabled
            
            if !availableBrowsers.contains(browserFilter) {
                browserFilter = availableBrowsers.first ?? .all
            }
            await loadAll()
        }
        .onChange(of: filters.startDate) { _, _ in 
            domainPages.removeAll()
            expandedDomains.removeAll()
            Task { await loadAll() } 
        }
        .onChange(of: filters.endDate) { _, _ in 
            domainPages.removeAll()
            expandedDomains.removeAll()
            Task { await loadAll() } 
        }
        .onChange(of: browserFilter) { _, _ in 
            domainPages.removeAll()
            expandedDomains.removeAll()
            Task { await loadAll() } 
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Web History")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)
            }

            Spacer(minLength: 20)

            // Browser picker
            browserPicker
        }
    }

    private var browserPicker: some View {
        HStack(spacing: 6) {
            ForEach(availableBrowsers) { source in
                let isActive = browserFilter == source

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        browserFilter = source
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: source.systemImage)
                            .font(.system(size: 11, weight: .semibold))
                        Text(source.rawValue)
                            .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .monospaced))
                    }
                    .foregroundColor(isActive ? BrutalTheme.activeButtonText : BrutalTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
                .tint(isActive ? BrutalTheme.accent : .clear)
            }
        }
    }

    // MARK: - Metrics strip

    private var metricsStrip: some View {
        HStack(spacing: 12) {
            metricPill(
                icon: "globe",
                label: "Total Visits",
                value: "\(totalVisitCount)"
            )
            metricPill(
                icon: "link",
                label: "Domains",
                value: "\(topDomains.count)"
            )
            metricPill(
                icon: "chart.line.uptrend.xyaxis",
                label: "Daily Avg",
                value: dailyAvgString
            )
            metricPill(
                icon: "clock.fill",
                label: "Peak Hour",
                value: peakHourString
            )
        }
    }

    private var totalVisitCount: Int {
        dailyCounts.reduce(0) { $0 + $1.visitCount }
    }

    private var dailyAvgString: String {
        let days = max(dailyCounts.count, 1)
        let avg = Double(totalVisitCount) / Double(days)
        return String(format: "%.0f", avg)
    }

    private var peakHourString: String {
        guard let peak = hourlyCounts.max(by: { $0.visitCount < $1.visitCount }),
              peak.visitCount > 0 else { return "—" }
        let hour = peak.hour
        let suffix = hour >= 12 ? "PM" : "AM"
        let display = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(display)\(suffix)"
    }

    private func metricPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BrutalTheme.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(BrutalTheme.accentMuted)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        
    }

    // MARK: - Error card

    private func errorCard(_ error: Error) -> some View {
        let errorMessage = error.localizedDescription
        let isPermissionError = errorMessage.contains("Permission denied") || errorMessage.contains("Full Disk Access")
        
        return GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(BrutalTheme.warning)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text("UNABLE TO LOAD HISTORY")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.danger)
                        .tracking(1)
                    
                    if isPermissionError {
                        permissionErrorMessage(errorMessage)
                    } else {
                        Text(errorMessage)
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textSecondary)
                    }
                }

                Spacer()
            }
        }
    }
    
    private func permissionErrorMessage(_ message: String) -> some View {
        let settingsText = "System Settings → Privacy & Security"
        
        return HStack(spacing: 0) {
            // Split the message around "System Settings → Privacy & Security"
            if let range = message.range(of: settingsText) {
                Text(String(message[..<range.lowerBound]))
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)
                
                Button {
                    openFullDiskAccessSettings()
                } label: {
                    Text(settingsText)
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.accent)
                        .underline()
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                Text(String(message[range.upperBound...]))
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)
            } else {
                Text(message)
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)
            }
        }
    }
    
    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Tab content

    private var tabContentSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Tab picker — glass buttons
            HStack(spacing: 6) {
                ForEach(WebHistoryTab.allCases) { t in
                    let isActive = tab == t
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { tab = t }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: t.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                            Text(t.rawValue)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(isActive ? BrutalTheme.activeButtonText : BrutalTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .tint(isActive ? BrutalTheme.accent : .clear)
                }
                Spacer()
            }

            // Content
            switch tab {
            case .timeline:
                timelineSection
            case .domains:
                domainsSection
            case .activity:
                activitySection
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search bar — glass effect
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)

                TextField("Search URLs, titles, domains…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .onSubmit { Task { await loadVisits() } }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        Task { await loadVisits() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            

            // Visit list
            GlassCard {
                if visits.isEmpty && !isLoading {
                    Text("NO BROWSING HISTORY FOR THIS PERIOD.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    visitTable
                }
            }
        }
    }

    private var visitTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("TIME")
                    .frame(width: 70, alignment: .leading)
                Text("TITLE / URL")
                Spacer()
                Text("DOMAIN")
                    .frame(width: 160, alignment: .trailing)
                Text("SRC")
                    .frame(width: 36, alignment: .trailing)
            }
            .font(BrutalTheme.tableHeader)
            .foregroundColor(BrutalTheme.textTertiary)
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                VStack(spacing: 0) {
                    visitRow(visit, showDate: shouldShowDateHeader(at: index))

                    if index < visits.count - 1 {
                        Rectangle()
                            .fill(BrutalTheme.border)
                            .frame(height: 0.5)
                    }
                }
            }

            if visits.count >= 500 {
                Text("SHOWING LATEST 500 VISITS")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 12)
            }
        }
    }

    private func shouldShowDateHeader(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let current = Calendar.current.startOfDay(for: visits[index].visitTime)
        let previous = Calendar.current.startOfDay(for: visits[index - 1].visitTime)
        return current != previous
    }

    private func visitRow(_ visit: BrowsingVisit, showDate: Bool) -> some View {
        let timeFormatter = Self.timeFormatter
        let dateFormatter = Self.dateFormatter

        return VStack(alignment: .leading, spacing: 0) {
            if showDate {
                Text(dateFormatter.string(from: visit.visitTime).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.accent)
                    .tracking(1)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .padding(.horizontal, 4)
            }

            HStack(spacing: 0) {
                Text(timeFormatter.string(from: visit.visitTime))
                    .font(BrutalTheme.tableBody)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.title)
                        .font(BrutalTheme.tableBody)
                        .foregroundColor(BrutalTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(visit.url)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Text(visit.domain)
                    .font(BrutalTheme.tableBody)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .trailing)

                browserIcon(visit.browser)
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
    }

    private func browserIcon(_ browser: BrowserSource) -> some View {
        Image(systemName: browser.systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(BrutalTheme.textTertiary)
    }

    // MARK: - Top Domains

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Bar chart
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TOP DOMAINS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    topDomainsChart
                }
            }

            // Table
            GlassCard {
                if topDomains.isEmpty {
                    Text("NO DOMAIN DATA FOR THIS PERIOD.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    domainTable
                }
            }
        }
    }

    private var topDomainsChart: some View {
        let display = Array(topDomains.prefix(10))
        let maxCount = display.first?.visitCount ?? 1

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(display) { domain in
                HStack(spacing: 8) {
                    Text(domain.domain)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textPrimary)
                        .lineLimit(1)
                        .frame(width: 140, alignment: .trailing)

                    GeometryReader { geo in
                        let fraction = CGFloat(domain.visitCount) / CGFloat(max(maxCount, 1))
                        Rectangle()
                            .fill(BrutalTheme.accent)
                            .frame(width: geo.size.width * fraction, height: geo.size.height)
                    }
                    .frame(height: 16)

                    Text("\(domain.visitCount)")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(width: 44, alignment: .leading)
                }
            }
        }
        .frame(minHeight: CGFloat(display.count) * 24)
    }

    private var domainTable: some View {
        let totalVisits = topDomains.reduce(0) { $0 + $1.visitCount }

        return VStack(spacing: 0) {
            // Header
            HStack {
                Text("")
                    .frame(width: 20, alignment: .leading)
                Text("#")
                    .frame(width: 28, alignment: .leading)
                Text("DOMAIN")
                Spacer()
                Text("VISITS")
                    .frame(width: 64, alignment: .trailing)
                Text("%")
                    .frame(width: 52, alignment: .trailing)
                Text("LAST SEEN")
                    .frame(width: 90, alignment: .trailing)
            }
            .font(BrutalTheme.tableHeader)
            .foregroundColor(BrutalTheme.textTertiary)
            .tracking(0.5)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)

            Rectangle()
                .fill(BrutalTheme.borderStrong)
                .frame(height: 1)

            ForEach(Array(topDomains.enumerated()), id: \.element.id) { index, domain in
                let pct = totalVisits > 0 ? Double(domain.visitCount) / Double(totalVisits) * 100 : 0
                let isExpanded = expandedDomains.contains(domain.domain)
                let isLoadingPages = loadingDomains.contains(domain.domain)

                VStack(spacing: 0) {
                    // Main domain row (clickable)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toggleDomainExpansion(domain.domain)
                        }
                    } label: {
                        HStack(spacing: 0) {
                            // Expand/collapse indicator
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            
                            Text(String(format: "%02d", index + 1))
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 28, alignment: .leading)

                            Text(domain.domain)
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer(minLength: 8)

                            Text("\(domain.visitCount)")
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textPrimary)
                                .frame(width: 64, alignment: .trailing)

                            Text(String(format: "%.1f%%", pct))
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 52, alignment: .trailing)

                            Text(Self.shortDateFormatter.string(from: domain.lastVisitTime))
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 90, alignment: .trailing)
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Percentage bar
                    GeometryReader { geo in
                        Rectangle()
                            .fill(BrutalTheme.accentMuted)
                            .frame(width: geo.size.width * max(CGFloat(pct) / 100, 0), height: 3)
                    }
                    .frame(height: 3)
                    
                    // Expanded pages section
                    if isExpanded {
                        if isLoadingPages {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                Text("Loading pages...")
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                            .padding(.vertical, 12)
                            .padding(.leading, 48)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else if let pages = domainPages[domain.domain], !pages.isEmpty {
                            domainPagesSection(pages: pages)
                        } else {
                            Text("No page details available")
                                .font(BrutalTheme.captionMono)
                                .foregroundColor(BrutalTheme.textTertiary)
                                .padding(.vertical, 12)
                                .padding(.leading, 48)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if index < topDomains.count - 1 {
                        Rectangle()
                            .fill(BrutalTheme.border)
                            .frame(height: 0.5)
                    }
                }
            }
        }
    }
    
    // MARK: - Domain pages detail section
    
    private func domainPagesSection(pages: [PageSummary]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Pages header
            HStack {
                Text("PAGE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("VISITS")
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundColor(BrutalTheme.textTertiary)
            .tracking(0.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.leading, 36)
            .background(BrutalTheme.surfaceAlt.opacity(0.5))
            
            ForEach(pages) { page in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.title)
                                .font(BrutalTheme.captionMono)
                                .foregroundColor(BrutalTheme.textPrimary)
                                .lineLimit(1)
                            
                            Text(page.path)
                                .font(.system(size: 9, weight: .regular, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                                .lineLimit(1)
                        }
                        
                        Spacer(minLength: 8)
                        
                        Text("\(page.visitCount)")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .padding(.leading, 36)
                    
                    // Visit times for this page
                    if !page.visits.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(page.visits.prefix(10)) { visit in
                                    visitTimeChip(visit)
                                }
                                if page.visits.count > 10 {
                                    Text("+\(page.visits.count - 10) more")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.leading, 36)
                            .padding(.bottom, 6)
                        }
                    }
                    
                    Rectangle()
                        .fill(BrutalTheme.border.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.leading, 48)
                }
            }
        }
        .background(BrutalTheme.surface.opacity(0.3))
    }
    
    private func visitTimeChip(_ visit: PageVisit) -> some View {
        HStack(spacing: 4) {
            Text(Self.chipDateFormatter.string(from: visit.visitTime))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
            
            Text(Self.timeFormatter.string(from: visit.visitTime))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
            
            browserIcon(visit.browser)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(BrutalTheme.surfaceAlt)
        )
    }
    
    private func toggleDomainExpansion(_ domain: String) {
        if expandedDomains.contains(domain) {
            expandedDomains.remove(domain)
        } else {
            expandedDomains.insert(domain)
            // Load pages if not already loaded
            if domainPages[domain] == nil {
                Task { await loadPagesForDomain(domain) }
            }
        }
    }
    
    private func loadPagesForDomain(_ domain: String) async {
        loadingDomains.insert(domain)
        defer { loadingDomains.remove(domain) }
        
        do {
            let pages = try await service.fetchPagesForDomain(
                domain: domain,
                browser: browserFilter,
                startDate: filters.startDate,
                endDate: filters.endDate,
                limit: 50
            )
            domainPages[domain] = pages
        } catch {
            // Silently fail - user will see "No page details available"
            domainPages[domain] = []
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Daily trend chart
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DAILY VISITS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    if dailyCounts.isEmpty {
                        Text("NO DATA FOR THIS PERIOD.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        dailyTrendChart
                    }
                }
            }

            // Hourly distribution
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("HOURLY DISTRIBUTION")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    if hourlyCounts.isEmpty || hourlyCounts.allSatisfy({ $0.visitCount == 0 }) {
                        Text("NO DATA FOR THIS PERIOD.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        hourlyDistributionChart
                    }
                }
            }
        }
    }

    private var dailyTrendChart: some View {
        Chart(dailyCounts) { point in
            BarMark(
                x: .value("Date", point.date, unit: .day),
                y: .value("Visits", point.visitCount)
            )
            .foregroundStyle(BrutalTheme.accent)
            .cornerRadius(0)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(dailyCounts.count / 8, 1))) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Self.axisDateFormatter.string(from: date))
                            .font(BrutalTheme.captionMono)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(BrutalTheme.captionMono)
                    }
                }
                AxisGridLine()
            }
        }
        .frame(height: 200)
    }

    private var hourlyDistributionChart: some View {
        Chart(hourlyCounts) { point in
            BarMark(
                x: .value("Hour", point.hour),
                y: .value("Visits", point.visitCount)
            )
            .foregroundStyle(
                point.hour >= 9 && point.hour <= 17
                    ? BrutalTheme.accent
                    : BrutalTheme.accent.opacity(0.5)
            )
            .cornerRadius(0)
        }
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                AxisValueLabel {
                    if let h = value.as(Int.self) {
                        let label = h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h-12)p"
                        Text(label)
                            .font(BrutalTheme.captionMono)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(BrutalTheme.captionMono)
                    }
                }
                AxisGridLine()
            }
        }
        .frame(height: 180)
    }

    // MARK: - Data loading

    private func loadAll() async {
        isLoading = true
        defer { 
            isLoading = false
            hasLoadedOnce = true
        }

        do {
            loadError = nil
            let start = filters.startDate
            let end = filters.endDate
            let browser = browserFilter

            async let v = service.fetchVisits(
                browser: browser, startDate: start, endDate: end,
                searchText: searchText, limit: 500
            )
            async let d = service.fetchTopDomains(
                browser: browser, startDate: start, endDate: end, limit: 50
            )
            async let dc = service.fetchDailyVisitCounts(
                browser: browser, startDate: start, endDate: end
            )
            async let hc = service.fetchHourlyVisitCounts(
                browser: browser, startDate: start, endDate: end
            )

            visits = try await v
            topDomains = try await d
            dailyCounts = try await dc
            hourlyCounts = try await hc
        } catch {
            loadError = error
        }
    }

    private func loadVisits() async {
        do {
            loadError = nil
            visits = try await service.fetchVisits(
                browser: browserFilter,
                startDate: filters.startDate,
                endDate: filters.endDate,
                searchText: searchText,
                limit: 500
            )
        } catch {
            loadError = error
        }
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, MMM d"
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    private static let axisDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "M/d"
        return f
    }()
    
    private static let chipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()
}
