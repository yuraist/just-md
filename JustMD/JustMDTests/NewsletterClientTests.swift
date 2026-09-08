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

    @Test("201 and 409 succeed, 500 fails")
    func statusMapping() async throws {
        let cases: [(Int, NewsletterError?)] = [(201, nil), (409, nil), (500, .server(status: 500))]
        for (status, expected) in cases {
            let client = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "K", appVersion: "1",
                                          session: StubURLProtocol.session(status: status))
            do {
                try await client.subscribe(email: "a@b.co")
                #expect(expected == nil, "status \(status)")
            } catch let error as NewsletterError {
                #expect(error == expected, "status \(status)")
            }
        }
    }

    @Test("transport failure and invalid email")
    func failures() async {
        let bad = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "K", appVersion: "1",
                                   session: StubURLProtocol.session(status: nil))
        await #expect(throws: NewsletterError.transport) { try await bad.subscribe(email: "a@b.co") }
        let invalid = NewsletterClient(baseURL: URL(string: "https://x.supabase.co")!, apiKey: "K", appVersion: "1", session: .shared)
        await #expect(throws: NewsletterError.invalidEmail) { try await invalid.subscribe(email: "nope") }
    }
}

/// Serves a canned status for every request; `status == nil` fails the connection.
/// Each session carries its own status in `URLProtocol.property` so the
/// parameterized tests can run in parallel.
final class StubURLProtocol: URLProtocol {
    private static let key = "StubURLProtocol.status"

    static func session(status: Int?) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Stub-Status": status.map(String.init) ?? "fail"]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let raw = request.value(forHTTPHeaderField: "X-Stub-Status") ?? "fail"
        if let status = Int(raw) {
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {}
}
