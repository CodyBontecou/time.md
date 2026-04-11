import Combine
import Foundation
import StoreKit

/// Manages the one-time lifetime purchase via StoreKit 2.
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    nonisolated static let lifetimeProductID = "com.codybontecou.Timeprint.lifetime"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading = false

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await checkEntitlement() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.lifetimeProductID])
            product = products.first
        } catch {
            print("[Store] Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase() async {
        guard let product else { return }
        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                isPurchased = true
                await transaction.finish()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        purchaseError = nil

        try? await AppStore.sync()
        await checkEntitlement()

        if !isPurchased {
            purchaseError = "No previous purchase found."
        }

        isLoading = false
    }

    // MARK: - Entitlement Check

    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.lifetimeProductID {
                isPurchased = true
                return
            }
        }
        // If we get here, no matching entitlement was found — but only clear
        // isPurchased if it wasn't already set by a purchase flow this session.
        if !isPurchased {
            isPurchased = false
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        let productID = Self.lifetimeProductID
        return Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   transaction.productID == productID {
                    await MainActor.run {
                        StoreManager.shared.isPurchased = true
                    }
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
