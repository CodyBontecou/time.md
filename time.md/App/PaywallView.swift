import StoreKit
import SwiftUI

struct PaywallView: View {
    @ObservedObject private var store = SubscriptionStore.shared
    @State private var selectedProductID: String = SubscriptionStore.yearlyProductID
    @State private var introEligible: Bool = true

    /// Called once a purchase or restore successfully entitles the user.
    var onEntitled: (() -> Void)?

    private var selectedProduct: Product? {
        selectedProductID == SubscriptionStore.yearlyProductID
            ? store.yearlyProduct
            : store.monthlyProduct
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 16)

            Text(LocalizedStringKey("05 / GET STARTED"))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(2)
                .padding(.bottom, 14)

            Image(systemName: "hourglass.bottomhalf.filled")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.blue)
                .padding(.bottom, 18)

            Text(introEligible ? "Try time.md Free for 30 Days" : "Subscribe to time.md")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 6)

            Text(introEligible
                 ? "Then continue for the price below. Cancel anytime."
                 : "Choose a plan to unlock time.md.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 22)

            HStack(spacing: 12) {
                planCard(
                    productID: SubscriptionStore.yearlyProductID,
                    title: "Yearly",
                    price: store.yearlyProduct?.displayPrice ?? "$29.99",
                    cadence: "/ year",
                    badge: "BEST VALUE",
                    subtitle: yearlySubtitle
                )
                planCard(
                    productID: SubscriptionStore.monthlyProductID,
                    title: "Monthly",
                    price: store.monthlyProduct?.displayPrice ?? "$4.99",
                    cadence: "/ month",
                    badge: nil,
                    subtitle: nil
                )
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 18)

            Button(action: startPurchase) {
                HStack(spacing: 8) {
                    if store.isLoading {
                        ProgressView().controlSize(.small).scaleEffect(0.8).tint(.white)
                    }
                    Text(ctaLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: BrutalTheme.pillCornerRadius)
                        .fill(Color.accentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isLoading || selectedProduct == nil)
            .padding(.horizontal, 40)
            .padding(.bottom, 12)

            if let error = store.purchaseError {
                Text(LocalizedStringKey(error))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 18) {
                Button("Restore Purchase") {
                    Task {
                        await store.restore()
                        if store.isEntitled { onEntitled?() }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
                .disabled(store.isLoading)

                Link("Terms", destination: URL(string: "https://timemd.isolated.tech/terms")!)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)

                Link("Privacy", destination: URL(string: "https://timemd.isolated.tech/privacy")!)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .padding(.bottom, 8)

            Text(footnote)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await store.loadProducts()
            introEligible = await store.isEligibleForIntroOffer()
        }
        .onChange(of: store.isEntitled) { _, entitled in
            if entitled { onEntitled?() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func planCard(
        productID: String,
        title: String,
        price: String,
        cadence: String,
        badge: String?,
        subtitle: String?
    ) -> some View {
        let isSelected = selectedProductID == productID
        Button {
            selectedProductID = productID
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Spacer()
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: price)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Text(cadence)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BrutalTheme.pillCornerRadius)
                    .fill(isSelected ? BrutalTheme.accentMuted : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrutalTheme.pillCornerRadius)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed copy

    private var ctaLabel: String {
        if store.isLoading { return "Processing..." }
        return introEligible ? "Start 30-Day Free Trial" : "Subscribe"
    }

    private var yearlySubtitle: String? {
        guard let yearly = store.yearlyProduct?.price,
              let monthly = store.monthlyProduct?.price,
              monthly > 0 else { return "Save vs monthly" }
        let yearlyMonthly = NSDecimalNumber(decimal: yearly / 12).doubleValue
        let monthlyDouble = NSDecimalNumber(decimal: monthly).doubleValue
        let savings = (1 - (yearlyMonthly / monthlyDouble)) * 100
        let pct = Int(savings.rounded())
        guard pct > 0 else { return nil }
        return "Save \(pct)% vs monthly"
    }

    private var footnote: String {
        if introEligible {
            return "30 days free, then your selected plan. Renews automatically. Cancel anytime in System Settings → Apple ID → Subscriptions."
        } else {
            return "Renews automatically. Cancel anytime in System Settings → Apple ID → Subscriptions."
        }
    }

    // MARK: - Actions

    private func startPurchase() {
        guard let product = selectedProduct else { return }
        Task {
            await store.purchase(product)
            if store.isEntitled { onEntitled?() }
        }
    }
}

#Preview {
    PaywallView()
        .frame(width: 640, height: 520)
        .background(BrutalTheme.background)
}
