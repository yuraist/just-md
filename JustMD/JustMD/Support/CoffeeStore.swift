#if !DIRECT_DISTRIBUTION
import Combine
import Foundation
import StoreKit

nonisolated struct CoffeeProduct: Equatable, Sendable {
    let id: String
    let displayPrice: String
}

nonisolated enum CoffeePurchaseOutcome: Sendable {
    case purchased, cancelled, pending
}

nonisolated protocol CoffeeProductProviding: Sendable {
    func loadProduct(id: String) async throws -> CoffeeProduct?
    func purchase(id: String) async throws -> CoffeePurchaseOutcome
    /// Emits once per consumable finished outside `purchase(id:)`, e.g. a
    /// transaction interrupted by a crash and delivered at the next launch.
    var completedPurchases: AsyncStream<Void> { get }
}

/// Real StoreKit 2 provider. Loaded products are cached per id so
/// `purchase(id:)` can reuse the `Product` StoreKit handed us.
nonisolated final class StoreKitCoffeeProvider: CoffeeProductProviding {
    private let cache = ProductCache()

    func loadProduct(id: String) async throws -> CoffeeProduct? {
        guard let product = try await Product.products(for: [id]).first else { return nil }
        await cache.store(product)
        return CoffeeProduct(id: product.id, displayPrice: product.displayPrice)
    }

    func purchase(id: String) async throws -> CoffeePurchaseOutcome {
        guard let product = await cache.product(for: id) else {
            throw StoreKitError.notAvailableInStorefront
        }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            return .purchased
        case .userCancelled:
            return .cancelled
        case .pending:
            return .pending
        @unknown default:
            return .cancelled
        }
    }

    var completedPurchases: AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    guard let transaction = try? result.payloadValue else { continue }
                    await transaction.finish()
                    if transaction.revocationDate == nil { continuation.yield() }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private actor ProductCache {
        private var products: [String: Product] = [:]
        func store(_ product: Product) { products[product.id] = product }
        func product(for id: String) -> Product? { products[id] }
    }
}

/// State machine behind the "Buy me a coffee" button. A consumable can be
/// bought any number of times; `coffeeCount` is a local, cosmetic tally.
@MainActor
final class CoffeeStore: ObservableObject {
    enum State: Equatable { case loading, ready, purchasing, thanked, unavailable, failed(String) }

    private static let countKey = "com.justmd.support.coffeeCount"

    @Published private(set) var state: State = .loading
    @Published private(set) var product: CoffeeProduct?
    @Published private(set) var coffeeCount: Int

    private let provider: CoffeeProductProviding
    private let defaults: UserDefaults
    private var updatesTask: Task<Void, Never>?

    init(provider: CoffeeProductProviding = StoreKitCoffeeProvider(), defaults: UserDefaults = .standard) {
        self.provider = provider
        self.defaults = defaults
        self.coffeeCount = defaults.integer(forKey: Self.countKey)
        updatesTask = Task { [weak self] in
            for await _ in provider.completedPurchases {
                self?.recordCoffee()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        do {
            if let loaded = try await provider.loadProduct(id: SupportConfig.coffeeProductID) {
                product = loaded
                state = .ready
            } else {
                state = .unavailable
            }
        } catch {
            state = .unavailable
        }
    }

    func buy() async {
        guard product != nil, state != .purchasing else { return }
        state = .purchasing
        do {
            switch try await provider.purchase(id: SupportConfig.coffeeProductID) {
            case .purchased:
                recordCoffee()
                state = .thanked
            case .cancelled:
                state = .ready
            case .pending:
                state = .failed("Purchase is awaiting approval.")
            }
        } catch {
            state = .failed("The purchase didn't go through. Try again.")
        }
    }

    private func recordCoffee() {
        coffeeCount += 1
        defaults.set(coffeeCount, forKey: Self.countKey)
    }
}
#endif
