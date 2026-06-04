import SwiftUI

struct BlockingView: View {
    @State private var viewModel = BlockingViewModel()
    @State private var newTargetType: BlockTargetType = .domain
    @State private var newTargetValue = ""
    @State private var newDisplayName = ""
    @State private var diagnosticsReport: BlockingDiagnosticsReport?
    @State private var helperSetupStatus: String?
    @State private var bulkActionStatus: String?
    @State private var isInstallingHelper = false
    @State private var isRunningBulkAction = false

    private let diagnosticsService = BlockingDiagnosticsService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                addBlockCard
                blockListCard
                if shouldShowHelperCard {
                    helperStatusCard
                }
                bulkActionsCard
            }
        }
        .scrollIndicators(.never)
        .task {
            await reloadBlockingState(reconcileDomains: true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocking")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text("Simple on/off blocks for distracting websites and apps.")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                Spacer()
                Button {
                    Task { await reloadBlockingState(reconcileDomains: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.danger)
                    .padding(.top, 8)
            }
        }
    }

    private var addBlockCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(BrutalTheme.sectionLabel(1, "ADD A BLOCK"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Picker("Block type", selection: $newTargetType) {
                    Text("Website").tag(BlockTargetType.domain)
                    Text("App").tag(BlockTargetType.app)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(targetPlaceholder)
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                        TextField(targetPlaceholder, text: $newTargetValue)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(minWidth: 260)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Name (optional)")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                        TextField("Display name", text: $newDisplayName)
                            .textFieldStyle(.roundedBorder)
                    }
                    .frame(minWidth: 220)

                    Button {
                        addBlock()
                    } label: {
                        Label("Add & block", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTargetValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 18)
                }

                Text("Blocks take effect immediately. Turn the switch off when you want the website or app to be viewable again.")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
            }
        }
    }

    private var blockListCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(BrutalTheme.sectionLabel(2, "BLOCKS"))
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1.5)
                    Spacer()
                    Text("On = blocked • Off = viewable")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                if blockRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No blocks yet")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        Text(viewModel.emptyStateMessage)
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(blockRows) { row in
                        blockRow(row)
                    }
                }
            }
        }
    }

    private var blockRows: [BlockingRuleRow] {
        viewModel.ruleRows.filter { row in
            row.rule.target.type == .domain || row.rule.target.type == .app
        }
    }

    private func blockRow(_ row: BlockingRuleRow) -> some View {
        HStack(spacing: 12) {
            targetIcon(row.rule.target.type)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.targetLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text(row.rule.enabled ? "BLOCKED" : "VIEWABLE")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(row.rule.enabled ? .white : BrutalTheme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(row.rule.enabled ? BrutalTheme.warning : BrutalTheme.surface.opacity(0.7)))
                }
                Text(blockDescription(for: row))
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
            }

            Spacer()

            Toggle(row.rule.enabled ? "On" : "Off", isOn: Binding(
                get: { row.rule.enabled },
                set: { enabled in setBlock(row.rule, enabled: enabled) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button(role: .destructive) {
                deleteBlock(row.rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete block")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(BrutalTheme.surface.opacity(0.4)))
        .contextMenu {
            Button(row.rule.enabled ? "Turn off" : "Turn on") { setBlock(row.rule, enabled: !row.rule.enabled) }
            Button("Delete", role: .destructive) { deleteBlock(row.rule) }
        }
    }

    private func blockDescription(for row: BlockingRuleRow) -> String {
        guard row.rule.enabled else { return "Allowed. Switch on to block it again." }
        switch row.rule.target.type {
        case .domain:
            return "Website is not viewable until you switch this off."
        case .app:
            return "App is hidden when opened until you switch this off."
        case .category:
            return "Category is blocked until you switch this off."
        }
    }

    private var shouldShowHelperCard: Bool {
        if helperSetupStatus != nil { return true }
        switch viewModel.helperUIState {
        case .notNeeded: return false
        case .healthy, .notInstalled, .needsUpgrade, .unhealthy: return true
        }
    }

    private var helperStatusCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: helperIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(helperColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Website blocking helper")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text(helperMessage)
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if helperShowsSetupButton {
                        HStack(spacing: 10) {
                            Button(helperSetupButtonTitle) {
                                installOrUpgradeDomainHelper()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isInstallingHelper)

                            if isInstallingHelper {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }

                    if let helperSetupStatus {
                        Text(helperSetupStatus)
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
        }
    }

    private var bulkActionsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safety")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textPrimary)
                        Text(diagnosticsSummary)
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textSecondary)
                    }
                    Spacer()
                    Button("Run diagnostics") {
                        Task { await loadDiagnostics() }
                    }
                    .buttonStyle(.bordered)
                    Button("Turn off all blocks", role: .destructive) {
                        turnOffAllBlocks()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningBulkAction)
                }

                if let bulkActionStatus {
                    Text(bulkActionStatus)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }
            }
        }
    }

    private var diagnosticsSummary: String {
        guard let diagnosticsReport else {
            return "Blocks are controlled by their switches. Diagnostics can verify helper and recovery state."
        }
        switch diagnosticsReport.overallSeverity {
        case .healthy:
            return "Blocking diagnostics are healthy. \(diagnosticsReport.activeBlockCount) block(s) are on."
        case .degraded:
            return "Diagnostics found a helper or recovery issue. Website blocks may need setup or repair."
        case .broken:
            return "Diagnostics found a broken blocking state that needs attention."
        }
    }

    private var helperIcon: String {
        switch viewModel.helperUIState {
        case .notNeeded: return "checkmark.circle"
        case .healthy: return "lock.shield.fill"
        case .notInstalled: return "lock.open.trianglebadge.exclamationmark"
        case .needsUpgrade: return "arrow.triangle.2.circlepath"
        case .unhealthy: return "exclamationmark.triangle.fill"
        }
    }

    private var helperColor: Color {
        switch viewModel.helperUIState {
        case .notNeeded, .healthy: return BrutalTheme.positive
        case .notInstalled, .needsUpgrade: return BrutalTheme.warning
        case .unhealthy: return BrutalTheme.danger
        }
    }

    private var helperMessage: String {
        switch viewModel.helperUIState {
        case .notNeeded:
            return "No website blocks are on. App blocking runs locally through frontmost-app observation."
        case .healthy:
            return "Website blocks are ready. The helper will make blocked websites unviewable until their switch is turned off."
        case .notInstalled:
            return "Website blocks are on, but system-wide website enforcement needs one-time helper setup."
        case .needsUpgrade:
            return "The website blocking helper should be upgraded before enforcing website blocks."
        case let .unhealthy(message):
            return "Helper reported a problem: \(message)"
        }
    }

    private var helperShowsSetupButton: Bool {
        switch viewModel.helperUIState {
        case .notInstalled, .needsUpgrade:
            return true
        case .notNeeded, .healthy, .unhealthy:
            return false
        }
    }

    private var helperSetupButtonTitle: String {
        if case .needsUpgrade = viewModel.helperUIState { return "Upgrade helper" }
        return "Set up helper once"
    }

    private var targetPlaceholder: String {
        switch newTargetType {
        case .domain: return "example.com"
        case .app: return "Bundle ID or app name"
        case .category: return "Category name"
        }
    }

    private func addBlock() {
        do {
            viewModel.draft = BlockingRuleDraft(
                targetType: newTargetType,
                targetValue: newTargetValue,
                displayName: newDisplayName,
                enabled: true,
                enforcementMode: newTargetType == .domain ? .domainNetwork : .appFocus
            )
            let savedRule = try viewModel.saveDraft()
            newTargetValue = ""
            newDisplayName = ""
            viewModel.resetDraft(type: newTargetType)
            afterRuleChange(affectedDomain: savedRule.target.type == .domain)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func setBlock(_ rule: BlockRule, enabled: Bool) {
        do {
            try viewModel.toggleRule(rule, enabled: enabled)
            afterRuleChange(affectedDomain: rule.target.type == .domain)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func deleteBlock(_ rule: BlockRule) {
        do {
            try viewModel.deleteRule(id: rule.id)
            afterRuleChange(affectedDomain: rule.target.type == .domain)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func turnOffAllBlocks() {
        isRunningBulkAction = true
        do {
            try viewModel.turnOffAllBlocks()
            bulkActionStatus = "All blocks are off. Websites and apps are viewable again."
        } catch {
            bulkActionStatus = error.localizedDescription
        }
        Task {
            await reconcileDomainBlocks()
            await reloadBlockingState()
            isRunningBulkAction = false
        }
    }

    private func afterRuleChange(affectedDomain: Bool) {
        Task {
            if affectedDomain {
                await reconcileDomainBlocks()
                await reloadBlockingState()
            } else {
                await loadDiagnostics()
            }
        }
    }

    private func installOrUpgradeDomainHelper() {
        isInstallingHelper = true
        helperSetupStatus = "macOS will ask once so time.md can install its website blocking helper."
        Task {
            do {
                _ = try await PrivilegedDomainBlockHelperClient.shared.installOrUpgrade(withConsent: .approvedForDomainBlocking)
                helperSetupStatus = "Helper installed. Website blocks now apply without another password prompt."
                await reconcileDomainBlocks()
            } catch {
                helperSetupStatus = error.localizedDescription
            }
            isInstallingHelper = false
            await reloadBlockingState()
        }
    }

    private func reloadBlockingState(reconcileDomains: Bool = false) async {
        viewModel = await viewModel.loaded()
        if reconcileDomains {
            await reconcileDomainBlocks()
            viewModel = await viewModel.loaded()
        }
        await loadDiagnostics()
    }

    private func reconcileDomainBlocks() async {
        do {
            _ = try await DomainBlockEnforcer(helper: PrivilegedDomainBlockHelperClient.shared).reconcileActiveDomainBlocks(now: Date())
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func loadDiagnostics() async {
        diagnosticsReport = await diagnosticsService.report()
    }

    private func targetIcon(_ type: BlockTargetType) -> some View {
        Image(systemName: {
            switch type {
            case .domain: return "globe"
            case .app: return "app.badge"
            case .category: return "square.grid.2x2"
            }
        }())
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(BrutalTheme.accent)
        .frame(width: 26, height: 26)
        .background(Circle().fill(BrutalTheme.accentMuted))
    }
}

#Preview {
    BlockingView()
        .padding()
        .frame(width: 900, height: 720)
}
