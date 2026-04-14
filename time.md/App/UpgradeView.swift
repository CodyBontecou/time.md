import StoreKit
import SwiftUI

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
