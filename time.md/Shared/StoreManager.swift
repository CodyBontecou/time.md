import Combine
import Foundation
import StoreKit

// MARK: - User Tier

enum UserTier: Int, Comparable {
    case free = 0
    case base = 1
    case pro  = 2

    static func < (lhs: UserTier, rhs: UserTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .base: return "Base"
        case .pro:  return "Pro"
        }
    }
}

// MARK: - StoreManager

/// Manages one-time lifetime purchases for Base and Pro tiers via StoreKit 2.
@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    nonisolated static let baseProductID = "com.codybontecou.Timeprint.lifetime"
    nonisolated static let proProductID  = "com.codybontecou.Timeprint.pro"

    @Published private(set) var baseProduct: Product?
    @Published private(set) var proProduct: Product?
    @Published private(set) var tier: UserTier = .free
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
            let products = try await Product.products(for: [Self.baseProductID, Self.proProductID])
            for product in products {
                if product.id == Self.baseProductID { baseProduct = product }
                if product.id == Self.proProductID  { proProduct  = product }
            }
        } catch {
            print("[Store] Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isLoading = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateTier(for: transaction.productID)
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

        if tier == .free {
            purchaseError = "No previous purchase found."
        }

        isLoading = false
    }

    // MARK: - Entitlement Check

    func checkEntitlement() async {
        var highestTier = UserTier.free

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == Self.proProductID {
                    highestTier = .pro
                } else if transaction.productID == Self.baseProductID, highestTier < .base {
                    highestTier = .base
                }
            }
        }

        tier = highestTier
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        return Task.detached {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await StoreManager.shared.updateTier(for: transaction.productID)
                    await transaction.finish()
                }
            }
        }
    }

    private func updateTier(for productID: String) async {
        if productID == Self.proProductID {
            tier = .pro
        } else if productID == Self.baseProductID, tier < .base {
            tier = .base
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
