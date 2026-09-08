# Support Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Support JustMD" window with a newsletter email form (Supabase) and a repeatable "Buy me a coffee" StoreKit 2 consumable (App Store build only), shipping as 1.1.

**Architecture:** New `JustMD/JustMD/Support/` module: a SwiftUI view hosted by an `NSWindowController` singleton (same shape as Welcome/Preferences), a `NewsletterClient` over `URLSession` → Supabase PostgREST, and a `CoffeeStore` over StoreKit 2 compiled out under `DIRECT_DISTRIBUTION`. Entry points: Help menu item and a text button on Welcome.

**Tech Stack:** Swift 6.2, AppKit + SwiftUI, StoreKit 2, URLSession, Swift Testing, Supabase (PostgREST, RLS).

**Spec:** `docs/superpowers/specs/2026-09-08-support-window-design.md`

## Global Constraints

- Do not touch the pending 1.0 review. Bump `MARKETING_VERSION` to `1.1` in both app configurations.
- `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` in both app configurations (sandbox network client).
- Supabase project: Nuta Apps, ref `txeisrdkgcloqjiqexnw`. Table `public.newsletter_subscribers`.
- Product id: `com.nuta.JustMD.coffee`, consumable, $2.99.
- Direct-download builds pass `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION'`; all StoreKit code and UI sit under `#if !DIRECT_DISTRIBUTION`.
- Build/test commands (from README):
  `xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD -destination 'platform=macOS' build`
  `xcodebuild -project JustMD/JustMD.xcodeproj -scheme JustMD -destination 'platform=macOS' -only-testing:JustMDTests test`
  New files under `JustMD/JustMD/` and `JustMD/JustMDTests/` are picked up automatically (file-system synchronized groups).
- Tests: Swift Testing (`@Suite`, `@Test`, `#expect`), `@testable import JustMD`.

---

### Task 1: Supabase table + config

**Files:**
- Create: `JustMD/JustMD/Support/SupportConfig.swift`
- Supabase migration `newsletter_subscribers` (via MCP `apply_migration` on project `txeisrdkgcloqjiqexnw`; restore the project first with `restore_project`).

**Interfaces:**
- Produces: `enum SupportConfig { static let supabaseURL: URL; static let supabasePublishableKey: String; static let coffeeProductID: String; static let newsletterSource: String }`

- [ ] **Step 1: Restore the project and apply the migration**

```sql
create table public.newsletter_subscribers (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  source text not null default 'unknown',
  app_version text,
  created_at timestamptz not null default now()
);
create unique index newsletter_subscribers_email_key on public.newsletter_subscribers (lower(email));
alter table public.newsletter_subscribers enable row level security;
create policy "anon can subscribe" on public.newsletter_subscribers
  for insert to anon with check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
```

- [ ] **Step 2: Fetch the publishable key** (`get_publishable_keys`) and `get_project_url`.

- [ ] **Step 3: Write `SupportConfig.swift`**

```swift
import Foundation

/// Public configuration for the Support window. The Supabase key is the
/// publishable (anon) key: it only grants what RLS allows (insert one row).
enum SupportConfig {
    static let supabaseURL = URL(string: "https://txeisrdkgcloqjiqexnw.supabase.co")!
    static let supabasePublishableKey = "<publishable key>"
    static let newsletterSource = "justmd-mac"
    static let coffeeProductID = "com.nuta.JustMD.coffee"
}
```

- [ ] **Step 4: Commit** `feat(support): Supabase config for newsletter`

### Task 2: NewsletterClient

**Files:**
- Create: `JustMD/JustMD/Support/NewsletterClient.swift`
- Test: `JustMD/JustMDTests/NewsletterClientTests.swift`

**Interfaces:**
- Produces:
  ```swift
  protocol NewsletterSubscribing: Sendable { func subscribe(email: String) async throws }
  enum NewsletterError: Error, Equatable { case invalidEmail, server(status: Int), transport }
  final class NewsletterClient: NewsletterSubscribing {
      init(baseURL: URL = SupportConfig.supabaseURL, apiKey: String = SupportConfig.supabasePublishableKey,
           appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
           session: URLSession = .shared)
      static func isValidEmail(_ s: String) -> Bool
      static func normalize(_ s: String) -> String   // trimmed, lowercased
      func makeRequest(email: String) -> URLRequest
      func subscribe(email: String) async throws
  }
  ```

