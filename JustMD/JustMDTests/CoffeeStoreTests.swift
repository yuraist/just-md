#if !DIRECT_DISTRIBUTION
import Testing
import Foundation
@testable import JustMD

@Suite("CoffeeStore")
@MainActor
struct CoffeeStoreTests {
    final class Fake: CoffeeProductProviding, @unchecked Sendable {
        var product: CoffeeProduct? = CoffeeProduct(id: SupportConfig.coffeeProductID, displayPrice: "$2.99")
        var outcome: CoffeePurchaseOutcome = .purchased
        var loadError: Error?
        var purchaseError: Error?
        var completedPurchases: AsyncStream<Void> { AsyncStream { $0.finish() } }
        func loadProduct(id: String) async throws -> CoffeeProduct? {
            if let loadError { throw loadError }
            return product
        }
        func purchase(id: String) async throws -> CoffeePurchaseOutcome {
            if let purchaseError { throw purchaseError }
            return outcome
        }
    }
    struct Boom: Error {}

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    @Test func loadsProduct() async {
        let store = CoffeeStore(provider: Fake(), defaults: defaults())
        #expect(store.state == .loading)
        await store.load()
        #expect(store.state == .ready)
        #expect(store.product?.displayPrice == "$2.99")
    }

    @Test func missingProductIsUnavailable() async {
        let fake = Fake()
        fake.product = nil
        let store = CoffeeStore(provider: fake, defaults: defaults())
        await store.load()
        #expect(store.state == .unavailable)

        let failing = Fake()
        failing.loadError = Boom()
        let store2 = CoffeeStore(provider: failing, defaults: defaults())
        await store2.load()
        #expect(store2.state == .unavailable)
    }

    @Test func purchaseIncrementsAndCanRepeat() async {
        let d = defaults()
        let store = CoffeeStore(provider: Fake(), defaults: d)
        await store.load()
        await store.buy()
        await store.buy()
        #expect(store.state == .thanked)
        #expect(store.coffeeCount == 2)
        #expect(CoffeeStore(provider: Fake(), defaults: d).coffeeCount == 2)
    }

    @Test func cancelPendingAndError() async {
        let fake = Fake()
        fake.outcome = .cancelled
        let store = CoffeeStore(provider: fake, defaults: defaults())
        await store.load()
        await store.buy()
        #expect(store.state == .ready)
        #expect(store.coffeeCount == 0)

        fake.outcome = .pending
        await store.buy()
        #expect(store.state == .failed("Purchase is awaiting approval."))

        fake.purchaseError = Boom()
        await store.buy()
        #expect(store.state == .failed("The purchase didn't go through. Try again."))
    }

    @Test func buyBeforeLoadIsNoop() async {
        let store = CoffeeStore(provider: Fake(), defaults: defaults())
        await store.buy()
        #expect(store.state == .loading)
        #expect(store.coffeeCount == 0)
    }
}
#endif
