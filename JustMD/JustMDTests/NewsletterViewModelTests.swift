import Testing
import Foundation
@testable import JustMD

@Suite("NewsletterViewModel")
@MainActor
struct NewsletterViewModelTests {
    final class Fake: NewsletterSubscribing, @unchecked Sendable {
        var error: NewsletterError?
        var received: [String] = []
        func subscribe(email: String) async throws {
            received.append(email)
            if let error { throw error }
        }
    }

    private func defaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    @Test func success() async {
        let fake = Fake()
        let d = defaults()
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
        let fake = Fake()
        fake.error = .server(status: 500)
        let vm = NewsletterViewModel(client: fake, defaults: defaults())
        vm.email = "a@b.co"
        await vm.subscribe()
        #expect(vm.state == .failed("Couldn't subscribe right now. Try again later."))
        #expect(vm.email == "a@b.co")
    }

    @Test func transportFailure() async {
        let fake = Fake()
        fake.error = .transport
        let vm = NewsletterViewModel(client: fake, defaults: defaults())
        vm.email = "a@b.co"
        await vm.subscribe()
        #expect(vm.state == .failed("No connection. Check your network and try again."))
    }
}