- [ ] **Step 1: Write failing tests**

```swift
import Testing
import Foundation
@testable import JustMD

@Suite("NewsletterClient")
struct NewsletterClientTests {
    @Test("email validation", arguments: [
        ("yuri@example.com", true), ("  Yuri@Example.com ", true), ("a@b.co", true),
        ("", false), ("no-at.com", false), ("a@b", false), ("a b@c.com", false), ("a@@b.com", false),
    ])
    func validation(input: String, expected: Bool) {
        #expect(NewsletterClient.isValidEmail(input) == expected)
    }

    @Test("request shape")
    func request() throws {
        let client = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "KEY", appVersion: "1.1", session: .shared)
        let req = client.makeRequest(email: "  Yuri@Example.com ")
        #expect(req.url?.absoluteString == "https://x.supabase.co/rest/v1/newsletter_subscribers")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "apikey") == "KEY")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer KEY")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(req.value(forHTTPHeaderField: "Prefer") == "return=minimal")
        let body = try #require(req.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json == ["email": "yuri@example.com", "source": "justmd-mac", "app_version": "1.1"])
    }

    @Test("201 and 409 succeed, 500 and transport fail")
    func responses() async throws {
        for (status, expected) in [(201, nil), (409, nil), (500, NewsletterError.server(status: 500))] as [(Int, NewsletterError?)] {
            let client = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "K", appVersion: "1", session: StubURLProtocol.session(status: status))
            do { try await client.subscribe(email: "a@b.co"); #expect(expected == nil) }
            catch let e as NewsletterError { #expect(e == expected) }
        }
        let bad = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "K", appVersion: "1", session: StubURLProtocol.session(status: nil))
        await #expect(throws: NewsletterError.transport) { try await bad.subscribe(email: "a@b.co") }
        let invalid = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "K", appVersion: "1", session: .shared)
        await #expect(throws: NewsletterError.invalidEmail) { try await invalid.subscribe(email: "nope") }
    }
}

/// Serves a canned status for every request; `status == nil` fails the connection.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var status: Int? = 201
    static func session(status: Int?) -> URLSession {
        Self.status = status
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let status = Self.status {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }
    override func stopLoading() {}
}
```

- [ ] **Step 2: Run, expect compile failure** (`NewsletterClient` undefined).

- [ ] **Step 3: Implement**

```swift
import Foundation

protocol NewsletterSubscribing: Sendable {
    func subscribe(email: String) async throws
}

enum NewsletterError: Error, Equatable {
    case invalidEmail
    case server(status: Int)
    case transport
}

/// Inserts one row into Supabase `newsletter_subscribers` through PostgREST.
/// A duplicate email (409) counts as success: the address is on the list.
final class NewsletterClient: NewsletterSubscribing {
    private let baseURL: URL
    private let apiKey: String
    private let appVersion: String
    private let session: URLSession

    init(baseURL: URL = SupportConfig.supabaseURL,
         apiKey: String = SupportConfig.supabasePublishableKey,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
         session: URLSession = .shared) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.appVersion = appVersion; self.session = session
    }

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidEmail(_ raw: String) -> Bool {
        let email = normalize(raw)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix(".") else { return false }
        return !email.contains(where: { $0.isWhitespace })
    }

    func makeRequest(email: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "rest/v1/newsletter_subscribers"))
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "email": Self.normalize(email),
            "source": SupportConfig.newsletterSource,
            "app_version": appVersion,
        ])
        request.timeoutInterval = 15
        return request
    }

    func subscribe(email: String) async throws {
        guard Self.isValidEmail(email) else { throw NewsletterError.invalidEmail }
        let response: URLResponse
        do { (_, response) = try await session.data(for: makeRequest(email: email)) }
        catch { throw NewsletterError.transport }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299, 409: return
        default: throw NewsletterError.server(status: status)
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass.**
- [ ] **Step 5: Commit** `feat(support): NewsletterClient against Supabase PostgREST`

### Task 3: NewsletterViewModel

**Files:**
- Create: `JustMD/JustMD/Support/NewsletterViewModel.swift`
- Test: `JustMD/JustMDTests/NewsletterViewModelTests.swift`

**Interfaces:**
- Consumes: `NewsletterSubscribing`, `NewsletterError`, `NewsletterClient.isValidEmail`.
- Produces:
  ```swift
  @MainActor final class NewsletterViewModel: ObservableObject {
      enum State: Equatable { case idle, sending, subscribed, failed(String) }
      @Published var email: String
      @Published private(set) var state: State
      var canSubmit: Bool
      init(client: NewsletterSubscribing = NewsletterClient(), defaults: UserDefaults = .standard)
      func subscribe() async
  }
  ```
  UserDefaults key `com.justmd.support.subscribedEmail`.

- [ ] **Step 1: Failing tests**

```swift
import Testing
import Foundation
@testable import JustMD

