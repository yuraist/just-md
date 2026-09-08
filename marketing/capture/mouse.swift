#!/usr/bin/env swift
// Real pointer input for the preview recording (the cursor has to move on
// screen, so AppleScript's `click at` is not enough). Coordinates are screen
// points, origin top-left.
//
//   swift mouse.swift move X Y [seconds]      glide the pointer there
//   swift mouse.swift click X Y               move, then left click
//   swift mouse.swift dblclick X Y            move, then double click
//   swift mouse.swift scroll X Y LINES        wheel scroll at a point (+down)
//   swift mouse.swift sleep SECONDS
//
// Several commands can be chained: swift mouse.swift move 100 100 0.5 click 100 100
import AppKit

func post(_ type: CGEventType, _ point: CGPoint, button: CGMouseButton = .left, clickCount: Int64 = 0) {
    guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { return }
    // Only button events carry a click count; a count on the moves that
    // precede a click makes AppKit read the click as a double-click.
    if clickCount > 0 { e.setIntegerValueField(.mouseEventClickState, value: clickCount) }
    e.post(tap: .cghidEventTap)
}

func currentPoint() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

func glide(to target: CGPoint, seconds: Double) {
    let start = currentPoint()
    let steps = max(1, Int(seconds * 90))
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        let p = CGPoint(x: start.x + (target.x - start.x) * eased, y: start.y + (target.y - start.y) * eased)
        post(.mouseMoved, p)
        usleep(useconds_t(seconds / Double(steps) * 1_000_000))
    }
    post(.mouseMoved, target)
}

func click(_ p: CGPoint, count: Int64) {
    for n in 1...count {
        post(.leftMouseDown, p, clickCount: n)
        usleep(60_000)
        post(.leftMouseUp, p, clickCount: n)
        if n < count { usleep(90_000) }
    }
}

var args = Array(CommandLine.arguments.dropFirst())
func next() -> String { args.isEmpty ? "" : args.removeFirst() }
func num() -> Double { Double(next()) ?? 0 }

while !args.isEmpty {
    switch next() {
    case "move":
        let p = CGPoint(x: num(), y: num())
        let secs = args.first.flatMap(Double.init).map { _ in num() } ?? 0.6
        glide(to: p, seconds: secs)
    case "click":
        let p = CGPoint(x: num(), y: num())
        glide(to: p, seconds: 0.45)
        usleep(150_000)
        click(p, count: 1)
    case "dblclick":
        let p = CGPoint(x: num(), y: num())
        glide(to: p, seconds: 0.45)
        usleep(150_000)
        click(p, count: 2)
    case "scroll":
        let p = CGPoint(x: num(), y: num())
        let lines = Int32(num())
        glide(to: p, seconds: 0.4)
        let step: Int32 = lines > 0 ? -1 : 1
        for _ in 0..<abs(lines) {
            if let e = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0) {
                e.post(tap: .cghidEventTap)
            }
            usleep(40_000)
        }
    case "sleep":
        usleep(useconds_t(num() * 1_000_000))
    case let other:
        FileHandle.standardError.write("unknown command \(other)\n".data(using: .utf8)!)
        exit(1)
    }
}
