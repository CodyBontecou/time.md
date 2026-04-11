import SwiftUI
import StoreKit

/// Full-screen paywall shown when the 12-hour free trial expires.
struct PaywallView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject var usage: UsageTracker

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Icon
                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.secondary)

                // Title
                VStack(spacing: 8) {
                    Text("Your free trial has ended")
                        .font(.system(size: 22, weight: .bold, design: .default))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text("You've used time.md for over 12 hours.\nUnlock lifetime access with a one-time purchase.")
                        .font(.system(size: 13, weight: .regular, design: .monospaced))
                        .foregroundColor(BrutalTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Price
                VStack(spacing: 4) {
                    if let product = store.product {
                        Text(product.displayPrice)
                            .font(.system(size: 36, weight: .black, design: .monospaced))
                            .foregroundColor(BrutalTheme.textPrimary)
                    } else {
                        Text("$19.99")
                            .font(.system(size: 36, weight: .black, design: .monospaced))
                            .foregroundColor(BrutalTheme.textPrimary)
                    }

                    Text("one-time purchase, forever yours")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                // Features
                VStack(alignment: .leading, spacing: 10) {
                    featureRow(icon: "checkmark.circle.fill", text: "Unlimited screen time analytics")
                    featureRow(icon: "checkmark.circle.fill", text: "All future updates included")
                    featureRow(icon: "checkmark.circle.fill", text: "iCloud sync across devices")
                    featureRow(icon: "checkmark.circle.fill", text: "No subscriptions, ever")
                }
                .padding(.vertical, 8)

                // Purchase button
                Button {
                    Task { await store.purchase() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                        Text(store.isLoading ? "Processing..." : "Unlock time.md")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(store.isLoading || store.product == nil)

                // Restore
                Button {
                    Task { await store.restore() }
                } label: {
                    Text("Restore Purchase")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .disabled(store.isLoading)

                // Error
                if let error = store.purchaseError {
                    Text(error)
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

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
        }
    }
}
