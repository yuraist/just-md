import AppKit
import Testing
@testable import JustMD

/// Not a test of correctness — a screenshot factory. Renders the document
/// view offscreen (the same path the render-artifact tests verify), draws
/// macOS window chrome around it by hand, and composites onto a gradient
/// backdrop at exactly 2880×1800 px — the Mac App Store retina size.
/// Rendering a real NSWindow offscreen doesn't work: a toolbar window is
/// layer-backed and its layers never draw without being on screen.
/// Output lands in NSTemporaryDirectory() (the sandboxed container's tmp).
@Suite("App Store screenshots", .serialized)
@MainActor
struct AppStoreScreenshots {

    static let demo = """
    # Quarterly Planning

    Notes from the **product sync** — *edited live in JustMD*. Syntax markers \
    hide while you write; the caret line shows them again. ~~No clutter.~~

    ## This week

    - Ship the onboarding flow with a [press kit](https://example.com/press)
    - Review `RenderPipeline.swift` before the freeze
    - [x] Draft the announcement post
    - [ ] Book the launch retro

    > The best interface is the one that disappears.

    ## Release checklist

    | Step | Owner | Status |
    |------|-------|--------|
    | Beta feedback triage | Ana | Done |
    | App Store screenshots | Lev | In review |
    | Localization pass | Mia | Planned |

    ## Launch script

    ```swift
    let release = Plan(version: "1.0")
    release.ship(when: .ready)
    ```
    """

    private func makeContext() -> HighlightContext {
        HighlightContext(
            baseFont: NSFont.systemFont(ofSize: 16),
            textColor: .labelColor,
            secondaryColor: .secondaryLabelColor,
            accentColor: .controlAccentColor,
            codeFont: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            codeBackground: NSColor(white: 0.95, alpha: 1)
        )
    }

    @Test("editor window screenshot")
    func editorScreenshot() throws {
        let storage = MarkdownTextStorage()
        storage.highlighter = SyntaxHighlighter(parser: MarkdownParser())
        storage.highlightContext = makeContext()
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: Self.demo)
        storage.applyHighlightingNow()
        let view = MarkdownTextView(storage: storage)
        view.frame = NSRect(x: 0, y: 0, width: 1060, height: 716)
        // Caret on the heading: one line shows live markers — the hybrid
        // editing pitch in a single image.
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        try renderShot(content: view, toolbarSymbol: "book", filename: "appstore-1-editor.png")
    }

    @Test("read mode window screenshot")
    func readModeScreenshot() throws {
        let rendered = MarkdownReadRenderer().render(Self.demo, context: makeContext())
        let storage = NSTextStorage()
        let layoutManager = MarkdownLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 980, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 1060, height: 716), textContainer: container)
        view.isEditable = false
        view.textContainerInset = NSSize(width: 40, height: 32)
        storage.setAttributedString(rendered)
        layoutManager.ensureLayout(for: container)
        try renderShot(content: view, toolbarSymbol: "pencil", filename: "appstore-2-read.png")
    }

    // MARK: - Compositor

    private func renderShot(content: NSView, toolbarSymbol: String, filename: String) throws {
        content.appearance = NSAppearance(named: .aqua)
        let contentRep = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: contentRep)

        let canvasW = 2880, canvasH = 1800
        // 32-bit RGBA: CGBitmapContext can't wrap 24-bit packed RGB, so an
        // alpha channel is required — the gradient fills every pixel opaque.
        let canvas = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: canvasW, pixelsHigh: canvasH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        canvas.size = NSSize(width: canvasW, height: canvasH)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = try #require(NSGraphicsContext(bitmapImageRep: canvas))
        defer { NSGraphicsContext.restoreGraphicsState() }

        let full = NSRect(x: 0, y: 0, width: canvasW, height: canvasH)
        let gradient = try #require(NSGradient(
            starting: NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.97, alpha: 1),
            ending: NSColor(calibratedRed: 0.82, green: 0.86, blue: 0.93, alpha: 1)
        ))
        gradient.draw(in: full, angle: -70)

        // All chrome geometry in canvas pixels (2× the window's point size).
        let titlebarH: CGFloat = 88
        let windowRect = NSRect(
            x: (CGFloat(canvasW) - content.bounds.width * 2) / 2,
            y: (CGFloat(canvasH) - (content.bounds.height * 2 + titlebarH)) / 2,
            width: content.bounds.width * 2,
            height: content.bounds.height * 2 + titlebarH
        )
        let windowPath = NSBezierPath(roundedRect: windowRect, xRadius: 20, yRadius: 20)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
        shadow.shadowBlurRadius = 48
        shadow.shadowOffset = NSSize(width: 0, height: -24)
        NSGraphicsContext.current?.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        windowPath.fill()
        NSGraphicsContext.current?.restoreGraphicsState()

        NSGraphicsContext.current?.saveGraphicsState()
        windowPath.addClip()
        contentRep.draw(
            in: NSRect(x: windowRect.minX, y: windowRect.minY,
                       width: windowRect.width, height: windowRect.height - titlebarH),
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false,
            hints: [.interpolation: NSImageInterpolation.high.rawValue]
        )
        NSGraphicsContext.current?.restoreGraphicsState()

        // Traffic lights: 12 pt circles centered 20/40/60 pt from the left
        // edge, vertically centered in the titlebar.
        let lightColors = [
            NSColor(calibratedRed: 1.00, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.25, alpha: 1),
        ]
        let lightY = windowRect.maxY - titlebarH / 2
        for (i, color) in lightColors.enumerated() {
            let cx = windowRect.minX + CGFloat(40 + i * 40)
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: cx - 12, y: lightY - 12, width: 24, height: 24)).fill()
        }

        // Read/Edit toggle in the toolbar corner, like the real window.
        if let symbol = NSImage(
            systemSymbolName: toolbarSymbol, accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 30, weight: .regular)) {
            let tinted = NSImage(size: symbol.size, flipped: false) { rect in
                symbol.draw(in: rect)
                NSColor.secondaryLabelColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            let iconSize = NSSize(width: symbol.size.width, height: symbol.size.height)
            tinted.draw(in: NSRect(
                x: windowRect.maxX - 36 - iconSize.width,
                y: lightY - iconSize.height / 2,
                width: iconSize.width, height: iconSize.height
            ))
        }

        // Guard against the blank-window failure mode: real text must leave
        // a meaningful number of dark pixels inside the content area.
        var darkPixels = 0
        for y in stride(from: Int(CGFloat(canvasH) - windowRect.maxY) + 100,
                        to: Int(CGFloat(canvasH) - windowRect.minY) - 100, by: 8) {
            for x in stride(from: Int(windowRect.minX) + 100,
                            to: Int(windowRect.maxX) - 100, by: 8) {
                if let c = canvas.colorAt(x: x, y: y), c.brightnessComponent < 0.5 {
                    darkPixels += 1
                }
            }
        }
        #expect(darkPixels > 500, "content area looks blank — window render regressed")

        let png = try #require(canvas.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try png.write(to: url)
    }
}
