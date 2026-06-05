import AppKit
import SwiftUI

struct LicenseActivationGateView: View {
    @Environment(LicenseActivationStore.self) private var activationStore
    @State private var activationKey = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            GlassCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(BrutalTheme.accentMuted)
                                .frame(width: 58, height: 58)
                            Image(systemName: iconName)
                                .font(.system(size: 25, weight: .bold))
                                .foregroundColor(BrutalTheme.accent)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text("00 / TRIAL OR LICENSE")
                                .font(BrutalTheme.headingFont)
                                .foregroundColor(BrutalTheme.textSecondary)
                                .tracking(1.5)
                            Text("Try or activate time.md")
                                .font(.system(size: 30, weight: .black, design: .monospaced))
                                .foregroundColor(BrutalTheme.textPrimary)
                            Text("Download is free. After onboarding, start a 14-day card-backed trial in Stripe Checkout; time.md reopens automatically when your trial is ready.")
                                .font(BrutalTheme.bodyMono)
                                .foregroundColor(BrutalTheme.textSecondary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if activationStore.phase == .checking {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Checking saved trial or activation…")
                                .font(BrutalTheme.bodyMono)
                                .foregroundColor(BrutalTheme.textSecondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                Task { await openTrialCheckout() }
                            } label: {
                                HStack(spacing: 8) {
                                    if activationStore.phase == .startingTrial {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "creditcard.fill")
                                    }
                                    Text(activationStore.phase == .startingTrial ? "Opening Stripe…" : "Start 14-Day Free Trial")
                                    Spacer(minLength: 0)
                                    Text("Card required")
                                        .font(BrutalTheme.captionMono)
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(activationStore.phase.isBusy)

                            Text("PASTE TRIAL OR LICENSE KEY")
                                .font(BrutalTheme.captionMono)
                                .foregroundColor(BrutalTheme.textTertiary)
                                .tracking(1.5)
                                .padding(.top, 4)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("TRIAL / ACTIVATION KEY")
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .tracking(1.5)

                                TextField("TMDTRIAL-… or TMD-XXXX-XXXX-XXXX-XXXX-XXXX", text: $activationKey)
                                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color.primary.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                    )
                                    .disabled(activationStore.phase.isBusy)
                                    .onSubmit {
                                        Task { await submitActivation() }
                                    }
                            }

                            HStack(spacing: 10) {
                                Button {
                                    Task { await submitActivation() }
                                } label: {
                                    HStack(spacing: 8) {
                                        if activationStore.phase == .activating {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "checkmark.seal.fill")
                                        }
                                        Text(activationStore.phase.isBusy ? "Activating…" : "Activate Key")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(activationStore.phase.isBusy || activationKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button("Paste Key") {
                                    pasteActivationKey()
                                }
                                .buttonStyle(.bordered)
                                .disabled(activationStore.phase.isBusy)

                                Button("Buy License") {
                                    openPurchasePortal()
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }
                        }
                    }

                    statusView

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Stripe collects and stores card details in the browser; time.md receives only entitlement records and never sees card numbers.", systemImage: "creditcard.fill")
                        Label("Screen time, browser history, exports, and input-tracking data stay on this Mac.", systemImage: "lock.fill")
                        Label("The browser return link activates the trial automatically; a paid activation unlocks permanently.", systemImage: "link")
                    }
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .labelStyle(.titleAndIcon)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 580)

