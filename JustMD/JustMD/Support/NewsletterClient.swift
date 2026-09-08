import Foundation

nonisolated protocol NewsletterSubscribing: Sendable {
    func subscribe(email: String) async throws
}

nonisolated enum NewsletterError: Error, Equatable {
    case invalidEmail
    case server(status: Int)
    case transport
}

/// Inserts one row into Supabase `newsletter_subscribers` through PostgREST.
/// A duplicate email (409) counts as success: the address is on the list.
nonisolated final class NewsletterClient: NewsletterSubscribing {
    private let baseURL: URL
    private let apiKey: String
    private let appVersion: String
    private let session: URLSession

    init(baseURL: URL = SupportConfig.supabaseURL,
         apiKey: String = SupportConfig.supabasePublishableKey,
         appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.appVersion = appVersion
        self.session = session
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
        do {
            (_, response) = try await session.data(for: makeRequest(email: email))
        } catch {
            throw NewsletterError.transport
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200...299, 409: return
        default: throw NewsletterError.server(status: status)
        }
    }
}