@Suite("NewsletterViewModel") @MainActor
struct NewsletterViewModelTests {
    final class Fake: NewsletterSubscribing, @unchecked Sendable {
        var error: NewsletterError?
        var received: [String] = []
        func subscribe(email: String) async throws { received.append(email); if let error { throw error } }
    }
    func defaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    @Test func success() async {
        let fake = Fake(); let d = defaults()
        let vm = NewsletterViewModel(client: fake, defaults: d)
        vm.email = "a@b.co"
        #expect(vm.canSubmit)
        await vm.subscribe()
        #expect(vm.state == .subscribed)
        #expect(fake.received == ["a@b.co"])
        #expect(NewsletterViewModel(client: fake, defaults: d).state == .subscribed)
    }
    @Test func invalidDoesNotSend() async {
        let fake = Fake()
        let vm = NewsletterViewModel(client: fake, defaults: defaults())
        vm.email = "nope"
        #expect(!vm.canSubmit)
        await vm.subscribe()
        #expect(vm.state == .failed("Enter a valid email address."))
        #expect(fake.received.isEmpty)
    }
    @Test func serverFailureKeepsEmail() async {
        let fake = Fake(); fake.error = .server(status: 500)
        let vm = NewsletterViewModel(client: fake, defaults: defaults())
        vm.email = "a@b.co"
        await vm.subscribe()
        #expect(vm.state == .failed("Couldn't subscribe right now. Try again later."))
        #expect(vm.email == "a@b.co")
    }
    @Test func transportFailure() async {
        let fake = Fake(); fake.error = .transport
        let vm = NewsletterViewModel(client: fake, defaults: defaults())
        vm.email = "a@b.co"
        await vm.subscribe()
        #expect(vm.state == .failed("No connection. Check your network and try again."))
    }
}
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement**

```swift
import Foundation

@MainActor
final class NewsletterViewModel: ObservableObject {
    enum State: Equatable { case idle, sending, subscribed, failed(String) }
    private static let subscribedKey = "com.justmd.support.subscribedEmail"

    @Published var email: String = ""
    @Published private(set) var state: State = .idle
    private let client: NewsletterSubscribing
    private let defaults: UserDefaults

    init(client: NewsletterSubscribing = NewsletterClient(), defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        if let saved = defaults.string(forKey: Self.subscribedKey) {
            email = saved
            state = .subscribed
        }
    }

    var canSubmit: Bool { state != .sending && NewsletterClient.isValidEmail(email) }

    func subscribe() async {
        guard NewsletterClient.isValidEmail(email) else {
            state = .failed("Enter a valid email address."); return
        }
        state = .sending
        do {
            try await client.subscribe(email: email)
            defaults.set(NewsletterClient.normalize(email), forKey: Self.subscribedKey)
            state = .subscribed
        } catch NewsletterError.transport {
            state = .failed("No connection. Check your network and try again.")
        } catch {
            state = .failed("Couldn't subscribe right now. Try again later.")
        }
    }
}
```

