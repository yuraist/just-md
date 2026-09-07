#!/usr/bin/env swift
// App Store screenshot compositor for JustMD.
//
//   swift compose.swift --list
//       Print JustMD's windows (id, title, bounds in points), front to back.
//
//   swift compose.swift --out shot.png --caption "Text" --window <id> [--window <id> …]
//       Capture each window with `screencapture -l` (no shadow, at the
//       display's backing scale), keep their relative placement, and lay the
//       group on a flat background under one caption at 2880×1800 — the Mac
//       App Store 16:10 retina size. Sheets (print dialog, open panel) are
//       separate windows: pass their ids too.
//
// Options: --bg RRGGBB (default EBEBED), --fg RRGGBB (default 1D1D1F),
//          --font-size px (default 84), --top px (default 132).
import AppKit

struct Options {
    var out = ""
    var caption = ""
    var bg = "EBEBED"
    var fg = "1D1D1F"
    var fontSize: CGFloat = 84
    var top: CGFloat = 132
    var windows: [CGWindowID] = []
    var list = false
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(1)
}

func parse() -> Options {
    var o = Options()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    func value(_ flag: String) -> String {
        guard let v = it.next() else { fail("\(flag) needs a value") }
        return v
    }
    while let a = it.next() {
        switch a {
        case "--list": o.list = true
        case "--out": o.out = value(a)
        case "--caption": o.caption = value(a)
        case "--bg": o.bg = value(a)
        case "--fg": o.fg = value(a)
        case "--font-size": o.fontSize = CGFloat(Double(value(a)) ?? 84)
        case "--top": o.top = CGFloat(Double(value(a)) ?? 132)
        case "--window":
            guard let id = CGWindowID(value(a)) else { fail("bad window id") }
            o.windows.append(id)
        default: fail("unknown option \(a)")
        }
    }
    return o
}

func color(_ hex: String) -> NSColor {
    var v: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&v)
    return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}

struct WindowInfo {
    let id: CGWindowID
    let title: String
    let bounds: CGRect   // points, origin top-left of the global screen space
    let layer: Int
    let onScreen: Bool
}

/// JustMD's windows, front to back (the order the window server returns).
func justMDWindows() -> [WindowInfo] {
    let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return raw.compactMap { d in
        guard d[kCGWindowOwnerName as String] as? String == "JustMD",
              let id = d[kCGWindowNumber as String] as? CGWindowID,
              let b = d[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        let rect = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        return WindowInfo(id: id,
                          title: d[kCGWindowName as String] as? String ?? "",
                          bounds: rect,
                          layer: d[kCGWindowLayer as String] as? Int ?? 0,
                          onScreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }
}

func capture(_ id: CGWindowID) -> NSBitmapImageRep {
    let path = NSTemporaryDirectory() + "compose-\(id).png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l\(id)", "-o", "-x", path]
    try? p.run()
    p.waitUntilExit()
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let rep = NSBitmapImageRep(data: data) else { fail("could not capture window \(id)") }
    return rep
}

let opts = parse()
let all = justMDWindows()

if opts.list {
    for w in all where w.bounds.width > 1 {
        print("\(w.id)\t\(w.title.isEmpty ? "(untitled)" : w.title)\tlayer=\(w.layer)\tonscreen=\(w.onScreen)\t\(Int(w.bounds.minX)),\(Int(w.bounds.minY)) \(Int(w.bounds.width))×\(Int(w.bounds.height))")
    }
    exit(0)
}

guard !opts.out.isEmpty, !opts.windows.isEmpty else { fail("need --out and at least one --window") }
if opts.caption.split(separator: " ").count > 8 { fail("caption longer than eight words") }

// Back-to-front, so the frontmost window (a sheet, say) is drawn last.
let chosen = all.filter { opts.windows.contains($0.id) }
guard chosen.count == opts.windows.count else { fail("some window ids are not JustMD windows") }
let ordered = chosen.reversed()
let scale = NSScreen.main?.backingScaleFactor ?? 2
let union = chosen.dropFirst().reduce(chosen[0].bounds) { $0.union($1.bounds) }

let canvasW = 2880, canvasH = 1800
guard let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: canvasW, pixelsHigh: canvasH,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fail("no canvas") }
canvas.size = NSSize(width: canvasW, height: canvasH)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
defer { NSGraphicsContext.restoreGraphicsState() }

color(opts.bg).setFill()
NSRect(x: 0, y: 0, width: canvasW, height: canvasH).fill()

// Caption: the app's own typeface (SF Pro via the system font), centred.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let caption = NSAttributedString(string: opts.caption, attributes: [
    .font: NSFont.systemFont(ofSize: opts.fontSize, weight: .semibold),
    .foregroundColor: color(opts.fg),
    .paragraphStyle: paragraph,
])
let captionSize = caption.size()
let captionTop = CGFloat(canvasH) - opts.top
caption.draw(at: NSPoint(x: (CGFloat(canvasW) - captionSize.width) / 2, y: captionTop - captionSize.height))

// Window group: below the caption, centred in what is left.
let areaTop = captionTop - captionSize.height - 72
let areaBottom: CGFloat = 40
let areaWidth = CGFloat(canvasW) - 2 * 80
let groupW = union.width * scale, groupH = union.height * scale
let fit = min(1, areaWidth / groupW, (areaTop - areaBottom) / groupH)
if fit < 1 { FileHandle.standardError.write("note: group scaled by \(fit)\n".data(using: .utf8)!) }
let drawnW = groupW * fit, drawnH = groupH * fit
let groupX = (CGFloat(canvasW) - drawnW) / 2
let groupBottom = areaBottom + (areaTop - areaBottom - drawnH) / 2

for w in ordered {
    let rep = capture(w.id)
    let x = groupX + (w.bounds.minX - union.minX) * scale * fit
    let y = groupBottom + (union.maxY - w.bounds.maxY) * scale * fit
    let dest = NSRect(x: x, y: y, width: w.bounds.width * scale * fit, height: w.bounds.height * scale * fit)
    NSGraphicsContext.current?.saveGraphicsState()
    // The shadow a Mac window actually casts, roughly: soft, mostly downward.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    rep.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false,
             hints: [.interpolation: NSImageInterpolation.high.rawValue])
    NSGraphicsContext.current?.restoreGraphicsState()
}

guard let png = canvas.representation(using: .png, properties: [:]) else { fail("png encode failed") }
do { try png.write(to: URL(fileURLWithPath: opts.out)) } catch { fail("write failed: \(error)") }
print("wrote \(opts.out) (\(canvasW)×\(canvasH)), \(chosen.count) window(s), group \(Int(groupW))×\(Int(groupH)) px, fit \(fit)")
