#!/usr/bin/env swift
// Dump frames of a video as PNG, for checking a take or picking the poster.
//
//   swift frames.swift <video> <out-dir> <seconds> [<seconds> …]
//   swift frames.swift <video> --duration
import AVFoundation
import AppKit

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: frames.swift video out-dir seconds… | video --duration\n".data(using: .utf8)!)
    exit(1)
}
let asset = AVURLAsset(url: URL(fileURLWithPath: args[1]))
let semaphore = DispatchSemaphore(value: 0)
Task {
    defer { semaphore.signal() }
    do {
        let duration = try await asset.load(.duration).seconds
        if args[2] == "--duration" {
            let track = try await asset.loadTracks(withMediaType: .video).first
            let size = try await track?.load(.naturalSize) ?? .zero
            let fps = try await track?.load(.nominalFrameRate) ?? 0
            let audio = try await asset.loadTracks(withMediaType: .audio).count
            print(String(format: "%.2f s, %.0f×%.0f, %.1f fps, %d audio track(s)", duration, size.width, size.height, fps, audio))
            return
        }
        let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
        for s in args.dropFirst(3) {
            guard let t = Double(s) else { continue }
            let (image, actual) = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600))
            let rep = NSBitmapImageRep(cgImage: image)
            let name = String(format: "frame-%05.2f.png", t)
            try rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent(name))
            print("\(name) (actual \(String(format: "%.2f", actual.seconds)) s)")
        }
    } catch {
        FileHandle.standardError.write("\(error)\n".data(using: .utf8)!)
    }
}
semaphore.wait()
