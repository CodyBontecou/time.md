import StoreKit
import SwiftUI

// MARK: - Mac Paywall

/// Full-window paywall shown on macOS when the user is on the Free tier.
/// Displays Base and Pro side-by-side so users can compare before buying.
struct MacPaywallView: View {
    @ObservedObject private var store = StoreManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "hourglass.bottomhalf.filled")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.secondary)

                    Text("Unlock time.md")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text("One-time purchase. No subscriptions. Yours forever.")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(BrutalTheme.textSecondary)
                }

                // Tier cards
                HStack(alignment: .top, spacing: 16) {
                    MacTierCard(
                        title: "Base",
                        price: store.baseProduct?.displayPrice ?? "$9.99",
                        description: "Everything you need to understand your screen time.",
                        features: [
                            "Full history — no date limits",
                            "Web History & Reports",
                            "CSV / JSON export",
                            "Projects & Rules",
                            "All future Base updates"
                        ],
                        buttonLabel: "Unlock Base",
                        isHighlighted: false,
                        isLoading: store.isLoading,
                        isDisabled: store.baseProduct == nil
                    ) {
                        if let product = store.baseProduct {
                            Task { await store.purchase(product) }
                        }
                    }

                    MacTierCard(
                        title: "Pro",
                        price: store.proProduct?.displayPrice ?? "$19.99",
                        description: "AI-powered querying via Claude Code MCP integration.",
                        features: [
                            "Everything in Base",
                            "Claude Code MCP server",
                            "35+ natural language query tools",
                            "Raw SQL access to your data",
                            "All future AI & Pro features"
                        ],
                        buttonLabel: "Unlock Pro",
                        isHighlighted: true,
                        isLoading: store.isLoading,
                        isDisabled: store.proProduct == nil
                    ) {
                        if let product = store.proProduct {
                            Task { await store.purchase(product) }
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                // Restore + error
                VStack(spacing: 8) {
                    Button {
                        Task { await store.restore() }
                    } label: {
                        Text("Restore Purchase")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isLoading)

                    if let error = store.purchaseError {
                        Text(LocalizedStringKey(error))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity)
        }
        .background(BrutalTheme.background)
    }
}

// MARK: - Mac Tier Card

private struct MacTierCard: View {
    let title: String
    let price: String
    let description: String
    let features: [String]
    let buttonLabel: String
    let isHighlighted: Bool
    let isLoading: Bool
    let isDisabled: Bool
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                if isHighlighted {
                    Text("MOST POPULAR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BrutalTheme.accent)
                        .clipShape(Capsule())
                }

                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(verbatim: price)
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text("one-time")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)

                Text(description)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
            .padding(16)

            Divider()
                .padding(.horizontal, 16)

            // Features
            VStack(alignment: .leading, spacing: 8) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                            .padding(.top, 1)
                        Text(feature)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)

            // Button
            Button(action: onPurchase) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView().controlSize(.small).scaleEffect(0.8)
                    }
                    Text(isLoading ? "Processing..." : buttonLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(isHighlighted ? .white : BrutalTheme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    isHighlighted
                        ? BrutalTheme.accent
                        : BrutalTheme.accent.opacity(0.12)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(isLoading || isDisabled)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(BrutalTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isHighlighted ? BrutalTheme.accent : BrutalTheme.border,
                            lineWidth: isHighlighted ? 2 : 1
                        )
                )
        )
    }
}

/// Reusable upgrade prompt shown when a user without the required tier
/// tries to access a gated feature.
///
/// Use `compact: true` for inline settings rows; `compact: false` (default)
/// for full detail-pane replacements.
struct UpgradeView: View {
    let requiredTier: UserTier
    var compact: Bool = false

    @ObservedObject private var store = StoreManager.shared

    var body: some View {
        if compact {
            compactBody
        } else {
            fullBody
        }
    }

    // MARK: - Full (detail pane)

    private var fullBody: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: iconName)
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text(subheadline)
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(BrutalTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(spacing: 4) {
                    if let price = displayPrice {
                        Text(verbatim: price)
                            .font(.system(size: 34, weight: .black, design: .monospaced))
                            .foregroundColor(BrutalTheme.textPrimary)
                    }
                    Text("one-time purchase, forever yours")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(featureBullets, id: \.self) { bullet in
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.green)
                            Text(LocalizedStringKey(bullet))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textPrimary)
                        }
                    }
                }
                .padding(.vertical, 8)

                Button {
                    Task { await purchaseAction() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isLoading {
                            ProgressView().controlSize(.small).scaleEffect(0.8)
                        }
                        Text(store.isLoading ? "Processing..." : buttonLabel)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(store.isLoading || targetProduct == nil)

                Button {
                    Task { await store.restore() }
                } label: {
                    Text("Restore Purchase")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading)

                if let error = store.purchaseError {
                    Text(LocalizedStringKey(error))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compact (inline settings row)

    private var compactBody: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BrutalTheme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(requiredTier.displayName) feature")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                if let price = displayPrice {
                    Text("Unlock for \(price) — one-time purchase")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
            }

            Spacer()

            Button {
                Task { await purchaseAction() }
            } label: {
                HStack(spacing: 6) {
                    if store.isLoading {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    Text(store.isLoading ? "..." : "Upgrade")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .disabled(store.isLoading || targetProduct == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BrutalTheme.surface.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BrutalTheme.border.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Helpers

    private var targetProduct: Product? {
        switch requiredTier {
        case .free: return nil
        case .base: return store.baseProduct
        case .pro:  return store.proProduct
        }
    }

    private var displayPrice: String? {
        targetProduct?.displayPrice
    }

    private var iconName: String {
        requiredTier == .pro ? "sparkles" : "lock.open.fill"
    }

    private var headline: String {
        requiredTier == .pro ? "time.md Pro" : "time.md Base"
    }

    private var subheadline: String {
        requiredTier == .pro
            ? "Unlock AI-powered features including the\nClaude Code MCP integration."
            : "Unlock your complete screen time history,\nexports, web history, reports, and more."
    }

    private var buttonLabel: String {
        requiredTier == .pro ? "Upgrade to Pro" : "Unlock time.md"
    }

    private var featureBullets: [String] {
        switch requiredTier {
        case .free:
            return []
        case .base:
            return [
                "Full history — no date limits",
                "Web History & Reports",
                "CSV / JSON export",
                "Projects & Rules",
                "iCloud sync across devices",
                "All future Base updates"
            ]
        case .pro:
            return [
                "Everything in Base",
                "Claude Code MCP server (35+ query tools)",
                "Raw SQL access to your data",
                "All future AI & Pro features"
            ]
        }
    }

    private func purchaseAction() async {
        guard let product = targetProduct else { return }
        await store.purchase(product)
    }
}
