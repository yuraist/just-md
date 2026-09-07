import AppKit

/// Security-scoped folder grants for Read mode images.
///
/// The App Sandbox lets JustMD read exactly the file the user opened, so an
/// image referenced next to the document (`![](diagram.png)`) is unreadable
/// until the user allows the folder once. Grants are stored as security-
/// scoped bookmarks keyed by folder path and re-activated on demand.
@MainActor
final class FolderAccess {
    static let shared = FolderAccess()

    /// URL scheme of the "Allow access" link the reader shows in place of an
    /// unreadable local image.
    static let grantScheme = "justmd-grant"

    private let defaultsKey = "com.justmd.folderBookmarks"
    private let defaults: UserDefaults

    /// Folders whose security scope is currently open, by standardized path.
    private var active: [String: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: Links

    static func grantLink(for folder: URL) -> URL? {
        var components = URLComponents()
        components.scheme = grantScheme
        components.host = "folder"
        components.path = folder.standardizedFileURL.path
        return components.url
    }

    static func folder(fromGrantLink link: Any?) -> URL? {
        let url: URL?
        if let u = link as? URL { url = u } else if let s = link as? String { url = URL(string: s) } else { url = nil }
        guard let url, url.scheme == grantScheme, !url.path.isEmpty else { return nil }
        return URL(fileURLWithPath: url.path, isDirectory: true)
    }

    // MARK: Grants

    /// True when `folder` (or an ancestor) has a stored grant; opens its
    /// security scope so file reads inside it succeed.
    @discardableResult
    func activateGrant(for folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        if active.keys.contains(where: { Self.path(path, isInside: $0) }) { return true }
        for (storedPath, data) in storedBookmarks() where Self.path(path, isInside: storedPath) {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            if url.startAccessingSecurityScopedResource() {
                active[storedPath] = url
                return true
            }
        }
        return false
    }

    /// Asks the user to allow `folder` through an open panel (a sheet on
    /// `window` when given) and stores the resulting bookmark.
    func requestGrant(for folder: URL, from window: NSWindow?, completion: @escaping @MainActor (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = "Allow"
        panel.message = "Allow JustMD to show images from this folder."
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .OK, let url = panel.url else {
                    completion(false)
                    return
                }
                completion(self.store(grantFor: url))
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    /// Persists a security-scoped bookmark for `folder` and opens its scope.
    @discardableResult
    func store(grantFor folder: URL) -> Bool {
        do {
            let data = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var bookmarks = storedBookmarks()
            let path = folder.standardizedFileURL.path
            bookmarks[path] = data
            defaults.set(bookmarks, forKey: defaultsKey)
            if folder.startAccessingSecurityScopedResource() {
                active[path] = folder
            }
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    private func storedBookmarks() -> [String: Data] {
        (defaults.dictionary(forKey: defaultsKey) as? [String: Data]) ?? [:]
    }

    private static func path(_ path: String, isInside folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }
}
