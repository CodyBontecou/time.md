import AppKit
import Observation
import SwiftUI

struct RootSplitView: View {
    let filters: GlobalFilterStore
    @Bindable var navigation: NavigationCoordinator

    var body: some View {
        ZStack {
            NavigationSplitView(columnVisibility: $navigation.sidebarVisibility) {
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
                            TimingReviewView(filters: filters)
                        case .details:
                            TimingDetailsView(filters: filters)
                        case .projects:
                            TimingProjectsView(filters: filters)
                        case .rules:
                            TimingRulesView(filters: filters)
                        case .webHistory:
                            WebHistoryView(filters: filters)
                        case .reports:
                            TimingReportsView(filters: filters)
                        case .export:
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
    @AppStorage(AppVisibilityMode.storageKey) private var visibilityModeRaw: String = AppVisibilityMode.dockAndMenuBar.rawValue

    private var visibilityMode: AppVisibilityMode {
        AppVisibilityMode(rawValue: visibilityModeRaw) ?? .dockAndMenuBar
    }

    @State private var browserSettings = BrowserSettingsStore.shared
    @State private var mcpStatuses: [MCPIntegrationService.Agent: MCPIntegrationService.Status] = [:]
    @State private var mcpSnippetCopied: Bool = false
    @State private var mcpAvailableTools: [MCPIntegrationService.ToolInfo] = []
    @State private var mcpDisabledTools: Set<String> = []
    @State private var mcpToolsExpanded: Bool = false

    private var displayMode: AppNameDisplayMode {
        AppNameDisplayMode(rawValue: appNameDisplayModeRaw) ?? .short
    }

    private var visibilityFootnote: String {
        switch visibilityMode {
        case .dockAndMenuBar:
            return "Default. Click \u{201C}Open time.md\u{201D} from the menu bar or use Cmd-Tab."
        case .menuBarOnly:
            return "No Dock icon or Cmd-Tab entry. Click the menu bar item to reveal the window."
        case .dockOnly:
            return "Use the Dock icon or Cmd-Tab to bring time.md forward."
        case .hidden:
            return "Fully hidden. Reopen time.md from Spotlight, Finder, or Launchpad to access it again."
        }
    }

    @ViewBuilder
    private func visibilityModeRow(_ mode: AppVisibilityMode) -> some View {
        let isSelected = visibilityMode == mode
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                visibilityModeRaw = mode.rawValue
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : BrutalTheme.textSecondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isSelected ? .white : BrutalTheme.textPrimary)
                    Text(mode.summary)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(isSelected ? Color.white.opacity(0.85) : BrutalTheme.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? BrutalTheme.accent : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

                // ─── Visibility ───
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(BrutalTheme.sectionLabel(3, "VISIBILITY"))
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1.5)

                        Text("Choose where time.md appears. macOS controls the Dock icon and Cmd-Tab entry together.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineSpacing(3)

                        VStack(spacing: 8) {
                            ForEach(AppVisibilityMode.allCases) { mode in
                                visibilityModeRow(mode)
                            }
                        }

                        Text(visibilityFootnote)
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

                // ─── MCP Integration ───
                mcpIntegrationSection

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
    
    // MARK: - MCP Integration Section

    private var mcpIntegrationSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(8, "MCP INTEGRATION"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Text("Expose your time.md data to any MCP-compatible coding agent. The bundled timemd-mcp server speaks standard MCP, so you can query your screen time data through natural conversation without exporting files.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)

                if MCPIntegrationService.shared.bundledBinaryPath == nil {
                    mcpMissingBinaryRow
                } else {
                    mcpQuickInstallRows
                    mcpToolPickerSection
                    mcpBinaryPathRow
                    mcpManualConfigBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            refreshMCPStatuses()
            mcpAvailableTools = MCPIntegrationService.shared.availableTools()
            mcpDisabledTools = MCPIntegrationService.shared.disabledTools()
        }
    }

    // MARK: - MCP tool picker

    private var mcpToolPickerSection: some View {
        let total = mcpAvailableTools.count
        let enabled = total - mcpDisabledTools.intersection(mcpAvailableTools.map(\.name)).count

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    mcpToolsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(BrutalTheme.textSecondary)
                        .rotationEffect(.degrees(mcpToolsExpanded ? 90 : 0))

                    Text("TOOLS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(BrutalTheme.textTertiary)

                    Text("\(enabled) of \(total) enabled")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if mcpToolsExpanded {
                mcpToolPickerControls
                mcpToolPickerList
            }
        }
    }

    private var mcpToolPickerControls: some View {
        HStack(spacing: 8) {
            Button {
                applyDisabledTools([])
            } label: {
                Text("All on")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrutalTheme.surface.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)

            Button {
                applyDisabledTools(Set(mcpAvailableTools.map(\.name)))
            } label: {
                Text("All off")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(BrutalTheme.surface.opacity(0.6))
                    )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var mcpToolPickerList: some View {
        VStack(spacing: 4) {
            ForEach(mcpAvailableTools) { tool in
                mcpToolRow(tool)
            }
        }
    }

    private func mcpToolRow(_ tool: MCPIntegrationService.ToolInfo) -> some View {
        let isEnabled = !mcpDisabledTools.contains(tool.name)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(isEnabled ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)

                Text(tool.description)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { newValue in
                    var next = mcpDisabledTools
                    if newValue {
                        next.remove(tool.name)
                    } else {
                        next.insert(tool.name)
                    }
                    applyDisabledTools(next)
                }
            ))
            .toggleStyle(.switch)
            .tint(.green)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(BrutalTheme.surface.opacity(isEnabled ? 0.5 : 0.2))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(BrutalTheme.border.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private func applyDisabledTools(_ next: Set<String>) {
        mcpDisabledTools = next
        let updates = MCPIntegrationService.shared.setDisabledTools(next)
        for (agent, status) in updates {
            mcpStatuses[agent] = status
        }
    }

    private var mcpQuickInstallRows: some View {
        VStack(spacing: 6) {
            Text("QUICK INSTALL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(BrutalTheme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            ForEach(MCPIntegrationService.Agent.allCases) { agent in
                mcpAgentRow(agent)
            }
        }
    }

    private func mcpAgentRow(_ agent: MCPIntegrationService.Agent) -> some View {
        let status = mcpStatuses[agent] ?? .inactive
        let isRegistered: Bool = {
            if case .registered = status { return true }
            return false
        }()

        return HStack(spacing: 12) {
            Image(systemName: isRegistered ? "terminal.fill" : "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isRegistered ? .green : BrutalTheme.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)

                mcpAgentStatusLabel(agent: agent, status: status)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isRegistered },
                set: { newValue in
                    if newValue {
                        mcpStatuses[agent] = MCPIntegrationService.shared.register(agent: agent)
                    } else {
                        mcpStatuses[agent] = MCPIntegrationService.shared.unregister(agent: agent)
                    }
                }
            ))
            .toggleStyle(.switch)
            .tint(.green)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BrutalTheme.surface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isRegistered ? BrutalTheme.accent.opacity(0.3) : BrutalTheme.border.opacity(0.3), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func mcpAgentStatusLabel(
        agent: MCPIntegrationService.Agent,
        status: MCPIntegrationService.Status
    ) -> some View {
        switch status {
        case .registered:
            Text("Registered · \(agent.displayConfigPath)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.green)
                .lineLimit(1)
                .truncationMode(.middle)
        case .inactive:
            Text("Writes to \(agent.displayConfigPath)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .missingBinary:
            Text("timemd-mcp binary missing")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.orange)
        case .error(let message):
            Text(verbatim: message)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.red)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    @ViewBuilder
    private var mcpBinaryPathRow: some View {
        if let path = MCPIntegrationService.shared.bundledBinaryPath {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(verbatim: path)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var mcpManualConfigBlock: some View {
        if let snippet = MCPIntegrationService.shared.configSnippet() {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("MANUAL CONFIG")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(BrutalTheme.textTertiary)

                    Spacer()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(snippet, forType: .string)
                        mcpSnippetCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            mcpSnippetCopied = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mcpSnippetCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                            Text(mcpSnippetCopied ? "Copied" : "Copy")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(mcpSnippetCopied ? .green : BrutalTheme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(BrutalTheme.surface.opacity(0.6))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Text("For agents we don't auto-install (Zed, Cline, Continue, Codex, etc.), paste this into their MCP config:")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)

                ScrollView(.horizontal, showsIndicators: false) {
                    Text(verbatim: snippet)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(BrutalTheme.border.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.top, 4)
        }
    }

    private var mcpMissingBinaryRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text("Bundled timemd-mcp binary not found. Rebuild time.md to include it.")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.orange)
        }
    }

    private func refreshMCPStatuses() {
        var next: [MCPIntegrationService.Agent: MCPIntegrationService.Status] = [:]
        for agent in MCPIntegrationService.Agent.allCases {
            next[agent] = MCPIntegrationService.shared.status(for: agent)
        }
        mcpStatuses = next
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
