import AppKit

@MainActor
final class DocumentViewController: NSViewController {
    let document: MarkdownDocument
    private let storage = MarkdownTextStorage()
    private let parser = MarkdownParser()
    private(set) var textView: MarkdownTextView?
    private var scrollView: NSScrollView?

    static let readModeDidChangeNotification = Notification.Name("com.justmd.readModeDidChange")

    private(set) var isReadMode = false
    private var readTextView: NSTextView?
    private lazy var readRenderer = MarkdownReadRenderer(codeHighlighter: readCodeHighlighter)
    private let readCodeHighlighter = CodeBlockHighlighter()

    init(document: MarkdownDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    private var appearanceObservation: NSKeyValueObservation?

    deinit {
        NotificationCenter.default.removeObserver(self)
        // NSKeyValueObservation auto-invalidates on deallocation; no manual
        // invalidate() call here because Swift 6 treats the deinit as
        // nonisolated and can't touch main-actor properties.
    }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true

        let highlighter = SyntaxHighlighter(parser: parser)
        highlighter.codeHighlighter = CodeBlockHighlighter()
        storage.highlighter = highlighter
        storage.highlightContext = makeContext()

        let textView = MarkdownTextView(storage: storage)
        textView.frame = scroll.contentView.bounds
        textView.minSize = NSSize(width: 0, height: scroll.contentView.bounds.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        scroll.documentView = textView

        // Load document text into storage. Apply highlighting synchronously so
        // the file renders fully styled on first paint — the 200ms debounce
        // would otherwise cause a visible blank flash on open.
        if !document.text.isEmpty {
            storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: document.text)
            storage.applyHighlightingNow()
        }

        // Forward storage edits back to document.text + change count.
        storage.delegate = self

        self.textView = textView
        self.scrollView = scroll
        self.view = scroll

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesDidChange),
            name: PreferencesStore.didChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentDidReload(_:)),
            name: MarkdownDocument.didReloadNotification,
            object: document
        )
        // Re-render when the effective appearance flips (system dark-mode toggle
        // or user-chosen "Follow System"). KVO is the simplest path because
        // `viewDidChangeEffectiveAppearance` is declared on `NSView`, not on
        // `NSViewController`.
        appearanceObservation = textView.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.rebuildContext()
            }
        }

        rebuildContext()
    }

    @objc private func preferencesDidChange() {
        rebuildContext()
    }

    @objc private func documentDidReload(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let newText = self.document.text
            let currentLen = self.storage.length
            // Avoid notifying the storage delegate recursively — the storage
            // will post an editedCharacters event that funnels back through
            // NSTextStorageDelegate and would re-set document.text to the same
            // value it just got from disk. That's a no-op, but still noisy.
            self.storage.replaceCharacters(
                in: NSRange(location: 0, length: currentLen),
                with: newText
            )
            self.storage.applyHighlightingNow()
            if self.isReadMode { self.renderReadView() }
        }
    }

    // MARK: - Read mode

    @objc func toggleReadMode(_ sender: Any?) {
        setReadMode(!isReadMode)
    }

    func setReadMode(_ read: Bool) {
        guard read != isReadMode, let scrollView else { return }
        isReadMode = read
        if read {
            let readView = makeReadTextViewIfNeeded()
            renderReadView()
            scrollView.documentView = readView
            view.window?.makeFirstResponder(readView)
        } else if let textView {
            scrollView.documentView = textView
            view.window?.makeFirstResponder(textView)
        }
        NotificationCenter.default.post(name: Self.readModeDidChangeNotification, object: self)
    }

    private func makeReadTextViewIfNeeded() -> NSTextView {
        if let readTextView { return readTextView }
        // Explicit TextKit 1 stack: NSTextTable rendering and our layout
        // manager chrome (quote bar, HR rule) both live there.
        let readStorage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        readStorage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 720, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        let readView = NSTextView(frame: scrollView?.contentView.bounds ?? .zero, textContainer: container)
        readView.isEditable = false
        readView.isRichText = true
        readView.usesFindBar = true
        readView.textContainerInset = NSSize(width: 40, height: 32)
        readView.minSize = NSSize(width: 0, height: scrollView?.contentView.bounds.height ?? 0)
        readView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        readView.isVerticallyResizable = true
        readView.isHorizontallyResizable = false
        readView.autoresizingMask = [.width]
        readView.backgroundColor = textView?.backgroundColor ?? .textBackgroundColor
        readView.linkTextAttributes = textView?.linkTextAttributes ?? [:]
        self.readTextView = readView
        return readView
    }

    private func renderReadView() {
        guard let readTextView, let context = storage.highlightContext else { return }
        let rendered = readRenderer.render(
            document.text,
            context: context,
            baseURL: document.fileURL?.deletingLastPathComponent()
        )
        readTextView.textStorage?.setAttributedString(rendered)
        readTextView.backgroundColor = textView?.backgroundColor ?? readTextView.backgroundColor
    }

    private func rebuildContext() {
        let prefs = PreferencesStore.shared
        let themeStore = ThemeStore()
        let theme = themeStore.loadAll().first(where: { $0.id == prefs.themeId })
            ?? BuiltinThemes.all.first
            ?? BuiltinThemes.all.first!
        let palette = activePalette(for: theme)

        let size = CGFloat(prefs.fontSize)
        let baseFont = PreferencesStore.nsFont(family: prefs.fontFamily, size: size)
        let codeFont = PreferencesStore.nsFont(family: .mono, size: max(10, size * 0.92))

        storage.highlightContext = HighlightContext(
            baseFont: baseFont,
            textColor: NSColor.fromHex(palette.text) ?? .labelColor,
            secondaryColor: NSColor.fromHex(palette.secondary) ?? .secondaryLabelColor,
            accentColor: NSColor.fromHex(palette.accent) ?? .controlAccentColor,
            codeFont: codeFont,
            codeBackground: NSColor.fromHex(palette.codeBackground) ?? NSColor(white: 0.95, alpha: 1)
        )
        if let bg = NSColor.fromHex(palette.background) {
            textView?.backgroundColor = bg
            scrollView?.backgroundColor = bg
        }
        if let accent = NSColor.fromHex(palette.accent) {
            textView?.linkTextAttributes = [
                .foregroundColor: accent,
                .underlineStyle: 0
            ]
        }
        if let selection = NSColor.fromHex(palette.selection) {
            textView?.selectedTextAttributes = [
                .backgroundColor: selection
            ]
        }
        storage.applyHighlightingNow()
        if isReadMode { renderReadView() }
    }

    private func activePalette(for theme: Theme) -> Palette {
        if theme.id == "builtin.followSystem" {
            let match = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])
            let isDark = match == .darkAqua
            return isDark ? (theme.dark ?? theme.light) : theme.light
        }
        return theme.light
    }

    private func makeContext() -> HighlightContext {
        return HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
    }
}

extension DocumentViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleReadMode(_:)) {
            menuItem.state = isReadMode ? .on : .off
        }
        return true
    }
}

extension DocumentViewController: NSTextStorageDelegate {
    nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        let snapshot = textStorage.string
        Task { @MainActor in
            self.document.text = snapshot
            self.document.updateChangeCount(.changeDone)
        }
    }
}
