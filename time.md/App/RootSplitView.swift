import Observation
import SwiftUI

struct RootSplitView: View {
    let filters: GlobalFilterStore
    @Bindable var navigation: NavigationCoordinator
    @ObservedObject private var store = StoreManager.shared

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $navigation.sidebarVisibility) {
                List(selection: $navigation.selectedDestination) {
                    ForEach(NavigationSection.visibleSections) { section in
                        Section(section.rawValue) {
                            ForEach(NavigationDestination.allCases.filter { $0.section == section }) { destination in
                                let locked = destination.minimumTier > store.tier
                                Label {
                                    HStack {
                                        Text(destination.title)
                                            .font(.system(size: 13, weight: .semibold, design: .default))
                                        if locked {
                                            Spacer()
                                            Image(systemName: "lock.fill")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(BrutalTheme.textTertiary)
                                        }
                                    }
                                } icon: {
                                    Image(systemName: destination.systemImage)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(locked ? BrutalTheme.textTertiary : nil)
                                }
                                .tag(destination)
                            }
                        }
                    }
                }
                .navigationTitle("time.md")
                .listStyle(.sidebar)
                .toolbar(removing: .sidebarToggle)
            } detail: {
                VStack(spacing: 0) {
                    Group {
                        switch navigation.selectedDestination ?? .overview {
                        case .overview:
                            TimingOverviewView(filters: filters)
                        case .review:
                            if store.tier >= .base { TimingReviewView(filters: filters) }
                            else { MacPaywallView() }
                        case .details:
                            if store.tier >= .base { TimingDetailsView(filters: filters) }
                            else { MacPaywallView() }
                        case .projects:
                            if store.tier >= .base { TimingProjectsView(filters: filters) }
                            else { MacPaywallView() }
                        case .rules:
                            if store.tier >= .base { TimingRulesView(filters: filters) }
                            else { MacPaywallView() }
                        case .webHistory:
                            if store.tier >= .base { WebHistoryView(filters: filters) }
                            else { MacPaywallView() }
                        case .reports:
                            if store.tier >= .base { TimingReportsView(filters: filters) }
                            else { MacPaywallView() }
                        case .export:
                            if store.tier >= .base { ExportsView(filters: filters) }
                            else { MacPaywallView() }
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
            }
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        navigation.toggleSidebar()
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .help("Toggle Sidebar ⌘B")
                }
                ToolbarItem(placement: .primaryAction) {
                    GranularityPickerToolbar(filters: filters)
                }
            }

        }
    }

}

// MARK: - Settings

private struct SettingsScaffoldView: View {
    let filters: GlobalFilterStore
    @AppStorage("appNameDisplayMode") private var appNameDisplayModeRaw: String = AppNameDisplayMode.short.rawValue
    @AppStorage("insightTickerAutoScroll") private var insightTickerAutoScroll: Bool = true
    @AppStorage("showMenuBarItem") private var showMenuBarItem: Bool = true
    @AppStorage("enableMCPServer") private var enableMCPServer: Bool = false

    @ObservedObject private var store = StoreManager.shared
    @State private var browserSettings = BrowserSettingsStore.shared
    @State private var mcpStatus: MCPIntegrationService.Status = .inactive

    private var displayMode: AppNameDisplayMode {
        AppNameDisplayMode(rawValue: appNameDisplayModeRaw) ?? .short
    }

