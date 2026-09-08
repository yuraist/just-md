#if !DIRECT_DISTRIBUTION
import Testing
import Foundation
import AppKit
import SwiftUI
import StoreKit
import StoreKitTest
@testable import JustMD

/// Exercises the real StoreKit provider against the local `JustMD.storekit`
/// configuration, and renders the Support window to a PNG artifact
/// (`NSTemporaryDirectory()/support-window.png`, readable from
/// `~/Library/Containers/com.nuta.JustMD/Data/tmp/`).
@Suite("Support QA", .serialized)
@MainActor
struct SupportQATests {
    private static func makeSession() throws -> SKTestSession {
        let url = Bundle(for: SessionAnchor.self).url(forResource: "JustMD", withExtension: "storekit")
        let session = try url.map { try SKTestSession(contentsOf: $0) }
            ?? SKTestSession(configurationFileNamed: "JustMD")
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test("real provider loads the coffee product and completes a purchase twice")
    func storeKitRoundTrip() async throws {
        let session = try Self.makeSession()
        defer { session.clearTransactions() }
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let store = CoffeeStore(provider: StoreKitCoffeeProvider(), defaults: defaults)
        await store.load()
        #expect(store.state == .ready)
        #expect(store.product?.id == SupportConfig.coffeeProductID)
        #expect(store.product?.displayPrice.contains("2.99") == true)

        await store.buy()
        #expect(store.state == .thanked)
        await store.buy()
        #expect(store.state == .thanked)
        #expect(store.coffeeCount == 2)
        #expect(session.allTransactions().count == 2)
    }

    @Test("Support window renders to a 1280x800 PNG artifact with the live price")
    func renderArtifact() async throws {
        let session = try Self.makeSession()
        defer { session.clearTransactions() }
        // Host the view in an (offscreen) window so `.task` runs and the
        // StoreKit product loads; centre the 440pt view on a 640x400 canvas
        // so the 2x render is the 1280x800 the IAP review screenshot needs.
        let canvas = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let hosting = NSHostingView(rootView: SupportView())
        hosting.frame = NSRect(x: 100, y: 10, width: 440, height: 380)
        canvas.addSubview(hosting)
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 640, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = canvas
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        canvas.layoutSubtreeIfNeeded()
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        let png = try #require(rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]))
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("support-window.png")
        try png.write(to: url)
        #expect(png.count > 5_000)
    }
}

private final class SessionAnchor {}
#endif
