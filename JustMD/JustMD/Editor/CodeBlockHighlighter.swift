import AppKit
import Highlightr

/// Box for moving an immutable value across an explicit queue hop. Highlightr
/// returns `NSAttributedString`, which is not formally `Sendable`; instances
/// produced here are never mutated after creation.
nonisolated private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

/// Wraps `Highlightr` to provide syntax-highlighted `NSAttributedString`s
/// for code blocks. Uses the "github" theme and fast HTML rendering.
///
/// Highlighting runs a JSContext call (~5–50 ms per block), far too slow for
/// the per-keystroke highlight pass. Results are cached by (code, language)
/// on the main thread, and misses are computed on a serial background queue —
/// the editor pass applies cached colors synchronously and schedules a re-apply
/// when an async result lands.
/// `@unchecked Sendable`: `engine` is confined to `queue`, `cache`/`inFlight`
/// are confined to the main thread.
nonisolated final class CodeBlockHighlighter: @unchecked Sendable {
    private struct Key: Hashable {
        let code: String
        let language: String?
    }

    /// JSContext work is confined to this queue; `Highlightr` is not
    /// thread-safe across concurrent calls.
    private let queue = DispatchQueue(label: "com.justmd.codeblock-highlight", qos: .userInitiated)
    private let engine: Highlightr

    /// Main-thread only.
    private var cache: [Key: NSAttributedString] = [:]
    private var inFlight: Set<Key> = []

    init() {
        guard let h = Highlightr() else {
            preconditionFailure("Highlightr failed to initialize")
        }
        self.engine = h
        _ = h.setTheme(to: "github")
    }

    /// Synchronous highlight, bypassing the cache. Kept for tests and one-off
    /// rendering (Read mode caches at a higher level).
    func highlight(_ code: String, language: String?) -> NSAttributedString? {
        if let language, !language.isEmpty {
            return engine.highlight(code, as: language, fastRender: true)
        } else {
            return engine.highlight(code, as: nil, fastRender: true)
        }
    }

    /// Returns the cached result for this code/language, if any. Main thread.
    func cachedHighlight(_ code: String, language: String?) -> NSAttributedString? {
        cache[Key(code: code, language: language)]
    }

    /// Computes the highlight on the background queue and delivers the result
    /// (also stored in the cache) on the main queue. Duplicate requests for an
    /// in-flight key are dropped — the first completion serves them all via a
    /// follow-up highlight pass. Main thread.
    func highlightAsync(
        _ code: String,
        language: String?,
        completion: @escaping @MainActor (NSAttributedString?) -> Void
    ) {
        let key = Key(code: code, language: language)
        if let hit = cache[key] {
            // Callers are on the main thread by contract; assumeIsolated makes
            // that contract checkable instead of silently assumed.
            MainActor.assumeIsolated { completion(hit) }
            return
        }
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        queue.async { [weak self] in
            guard let self else { return }
            let result = UncheckedSendable(value: self.highlight(code, language: language))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.inFlight.remove(key)
                    if let value = result.value {
                        if self.cache.count > 256 { self.cache.removeAll(keepingCapacity: true) }
                        self.cache[key] = value
                    }
                    completion(result.value)
                }
            }
        }
    }
}
