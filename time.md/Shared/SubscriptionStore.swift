import Combine
import Foundation
import StoreKit

@MainActor
final class SubscriptionStore: ObservableObject {
    static let shared = SubscriptionStore()

    nonisolated static let yearlyProductID = "com.bontecou.time.md.pro.yearly"
    nonisolated static let monthlyProductID = "com.bontecou.time.md.pro.monthly"
    nonisolated static let lifetimeProductID = "com.bontecou.time.md.lifetime"
    nonisolated static let subscriptionProductIDs: [String] = [yearlyProductID, monthlyProductID]
    nonisolated static let allProductIDs: [String] = [yearlyProductID, monthlyProductID, lifetimeProductID]

    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var isEntitled: Bool = false
    @Published private(set) var isInTrial: Bool = false
    @Published private(set) var purchaseError: String?
    @Published private(set) var isLoading: Bool = false

    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = listenForTransactions()
        Task {
            await loadProducts()
            await refreshEntitlement()
        }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.allProductIDs)
            for product in products {
                if product.id == Self.yearlyProductID { yearlyProduct = product }
                if product.id == Self.monthlyProductID { monthlyProduct = product }
                if product.id == Self.lifetimeProductID { lifetimeProduct = product }
            }
        } catch {
            purchaseError = "Couldn't load purchase options. Check your connection."
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Restore

    func restore() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        try? await AppStore.sync()
        await refreshEntitlement()

        if !isEntitled {
            purchaseError = "No active purchase found."
        }
    }

    // MARK: - Entitlement

    func refreshEntitlement() async {
        var entitled = false
        var inTrial = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate != nil { continue }
            if let expirationDate = transaction.expirationDate, expirationDate < Date() { continue }

            entitled = true
            if transaction.offerType == .introductory {
                inTrial = true
            }
        }

        isEntitled = entitled
        isInTrial = inTrial
    }

    /// Days remaining in the current intro trial, if any. nil when not in a trial.
    func trialDaysRemaining() async -> Int? {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.allProductIDs.contains(transaction.productID) else { continue }
            guard transaction.offerType == .introductory else { continue }
            guard let expirationDate = transaction.expirationDate else { continue }
            let seconds = expirationDate.timeIntervalSince(Date())
            guard seconds > 0 else { return 0 }
            return Int(ceil(seconds / 86_400))
        }
        return nil
    }

    /// Whether the current Apple ID is eligible for the introductory free-trial offer.
    /// Apple allows one intro offer per subscription group per family.
    func isEligibleForIntroOffer() async -> Bool {
        guard let product = yearlyProduct ?? monthlyProduct else { return true }
        guard let subscription = product.subscription else { return false }
        return await subscription.isEligibleForIntroOffer
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }
}