    var body: some View {
        let _ = filters

        ScrollView {
            VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
                Text("Settings")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                // ─── App Name Display ───
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(BrutalTheme.sectionLabel(1, "APP NAME DISPLAY"))
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1.5)

                        Text("Choose how app names appear throughout time.md.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineSpacing(3)

                        HStack(spacing: 8) {
                            ForEach(AppNameDisplayMode.allCases) { mode in
                                let isSelected = displayMode == mode
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
                                            .opacity(isSelected ? 0.85 : 0.7)
                                    }
                                    .foregroundColor(isSelected ? .white : BrutalTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isSelected ? BrutalTheme.accent : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
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
                        Text(BrutalTheme.sectionLabel(2, "INSIGHT TICKER"))
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

                // ─── Menu Bar ───
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(BrutalTheme.sectionLabel(3, "MENU BAR"))
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1.5)

                        Text("Show a menu bar icon for quick access to today's screen time.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineSpacing(3)

                        HStack(spacing: 16) {
                            Toggle(isOn: $showMenuBarItem) {
                                HStack(spacing: 8) {
                                    Image(systemName: showMenuBarItem ? "menubar.rectangle" : "menubar.arrow.up.rectangle")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(showMenuBarItem ? .green : .orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(showMenuBarItem ? "Visible" : "Hidden")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(BrutalTheme.textPrimary)
                                        
                                        Text(showMenuBarItem ? "Menu bar item shows today's screen time" : "Menu bar item is hidden")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(BrutalTheme.textTertiary)
                                    }
                                }
                            }
                            .toggleStyle(.switch)
                            .tint(.green)
                            
                            Spacer()
                        }

                        Text("The menu bar item displays your daily screen time and allows quick sync.")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // ─── Web Browsers ───
                browserSettingsSection

                settingsBlock(
                    number: 5,
                    title: "DATA SOURCE",
                    body: "Data loads from local normalized screentime.db",
                    footnote: "Category mappings saved at ~/Library/Application Support/time.md/category-mappings.db."
                )

                settingsBlock(
                    number: 6,
                    title: "CATEGORY MAPPING",
                    body: "Mappings are edited from the Apps & Categories view. Single source of truth — no conflicting state.",
                    footnote: nil
                )

                settingsBlock(
                    number: 7,
                    title: "PRIVACY",
                    body: "time.md is local-first. Your raw data never leaves this Mac.",
                    footnote: nil
                )

                // ─── Claude Code Integration (Pro) ───
                claudeCodeIntegrationSection

                // Device info
                deviceInfoSection
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
    }
    
    // MARK: - Browser Settings Section
    
    private var browserSettingsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(4, "WEB BROWSERS"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)
                
                Text("Choose which browsers to include in Web History tracking. Only installed browsers can be enabled.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)
                
                // Browser toggles grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 10) {
                    ForEach(browserSettings.allBrowsersStatus(), id: \.browser) { status in
                        browserToggleRow(
                            browser: status.browser,
                            isInstalled: status.isInstalled,
                            isEnabled: status.isEnabled
                        )
                    }
                }
                .frame(maxWidth: 500)
                
                // Summary of enabled browsers
                let enabledCount = browserSettings.allBrowsersStatus().filter { $0.isInstalled && $0.isEnabled }.count
                let installedCount = browserSettings.allBrowsersStatus().filter { $0.isInstalled }.count
                
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    Text("\(enabledCount) of \(installedCount) installed browser\(installedCount == 1 ? "" : "s") enabled for tracking")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func browserToggleRow(browser: BrowserSource, isInstalled: Bool, isEnabled: Bool) -> some View {
        HStack(spacing: 10) {
            // Browser icon
            Image(systemName: browser.systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(isInstalled ? (isEnabled ? BrutalTheme.accent : BrutalTheme.textSecondary) : BrutalTheme.textTertiary.opacity(0.5))
                .frame(width: 24, height: 24)
            
            // Browser name and status
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isInstalled ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
                
                Text(isInstalled ? (isEnabled ? "Tracking enabled" : "Tracking disabled") : "Not installed")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isInstalled ? (isEnabled ? .green : .orange) : BrutalTheme.textTertiary)
            }
            
            Spacer()
            
            // Toggle
            if isInstalled {
                Toggle("", isOn: Binding(
                    get: { browserSettings.isEnabled(browser) },
                    set: { browserSettings.setEnabled(browser, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .tint(.green)
                .labelsHidden()
            } else {
                // Show "N/A" for uninstalled browsers
                Text("N/A")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrutalTheme.surfaceAlt.opacity(0.5))
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isInstalled ? BrutalTheme.surface.opacity(0.5) : BrutalTheme.surface.opacity(0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isInstalled && isEnabled ? BrutalTheme.accent.opacity(0.3) : BrutalTheme.border.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Claude Code Integration Section

    private var claudeCodeIntegrationSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(8, "CLAUDE CODE INTEGRATION"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Text("Expose your time.md data to Claude Code as an MCP server. When enabled, time.md registers a bundled server with Claude Code so you can query your screen time data through natural conversation without exporting files.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)

                if store.tier >= .pro {
                    HStack(spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { enableMCPServer },
                            set: { newValue in
                                enableMCPServer = newValue
                                if newValue {
                                    mcpStatus = MCPIntegrationService.shared.register()
                                } else {
                                    mcpStatus = MCPIntegrationService.shared.unregister()
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: enableMCPServer ? "terminal.fill" : "terminal")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(enableMCPServer ? .green : .orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(enableMCPServer ? "Enabled" : "Disabled")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(BrutalTheme.textPrimary)

                                    Text(enableMCPServer ? "Claude Code can query your data" : "Toggle on to enable querying via Claude Code")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(.green)

                        Spacer()
                    }

                    mcpStatusFooter

                    Text("Writes to ~/.claude.json. Restart Claude Code after enabling to pick up the new tools.")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                } else {
                    UpgradeView(requiredTier: .pro, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            guard store.tier >= .pro else { return }
            mcpStatus = MCPIntegrationService.shared.currentStatus()
            if enableMCPServer, case .registered = mcpStatus {
                // Already registered — nothing to do.
            } else if enableMCPServer, MCPIntegrationService.shared.bundledBinaryPath != nil {
                mcpStatus = MCPIntegrationService.shared.register()
            }
        }
    }

    @ViewBuilder
    private var mcpStatusFooter: some View {
        switch mcpStatus {
        case .inactive:
            EmptyView()
        case .registered(let path):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(verbatim: path)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        case .missingBinary:
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Bundled timemd-mcp binary not found. Rebuild time.md to include it.")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange)
            }
        case .error(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(.red)
                Text(verbatim: message)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Device Info Section

    private var deviceInfoSection: some View {
        let device = DeviceInfo.current()
        
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(9, "THIS DEVICE"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)
                
                HStack(spacing: 12) {
                    Image(systemName: device.platform.icon)
                        .font(.system(size: 24))
                        .foregroundColor(BrutalTheme.accent)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: device.name)
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
    
    private func settingsBlock(number: Int, title: String, body: LocalizedStringKey, footnote: LocalizedStringKey?) -> some View {
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
        HStack(spacing: 12) {
            // Time Navigation
            HStack(spacing: 4) {
                // Previous period
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filters.stepBackward()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BrutalTheme.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Previous \(filters.granularity.title)")
                
                // Period label / Today button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filters.goToToday()
                    }
                } label: {
                    Text(LocalizedStringKey(filters.periodLabel))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(filters.isCurrentPeriod ? BrutalTheme.textPrimary : BrutalTheme.accent)
                        .frame(minWidth: 100)
                }
                .buttonStyle(.plain)
                .help(filters.isCurrentPeriod ? "Viewing current period" : "Jump to today")
                
                // Next period
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        filters.stepForward()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(filters.isCurrentPeriod ? BrutalTheme.textTertiary.opacity(0.5) : BrutalTheme.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(filters.isCurrentPeriod)
                .help(filters.isCurrentPeriod ? "Already at current period" : "Next \(filters.granularity.title)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(BrutalTheme.surface.opacity(0.5))
            )
            
            Divider()
                .frame(height: 20)
            
            // Granularity picker
            HStack(spacing: 12) {
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
}