- [ ] **Step 4: Run tests, expect pass.**
- [ ] **Step 5: Commit** `feat(support): newsletter view model`

### Task 4: CoffeeStore (StoreKit 2, App Store build only)

**Files:**
- Create: `JustMD/JustMD/Support/CoffeeStore.swift`
- Create: `JustMD/JustMD/Support/JustMD.storekit`
- Modify: `JustMD/JustMD.xcodeproj/xcshareddata/xcschemes/JustMD.xcscheme` (StoreKit configuration for Run)
- Test: `JustMD/JustMDTests/CoffeeStoreTests.swift`

**Interfaces:**
- Produces (all under `#if !DIRECT_DISTRIBUTION`):
  ```swift
  struct CoffeeProduct: Equatable { let id: String; let displayPrice: String }
  enum CoffeePurchaseOutcome { case purchased, cancelled, pending }
  protocol CoffeeProductProviding: Sendable {
      func loadProduct(id: String) async throws -> CoffeeProduct?
      func purchase(id: String) async throws -> CoffeePurchaseOutcome
      var completedPurchases: AsyncStream<Void> { get }   // unfinished transactions drained at launch
  }
  @MainActor final class CoffeeStore: ObservableObject {
      enum State: Equatable { case loading, ready, purchasing, thanked, unavailable, failed(String) }
      @Published private(set) var state: State
      @Published private(set) var product: CoffeeProduct?
      @Published private(set) var coffeeCount: Int
      init(provider: CoffeeProductProviding = StoreKitCoffeeProvider(), defaults: UserDefaults = .standard)
      func load() async
      func buy() async
  }
  ```
  UserDefaults key `com.justmd.support.coffeeCount`.

- [ ] **Step 1: Failing tests**

```swift
#if !DIRECT_DISTRIBUTION
import Testing
import Foundation
@testable import JustMD

@Suite("CoffeeStore") @MainActor
struct CoffeeStoreTests {
    final class Fake: CoffeeProductProviding, @unchecked Sendable {
        var product: CoffeeProduct? = CoffeeProduct(id: SupportConfig.coffeeProductID, displayPrice: "$2.99")
        var outcome: CoffeePurchaseOutcome = .purchased
        var loadError: Error?
        var purchaseError: Error?
        var completedPurchases: AsyncStream<Void> { AsyncStream { $0.finish() } }
        func loadProduct(id: String) async throws -> CoffeeProduct? { if let loadError { throw loadError }; return product }
        func purchase(id: String) async throws -> CoffeePurchaseOutcome { if let purchaseError { throw purchaseError }; return outcome }
    }
    struct Boom: Error {}
    func defaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    @Test func loadsProduct() async {
        let store = CoffeeStore(provider: Fake(), defaults: defaults())
        #expect(store.state == .loading)
        await store.load()
        #expect(store.state == .ready)
        #expect(store.product?.displayPrice == "$2.99")
    }
    @Test func missingProductIsUnavailable() async {
        let fake = Fake(); fake.product = nil
        let store = CoffeeStore(provider: fake, defaults: defaults())
        await store.load()
        #expect(store.state == .unavailable)
        let failing = Fake(); failing.loadError = Boom()
        let store2 = CoffeeStore(provider: failing, defaults: defaults())
        await store2.load()
        #expect(store2.state == .unavailable)
    }
    @Test func purchaseIncrementsAndCanRepeat() async {
        let d = defaults()
        let store = CoffeeStore(provider: Fake(), defaults: d)
        await store.load()
        await store.buy(); await store.buy()
        #expect(store.state == .thanked)
        #expect(store.coffeeCount == 2)
        #expect(CoffeeStore(provider: Fake(), defaults: d).coffeeCount == 2)
    }
    @Test func cancelAndPendingAndError() async {
        let fake = Fake(); fake.outcome = .cancelled
        let store = CoffeeStore(provider: fake, defaults: defaults())
        await store.load(); await store.buy()
        #expect(store.state == .ready); #expect(store.coffeeCount == 0)
        fake.outcome = .pending
        await store.buy()
        #expect(store.state == .failed("Purchase is awaiting approval."))
        fake.purchaseError = Boom()
        await store.buy()
        #expect(store.state == .failed("The purchase didn't go through. Try again."))
    }
}
#endif
```

