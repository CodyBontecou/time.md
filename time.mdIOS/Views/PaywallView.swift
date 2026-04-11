import SwiftUI
import StoreKit

/// Full-screen paywall shown when the 12-hour free trial expires (iOS).
struct IOSPaywallView: View {
    @ObservedObject var store: StoreManager
    @ObservedObject var usage: UsageTracker

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Icon
                Image(systemName: "hourglass.bottomhalf.filled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                // Title
                VStack(spacing: 10) {
                    Text("Your free trial has ended")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.primary)

                    Text("You've used time.md for over 12 hours.\nUnlock lifetime access with a one-time purchase.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Price
                VStack(spacing: 4) {
                    if let product = store.product {
                        Text(product.displayPrice)
                            .font(.system(size: 40, weight: .black, design: .monospaced))
                            .foregroundColor(.primary)
                    } else {
                        Text("$19.99")
                            .font(.system(size: 40, weight: .black, design: .monospaced))
                            .foregroundColor(.primary)
                    }

                    Text("one-time purchase, forever yours")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    featureRow(text: "Unlimited screen time analytics")
                    featureRow(text: "All future updates included")
                    featureRow(text: "iCloud sync across devices")
                    featureRow(text: "No subscriptions, ever")
                }
                .padding(.vertical, 8)

                // Purchase button
                Button {
                    Task { await store.purchase() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(store.isLoading ? "Processing..." : "Unlock time.md")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(store.isLoading || store.product == nil)

                // Restore
                Button {
                    Task { await store.restore() }
                } label: {
                    Text("Restore Purchase")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .disabled(store.isLoading)

                // Error
                if let error = store.purchaseError {
                    Text(error)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func featureRow(text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.green)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}
