import Combine
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
            state = .failed("Enter a valid email address.")
            return
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