- [ ] **Step 2: Run, expect failure.**
- [ ] **Step 3: Implement `CoffeeStore.swift`**

```swift
#if !DIRECT_DISTRIBUTION
import Foundation
import StoreKit

struct CoffeeProduct: Equatable, Sendable {
    let id: String
    let displayPrice: String
}

enum CoffeePurchaseOutcome: Sendable { case purchased, cancelled, pending }

protocol CoffeeProductProviding: Sendable {
    func loadProduct(id: String) async throws -> CoffeeProduct?
    func purchase(id: String) async throws -> CoffeePurchaseOutcome
    /// Emits once per consumable finished outside `purchase(id:)` (e.g. a
    /// transaction interrupted by a crash and delivered at the next launch).
    var completedPurchases: AsyncStream<Void> { get }
}

/// Real StoreKit 2 provider. Products are cached per id.
final class StoreKitCoffeeProvider: CoffeeProductProviding {
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
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: return .cancelled
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
        func store(_ p: Product) { products[p.id] = p }
        func product(for id: String) -> Product? { products[id] }
    }
}

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
            if let p = try await provider.loadProduct(id: SupportConfig.coffeeProductID) {
                product = p
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
```

- [ ] **Step 4: `JustMD.storekit`** (Xcode StoreKit configuration JSON with one consumable `com.nuta.JustMD.coffee`, $2.99, en_US "Buy me a coffee"). Reference it in the scheme's `LaunchAction` via `<StoreKitConfigurationFileReference identifier = "../../JustMD/Support/JustMD.storekit">`.
- [ ] **Step 5: Run tests, expect pass. Build with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION'` and confirm it still compiles.**
- [ ] **Step 6: Commit** `feat(support): CoffeeStore consumable over StoreKit 2`

### Task 5: SupportView + window + entry points

**Files:**
- Create: `JustMD/JustMD/Support/SupportView.swift`, `JustMD/JustMD/Support/SupportWindowController.swift`
- Modify: `JustMD/JustMD/App/AppDelegate.swift` (add `installSupportMenuItem()` + `showSupport(_:)`)
- Modify: `JustMD/JustMD/Welcome/WelcomeView.swift` (add `onSupport: () -> Void` and a small text button), `WelcomeWindowController.swift` (pass the closure)
- Test: `JustMD/JustMDTests/WelcomeTests.swift` (adjust construction if it builds `WelcomeView`)

**Interfaces:**
- Consumes: `NewsletterViewModel`, `CoffeeStore` (gated).
- Produces: `SupportWindowController.shared.showWindow(_:)`; `AppDelegate.showSupport(_:)`.

- [ ] **Step 1: `SupportView.swift`**