            Spacer(minLength: 0)
        }
        .padding(32)
        .frame(minWidth: 660, minHeight: 560)
        .background(BrutalTheme.background)
    }

    @ViewBuilder
    private var statusView: some View {
        switch activationStore.phase {
        case .failed(let message):
            statusPill(message, tone: .error)
        case .activated:
            statusPill(activationStore.statusMessage ?? "Activated.", tone: .success)
        case .trialing:
            statusPill(activationStore.statusMessage ?? "Trial active — \(activationStore.trialRemainingDescription()).", tone: .success)
        case .activating:
            statusPill(activationStore.statusMessage ?? "Activating…", tone: .neutral)
        case .startingTrial:
            statusPill(activationStore.statusMessage ?? "Activating trial…", tone: .neutral)
        case .checking:
            EmptyView()
        case .needsActivation:
            if let message = activationStore.statusMessage, !message.isEmpty {
                statusPill(message, tone: .neutral)
            }
        }
    }

    private var iconName: String {
        switch activationStore.phase {
        case .failed:
            return "xmark.seal.fill"
        case .activated:
            return "checkmark.seal.fill"
        case .trialing:
            return "timer.circle.fill"
        case .startingTrial:
            return "creditcard.fill"
        default:
            return "key.fill"
        }
    }

    private func statusPill(_ message: String, tone: StatusTone) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tone.icon)
            Text(message)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(BrutalTheme.captionMono)
        .foregroundColor(tone.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tone.background)
        )
    }

    private func submitActivation() async {
        let normalizedInput = activationKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalizedInput.hasPrefix("TMDTRIAL") {
            await activationStore.activateTrial(with: normalizedInput)
        } else {
            await activationStore.activate(with: activationKey)
        }
    }

    private func openTrialCheckout() async {
        guard let checkoutURL = await activationStore.createTrialCheckoutURL() else { return }
        NSWorkspace.shared.open(checkoutURL)
    }

    private func pasteActivationKey() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            activationKey = LicenseActivationKeyFormatter.normalized(pasted)
        }
    }

    private func openPurchasePortal() {
        NSWorkspace.shared.open(URL(string: "https://timemd.isolated.tech/#portal")!)
    }

    private enum StatusTone {
        case neutral
        case success
        case error

        var icon: String {
            switch self {
            case .neutral: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "exclamationmark.triangle.fill"
            }
        }

        var foreground: Color {
            switch self {
            case .neutral: return BrutalTheme.textSecondary
            case .success: return .green
            case .error: return BrutalTheme.danger
            }
        }

        var background: Color {
            switch self {
            case .neutral: return Color.primary.opacity(0.06)
            case .success: return Color.green.opacity(0.12)
            case .error: return BrutalTheme.danger.opacity(0.12)
            }
        }
    }
}

struct LicenseMenuBarExtraView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("time.md needs a trial or license key", systemImage: "lock.fill")
                .font(.headline)

            Text("Open the app to finish onboarding, start a card-backed 14-day trial, or paste your trial/license key.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button {
                AppVisibilityMode.current.apply()
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            } label: {
                Label("Open Activation", systemImage: "key.fill")
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
        .frame(width: 250)
    }
}

struct LicenseMenuBarLabel: View {
    var body: some View {
        Image(systemName: "lock.fill")
    }
}

struct LicenseSettingsSection: View {
    @Environment(LicenseActivationStore.self) private var activationStore
    @State private var resetConfirmation = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(9, "LICENSE & TRIAL"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(statusColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(activationStore.entitlementTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(BrutalTheme.textPrimary)

                        Text(activationStore.entitlementDetail)
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)

                        if let message = activationStore.statusMessage, !message.isEmpty {
                            Text(message)
                                .font(BrutalTheme.captionMono)
                                .foregroundColor(BrutalTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer()

                    Button("Verify Now") {
                        Task { await activationStore.revalidateCurrentEntitlement() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!activationStore.isUnlockedForLaunch || activationStore.phase.isBusy)

                    Button("Reset") {
                        resetConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(!activationStore.hasSavedEntitlement)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("Reset activation or trial on this Mac?", isPresented: $resetConfirmation) {
            Button("Reset Entitlement", role: .destructive) {
                activationStore.resetActivation()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("time.md will lock until you start a trial or paste a valid activation key again.")
        }
    }

    private var statusIcon: String {
        if activationStore.isPaidActivated { return "checkmark.seal.fill" }
        if activationStore.isTrialActive { return "timer.circle.fill" }
        return "key.fill"
    }

    private var statusColor: Color {
        if activationStore.isPaidActivated || activationStore.isTrialActive { return .green }
        return BrutalTheme.warning
    }
}
