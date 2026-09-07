#!/usr/bin/env swift
// Re-encode a screen recording for App Store Connect: 1920×1080, H.264, 30 fps.
//
//   swift scale-video.swift <in.mov> <out.mp4> [width height]
//
// The source should already be 16:9 (record a 16:9 region with
// `screencapture -v -R x,y,w,h`); the video is scaled, not cropped, so a
// different aspect ratio would be distorted.
import AVFoundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: scale-video.swift in.mov out.mp4 [width height]\n".data(using: .utf8)!)
    exit(1)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
let targetW = args.count > 4 ? Double(args[3]) ?? 1920 : 1920
let targetH = args.count > 4 ? Double(args[4]) ?? 1080 : 1080

let asset = AVURLAsset(url: input)
let semaphore = DispatchSemaphore(value: 0)
var failure: String?

Task {
    do {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            failure = "no video track"; semaphore.signal(); return
        }
        let natural = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)

        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: targetW, height: targetH)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(CGAffineTransform(scaleX: targetW / natural.width, y: targetH / natural.height), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            failure = "no export session"; semaphore.signal(); return
        }
        export.videoComposition = composition
        export.outputFileType = .mp4
        export.outputURL = output
        try? FileManager.default.removeItem(at: output)
        try await export.export(to: output, as: .mp4)
        print("wrote \(output.path): \(Int(natural.width))×\(Int(natural.height)) -> \(Int(targetW))×\(Int(targetH)), \(String(format: "%.1f", duration.seconds)) s")
    } catch {
        failure = "\(error)"
    }
    semaphore.signal()
}
semaphore.wait()
if let failure { FileHandle.standardError.write((failure + "\n").data(using: .utf8)!); exit(1) }
