import Foundation

nonisolated public enum BuiltinThemes {
    public static let all: [Theme] = {
        let names = ["follow-system", "white", "sepia", "gray", "black"]
        return names.compactMap { name in
            guard let url = bundle.url(forResource: name, withExtension: "justmd-theme") else {
                assertionFailure("Missing builtin theme resource: \(name)")
                return nil
            }
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(Theme.self, from: data)
            } catch {
                assertionFailure("Failed to decode builtin theme \(name): \(error)")
                return nil
            }
        }
    }()

    // Resolve the bundle that ships with the built-in theme resources.
    // Using a marker class keeps this correct in both app runtime and test-host contexts,
    // since `Bundle.main` in a test run can be the test runner rather than the app bundle.
    private static let bundle: Bundle = Bundle(for: BundleMarker.self)
    private final class BundleMarker {}
}
