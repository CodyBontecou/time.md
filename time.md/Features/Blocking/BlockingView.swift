import Combine
import SwiftUI

struct BlockingView: View {
    @State private var viewModel = BlockingViewModel()
    @State private var selectedType: BlockTargetType = .domain
    @State private var diagnosticsReport: BlockingDiagnosticsReport?
    @State private var recoveryStatus: String?
    @State private var isRunningRecovery = false
    private let diagnosticsService = BlockingDiagnosticsService()
    private let recoveryService = BlockingRecoveryService()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                helperStatusCard
                safetyRecoveryCard
                activeBlocksSection
                HStack(alignment: .top, spacing: 20) {
                    rulesSection
                        .frame(maxWidth: .infinity)
                    editorSection
                        .frame(width: 340)
                }
            }
        }
        .scrollIndicators(.never)
        .task {
            viewModel = await viewModel.loaded()
            await loadDiagnostics()
        }
        .onReceive(refreshTimer) { _ in
            try? viewModel.clearExpiredBlocks()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Blocking")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text("Create exponential cooldowns for websites, apps, and categories.")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                Spacer()
                Button {
                    Task {
                        viewModel = await viewModel.loaded()
                        await loadDiagnostics()
                    }
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

    private var helperStatusCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: helperIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(helperColor)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Domain blocking helper")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text(helperMessage)
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if case .notInstalled = viewModel.helperUIState {
                        Text("Domain rules can be created now, but website enforcement requires explicit admin approval before time.md writes its owned /etc/hosts block and pf anchor.")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
            }
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
            return "No active domain-network rules. App and category enforcement runs locally through frontmost-app observation."
        case .healthy:
            return "Helper looks healthy. time.md will only reconcile its owned hosts marker block and pf anchor."
        case .notInstalled:
            return "Helper is not installed or not reachable. Website rules are saved but may not be enforced yet."
        case .needsUpgrade:
            return "Helper version differs from the app and should be upgraded before enforcing website blocks."
        case let .unhealthy(message):
            return "Helper reported a problem: \(message)"
        }
    }

    private var safetyRecoveryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Safety & recovery")
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
                }

                if let recoveryStatus {
                    Text(recoveryStatus)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                if let diagnosticsReport {
                    ForEach(diagnosticsReport.checks.prefix(4)) { check in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: diagnosticIcon(for: check.severity))
                                .foregroundColor(diagnosticColor(for: check.severity))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                Text(check.message)
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                    }
                }

                HStack {
                    Button("Clear expired") {
                        runRecovery { try recoveryService.clearExpiredBlocks() }
                    }
                    .disabled(isRunningRecovery)

                    Button("Repair helper") {
                        runAsyncRecovery { try await recoveryService.repairManagedDomainBlocks() }
                    }
                    .disabled(isRunningRecovery)

                    Button("Remove all managed blocks", role: .destructive) {
                        runAsyncRecovery { try await recoveryService.removeAllManagedBlocks() }
                    }
                    .disabled(isRunningRecovery)
                }
                .buttonStyle(.bordered)

                Text("Remove all managed blocks clears active time.md cooldowns and the time.md-owned hosts/pf rules without deleting your rule definitions or analytics data.")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsSummary: String {
        guard let diagnosticsReport else {
            return "Run diagnostics to verify blocking enforcement and recovery state."
        }
        switch diagnosticsReport.overallSeverity {
        case .healthy:
            return "Blocking diagnostics are healthy. \(diagnosticsReport.activeBlockCount) active cooldown(s)."
        case .degraded:
            return "Blocking diagnostics found degraded recovery or enforcement state."
        case .broken:
            return "Blocking diagnostics found a broken state that needs repair before enforcement."
        }
    }

    private func diagnosticIcon(for severity: BlockingDiagnosticSeverity) -> String {
        switch severity {
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .broken: return "xmark.octagon.fill"
        }
    }

    private func diagnosticColor(for severity: BlockingDiagnosticSeverity) -> Color {
        switch severity {
        case .healthy: return BrutalTheme.positive
        case .degraded: return BrutalTheme.warning
        case .broken: return BrutalTheme.danger
        }
    }

    private func loadDiagnostics() async {
        diagnosticsReport = await diagnosticsService.report()
    }

    private func runRecovery(_ operation: @escaping () throws -> BlockingRecoveryResult) {
        isRunningRecovery = true
        do {
            let result = try operation()
            recoveryStatus = result.messages.joined(separator: " ")
        } catch {
            recoveryStatus = error.localizedDescription
        }
        isRunningRecovery = false
        Task {
            viewModel = await viewModel.loaded()
            await loadDiagnostics()
        }
    }

    private func runAsyncRecovery(_ operation: @escaping () async throws -> BlockingRecoveryResult) {
        isRunningRecovery = true
        Task {
            do {
                let result = try await operation()
                recoveryStatus = result.messages.joined(separator: " ")
            } catch {
                recoveryStatus = error.localizedDescription
            }
            isRunningRecovery = false
            viewModel = await viewModel.loaded()
            await loadDiagnostics()
        }
    }

    private var activeBlocksSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(BrutalTheme.sectionLabel(1, "ACTIVE COOLDOWNS"))
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1.5)
                    Spacer()
                    Button("Clear expired") {
                        try? viewModel.clearExpiredBlocks()
                    }
                    .font(BrutalTheme.captionMono)
                }

                if viewModel.activeRows.isEmpty {
                    Text("No active blocks right now.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(viewModel.activeRows) { row in
                        HStack(spacing: 12) {
                            targetIcon(row.target.type)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.targetLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                Text("Strike \(row.strikeCount) • unlocks \(row.blockedUntil.formatted(date: .abbreviated, time: .shortened))")
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                            Spacer()
                            Text(viewModel.countdownText(until: row.blockedUntil))
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(BrutalTheme.warning)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(BrutalTheme.surface.opacity(0.45)))
                    }
                }
            }
        }
    }

    private var rulesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(BrutalTheme.sectionLabel(2, "RULES"))
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1.5)
                    Spacer()
                    Picker("Type", selection: $selectedType) {
                        ForEach(BlockTargetType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 140)
                    Button {
                        viewModel.resetDraft(type: selectedType)
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if viewModel.ruleRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No blocking rules yet")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        Text(viewModel.emptyStateMessage)
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 16)
                } else {
                    ForEach(viewModel.ruleRows) { row in
                        ruleRow(row)
                    }
                }
            }
        }
    }

    private func ruleRow(_ row: BlockingRuleRow) -> some View {
        Button {
            viewModel.beginEditing(row.rule)
        } label: {
            HStack(spacing: 12) {
                targetIcon(row.rule.target.type)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.targetLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        if row.isActive {
                            Text("ACTIVE")
                                .font(BrutalTheme.captionMono)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(BrutalTheme.warning))
                        }
                    }
                    Text("\(row.enforcementLabel) • next penalty \(viewModel.durationText(row.nextPenaltySeconds)) • strike \(row.state?.strikeCount ?? 0)")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { row.rule.enabled },
                    set: { enabled in try? viewModel.toggleRule(row.rule, enabled: enabled) }
                ))
                .labelsHidden()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.selectedRuleID == row.id ? BrutalTheme.accentMuted : BrutalTheme.surface.opacity(0.4))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reset strikes") { try? viewModel.resetStrikes(for: row.rule) }
            Button("Delete", role: .destructive) { try? viewModel.deleteRule(id: row.id) }
        }
    }

    private var editorSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(viewModel.draft.editingRuleID == nil ? "New rule" : "Edit rule")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)

                Picker("Target", selection: $viewModel.draft.targetType) {
                    ForEach(BlockTargetType.allCases, id: \.rawValue) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .onChange(of: viewModel.draft.targetType) { _, newValue in
                    if viewModel.draft.editingRuleID == nil {
                        viewModel.draft.enforcementMode = newValue == .domain ? .domainNetwork : .appFocus
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(targetPlaceholder)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                    TextField(targetPlaceholder, text: $viewModel.draft.targetValue)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Display name (optional)", text: $viewModel.draft.displayName)
                    .textFieldStyle(.roundedBorder)

                Picker("Preset", selection: $viewModel.draft.preset) {
                    ForEach(BlockingPolicyPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }

                if viewModel.draft.preset == .custom {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Text("Base min")
                            TextField("1", value: $viewModel.draft.customBaseMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Multiplier")
                            TextField("2", value: $viewModel.draft.customMultiplier, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Max hours")
                            TextField("4", value: $viewModel.draft.customMaxHours, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                        GridRow {
                            Text("Min session sec")
                            TextField("0", value: $viewModel.draft.minimumSessionSeconds, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .font(BrutalTheme.bodyMono)
                }

                Picker("Enforcement", selection: $viewModel.draft.enforcementMode) {
                    Text("Monitor only").tag(BlockEnforcementMode.monitorOnly)
                    Text("Domain network").tag(BlockEnforcementMode.domainNetwork)
                    Text("App focus").tag(BlockEnforcementMode.appFocus)
                }

                Toggle("Enabled", isOn: $viewModel.draft.enabled)

                HStack {
                    Button(viewModel.draft.editingRuleID == nil ? "Create rule" : "Save changes") {
                        do {
                            let savedRule = try viewModel.saveDraft()
                            if savedRule.enabled,
                               savedRule.target.type == .domain,
                               savedRule.enforcementMode == .domainNetwork {
                                Task {
                                    _ = await WebsiteAccessEventSource.shared.pollOnce()
                                    viewModel = await viewModel.loaded()
                                    await loadDiagnostics()
                                }
                            }
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.draft.targetValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let id = viewModel.draft.editingRuleID,
                       let rule = viewModel.ruleRows.first(where: { $0.id == id })?.rule {
                        Button("Reset") { try? viewModel.resetStrikes(for: rule) }
                        Button("Delete", role: .destructive) { try? viewModel.deleteRule(id: id) }
                    }
                }
            }
        }
    }

    private var targetPlaceholder: String {
        switch viewModel.draft.targetType {
        case .domain: return "example.com"
        case .app: return "Bundle ID or app name"
        case .category: return "Category name"
        }
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
        .frame(width: 1100, height: 800)
}
