#!/usr/bin/env swift
// Keyboard input source for scripted typing: keystrokes go through the
// current layout, so a Russian layout turns "hello" into "руддщ".
//
//   swift layout.swift list           ids of enabled keyboard layouts, current first
//   swift layout.swift current        id of the current layout
//   swift layout.swift select <id>    e.g. com.apple.keylayout.ABC
import Carbon

func id(_ source: TISInputSource) -> String {
    guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
}

let args = CommandLine.arguments.dropFirst()
let current = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
switch args.first {
case "current":
    print(id(current))
case "list":
    let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout, kTISPropertyInputSourceIsEnabled: true] as CFDictionary
    let list = TISCreateInputSourceList(filter, false).takeRetainedValue() as! [TISInputSource]
    print(id(current))
    for s in list where id(s) != id(current) { print(id(s)) }
case "select":
    guard let wanted = args.dropFirst().first else { exit(1) }
    let filter = [kTISPropertyInputSourceID: wanted] as CFDictionary
    let list = TISCreateInputSourceList(filter, true).takeRetainedValue() as! [TISInputSource]
    guard let source = list.first else { FileHandle.standardError.write("no such layout: \(wanted)\n".data(using: .utf8)!); exit(1) }
    let status = TISSelectInputSource(source)
    print(status == noErr ? "selected \(wanted)" : "failed \(status)")
default:
    print("usage: layout.swift list | current | select <id>")
}