```swift
import SwiftUI

@MainActor
struct SupportView: View {
    @StateObject private var newsletter = NewsletterViewModel()
    #if !DIRECT_DISTRIBUTION
    @StateObject private var coffee = CoffeeStore()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Support JustMD")
                    .font(.system(size: 28, weight: .light, design: .serif))
                Text("JustMD is free and made by one person. Here are two ways to help.")
                    .foregroundStyle(.secondary)
            }
            newsletterSection
            #if !DIRECT_DISTRIBUTION
            if coffee.state != .unavailable { coffeeSection }
            #endif
        }
        .padding(32)
        .frame(width: 440)
        .task {
            #if !DIRECT_DISTRIBUTION
            await coffee.load()
            #endif
        }
    }

    private var newsletterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get updates").font(.headline)
            Text("Occasional emails about new versions. No spam, unsubscribe anytime.")
                .font(.callout).foregroundStyle(.secondary)
            if newsletter.state == .subscribed {
                Label("You're on the list: \(newsletter.email)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField("you@example.com", text: $newsletter.email)
                        .textFieldStyle(.roundedBorder)
                        .disabled(newsletter.state == .sending)
                        .onSubmit { Task { await newsletter.subscribe() } }
                    Button(newsletter.state == .sending ? "Sending…" : "Subscribe") {
                        Task { await newsletter.subscribe() }
                    }
                    .disabled(!newsletter.canSubmit)
                    .keyboardShortcut(.defaultAction)
                }
                if case .failed(let message) = newsletter.state {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }
        }
    }

    #if !DIRECT_DISTRIBUTION
    private var coffeeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Buy me a coffee").font(.headline)
            Text("A small thank-you that keeps the editor going. Buy as many as you like.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    Task { await coffee.buy() }
                } label: {
                    Label(buttonTitle, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(coffee.state == .loading || coffee.state == .purchasing)
                if coffee.coffeeCount > 0 {
                    Text("☕️ × \(coffee.coffeeCount) — thank you!").foregroundStyle(.secondary)
                }
            }
            if case .failed(let message) = coffee.state {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var buttonTitle: String {
        switch coffee.state {
        case .loading: return "Loading…"
        case .purchasing: return "Purchasing…"
        default: return "Buy me a coffee · \(coffee.product?.displayPrice ?? "")"
        }
    }
    #endif
}
```

- [ ] **Step 2: `SupportWindowController.swift`** (copy of `PreferencesWindowController` shape, title "Support JustMD", `NSHostingController(rootView: SupportView())`, `setContentSize(fittingSize)`).
- [ ] **Step 3: AppDelegate**: in `applicationDidFinishLaunching` call `installSupportMenuItem()`; it finds the "Help" submenu and appends a separator + "Support JustMD…" targeting `showSupport(_:)`, which calls `SupportWindowController.shared.showWindow(sender)`.
- [ ] **Step 4: Welcome**: add `let onSupport: () -> Void` to `WelcomeView`; below the recents (or after the buttons when empty) add
  ```swift
  Button("Support JustMD") { onSupport() }.buttonStyle(.link).font(.system(size: 12)).foregroundStyle(.secondary)
  ```
  Pass `onSupport: { SupportWindowController.shared.showWindow(nil) }` from `WelcomeWindowController`. Fix any test that constructs `WelcomeView`.
- [ ] **Step 5: Build and run the full test suite.** Open the app, Help → Support JustMD…, subscribe a test address, verify the row in Supabase (`execute_sql`), buy a coffee in the Debug scheme with the StoreKit config.
- [ ] **Step 6: Commit** `feat(support): Support window, Help menu item, Welcome link`

### Task 6: Build settings, DMG gate, ASC product, docs

**Files:**
- Modify: `JustMD/JustMD.xcodeproj/project.pbxproj` (`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`, `MARKETING_VERSION = 1.1` in both app configs)
- Modify: `scripts/release-devid.sh` (`VER=1.1`, add `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION'` to the archive step)
- Modify: `README.md` (Architecture table row `Support/`; License line), `docs/distribution.md` (1.1 section), `docs/roadmap.md` (1.1 entry)
- ASC via MCP: `create_iap` consumable on app `6779422717`, `set_iap_localization` en-US, `set_iap_price` $2.99.

- [ ] **Step 1: pbxproj edits with `sed`; verify with `grep`.**
- [ ] **Step 2: release script edit; run `xcodebuild … build SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION'` to confirm the gated build compiles.**
- [ ] **Step 3: Create the IAP in ASC, then list to confirm.**
- [ ] **Step 4: Docs.**
- [ ] **Step 5: Full test run, commit** `feat(support): network entitlement, 1.1, DMG gate, ASC coffee product`

## Self-review

- Spec coverage: window + entry points (T5), newsletter flow + schema + entitlement (T1–T3, T6), purchase flow + listener + storekit file + ASC (T4, T6), DMG gate (T6), error handling (T3/T4 messages), tests (T2–T4), docs (T6). Follow-ups (privacy labels, policy page) stay out of scope as specified.
- Types: `CoffeeProductProviding`, `CoffeePurchaseOutcome`, `NewsletterSubscribing`, `NewsletterError` used consistently across tasks.
