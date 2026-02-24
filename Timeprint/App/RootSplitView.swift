import Observation
import SwiftUI

struct RootSplitView: View {
    let filters: GlobalFilterStore
    @Bindable var navigation: NavigationCoordinator

    @State private var isCalendarExpanded = false

    var body: some View {
        ZStack {
            NavigationSplitView {
                List(selection: $navigation.selectedDestination) {
                    ForEach(NavigationSection.visibleSections) { section in
                        Section(section.rawValue) {
                            ForEach(NavigationDestination.allCases.filter { $0.section == section }) { destination in
                                Label {
                                    Text(destination.title)
                                        .font(.system(size: 13, weight: .semibold, design: .default))
                                } icon: {
                                    Image(systemName: destination.systemImage)
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .tag(destination)
                            }
                        }
                    }
                }
                .navigationTitle("Timeprint")
                .listStyle(.sidebar)
            } detail: {
                VStack(spacing: 0) {
                    Group {
                        switch navigation.selectedDestination ?? .overview {
                        case .overview:
                            OverviewView(filters: filters)
                        case .calendar:
                            AppleCalendarView(filters: filters, isExpanded: $isCalendarExpanded)
                        case .trends:
                            TrendsView(filters: filters)
                        case .appsCategories:
                            AppsCategoriesView(filters: filters)
                        case .sessions:
                            SessionsView(filters: filters)
                        case .heatmap:
                            DistractingHoursView(filters: filters)
                        case .focus:
                            FocusStreaksView(filters: filters)
                        case .rawSessions:
                            // Raw sessions is export-only, redirect to exports
                            ExportsView(filters: filters)
                        case .webHistory:
                            WebHistoryView(filters: filters)
                        case .exports:
                            ExportsView(filters: filters)
                        case .settings:
                            SettingsScaffoldView(filters: filters)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .onChange(of: filters.granularity) { _, newValue in
                    filters.adjustDateRange(for: newValue)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        GranularityPickerToolbar(filters: filters)
                    }
                }
            }

            // Expanded calendar overlay
            if isCalendarExpanded {
                AppleCalendarView(filters: filters, isExpanded: $isCalendarExpanded)
                    .background(CalendarColors.background)
            }
        }
    }
}

// MARK: - Settings

private struct SettingsScaffoldView: View {
    let filters: GlobalFilterStore
    @Environment(\.appEnvironment) private var appEnvironment
    @AppStorage("appNameDisplayMode") private var appNameDisplayModeRaw: String = AppNameDisplayMode.short.rawValue
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false
    @AppStorage("insightTickerAutoScroll") private var insightTickerAutoScroll: Bool = true
    
    @State private var isSyncing = false
    @State private var lastSyncDate: Date?
    @State private var syncError: String?
    @State private var showSyncSuccess = false

    private var displayMode: AppNameDisplayMode {
        AppNameDisplayMode(rawValue: appNameDisplayModeRaw) ?? .short
    }
    
    private var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var body: some View {
        let _ = filters

        ScrollView {
            VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                // ─── iCloud Sync ───
                syncSection

                // ─── App Name Display ───
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(BrutalTheme.sectionLabel(2, "APP NAME DISPLAY"))
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1.5)

                        Text("Choose how app names appear throughout Timeprint.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineSpacing(3)

                        HStack(spacing: 8) {
                            ForEach(AppNameDisplayMode.allCases) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        appNameDisplayModeRaw = mode.rawValue
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mode.title)
                                            .font(BrutalTheme.captionMono)
                                            .tracking(1)
                                        Text("e.g. \(mode.description)")
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .opacity(0.7)
                                    }
                                    .foregroundColor(displayMode == mode ? .white : BrutalTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                }
                                .buttonStyle(.glass)
                                .tint(displayMode == mode ? BrutalTheme.accent : .clear)
                            }
                        }
                        .frame(maxWidth: 420)

                        Text("Short name extracts the last component of a bundle identifier (com.apple.Safari → Safari).")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ─── Insight Ticker ───
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(BrutalTheme.sectionLabel(3, "INSIGHT TICKER"))
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1.5)

                        Text("Control how the insight bar scrolls on the Overview screen.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineSpacing(3)

                        HStack(spacing: 16) {
                            Toggle(isOn: $insightTickerAutoScroll) {
                                HStack(spacing: 8) {
                                    Image(systemName: insightTickerAutoScroll ? "play.fill" : "hand.draw.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(insightTickerAutoScroll ? .green : .orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(insightTickerAutoScroll ? "Auto-scroll" : "Manual scroll")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(BrutalTheme.textPrimary)
                                        
                                        Text(insightTickerAutoScroll ? "Insights scroll continuously, pause on hover" : "Drag to scroll through insights")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(BrutalTheme.textTertiary)
                                    }
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(.green)
                            
                            Spacer()
                        }

                        Text("When auto-scroll is enabled, hover over the ticker to pause it.")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                settingsBlock(
                    number: 4,
                    title: "DATA SOURCE",
                    body: "Data loads from local SQLite only (normalized screentime.db or knowledgeC.db fallback).",
                    footnote: "Category mappings saved at ~/Library/Application Support/Timeprint/category-mappings.db."
                )

                settingsBlock(
                    number: 5,
                    title: "CATEGORY MAPPING",
                    body: "Mappings are edited from the Apps & Categories view. Single source of truth — no conflicting state.",
                    footnote: nil
                )

                settingsBlock(
                    number: 6,
                    title: "PRIVACY",
                    body: "Timeprint is local-first. Your raw data stays on this machine. iCloud sync only shares aggregated daily summaries.",
                    footnote: nil
                )
                
                // Device info
                deviceInfoSection
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
    }
    
    // MARK: - Sync Section
    
    private var syncSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(1, "ICLOUD SYNC"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)
                
                Text("Sync your screen time data across devices. View combined usage from your Mac, iPhone, and iPad in one place.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)
                
                HStack(spacing: 16) {
                    // Status indicator
                    HStack(spacing: 8) {
                        Image(systemName: iCloudAvailable ? "icloud.fill" : "icloud.slash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(iCloudAvailable ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(iCloudAvailable ? "iCloud Available" : "iCloud Unavailable")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(BrutalTheme.textPrimary)
                            
                            if let lastSync = lastSyncDate {
                                Text("Last sync: \(TimeFormatters.relativeDate(lastSync))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Sync button
                    Button {
                        Task { await performSync() }
                    } label: {
                        HStack(spacing: 6) {
                            if isSyncing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(isSyncing ? "Syncing..." : "Sync Now")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .disabled(!iCloudAvailable || isSyncing)
                }
                
                // Success/Error feedback
                if showSyncSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Sync complete!")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                if let error = syncError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
                
                Text("Only aggregated daily summaries are synced. Raw session data stays local.")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Device Info Section
    
    private var deviceInfoSection: some View {
        let device = DeviceInfo.current()
        
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(7, "THIS DEVICE"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)
                
                HStack(spacing: 12) {
                    Image(systemName: device.platform.icon)
                        .font(.system(size: 24))
                        .foregroundColor(BrutalTheme.accent)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        
                        Text("\(device.model) • \(device.platform.displayName) \(device.osVersion)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textSecondary)
                    }
                }
                
                Text("Device ID: \(device.id.prefix(8))...")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Actions
    
    private func performSync() async {
        guard let syncCoordinator = appEnvironment.syncCoordinator else { return }
        
        isSyncing = true
        syncError = nil
        showSyncSuccess = false
        
        do {
            try await syncCoordinator.performSync()
            lastSyncDate = Date()
            withAnimation {
                showSyncSuccess = true
            }
            
            // Hide success after 3 seconds
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                showSyncSuccess = false
            }
        } catch {
            syncError = error.localizedDescription
        }
        
        isSyncing = false
    }

    private func settingsBlock(number: Int, title: String, body: String, footnote: String?) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(number, title))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Text(body)
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)

                if let footnote {
                    Text(footnote)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Granularity Picker Toolbar

private struct GranularityPickerToolbar: View {
    let filters: GlobalFilterStore

    var body: some View {
        HStack(spacing: 16) {
            ForEach(TimeGranularity.allCases) { granularity in
                let isActive = filters.granularity == granularity

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filters.granularity = granularity
                    }
                } label: {
                    Text(granularity.title)
                        .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
