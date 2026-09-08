#!/usr/bin/env swift
// Re-encode a screen recording for App Store Connect: 1920×1080, H.264,
// 30 fps, with a silent stereo AAC track. App Store Connect rejects a preview
// that has no audio track at all (asset error MOV_RESAVE_STEREO), so silence
// is generated and muxed in.
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

/// Writes `seconds` of stereo silence as AAC and returns the file.
func makeSilence(seconds: Double) throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("silence-\(UUID().uuidString).m4a")
    let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
    let sampleRate = 44_100.0
    let channels: UInt32 = 2
    let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: Int(channels),
        AVEncoderBitRateKey: 96_000,
    ])
    writer.add(writerInput)
    guard writer.startWriting() else { throw writer.error ?? NSError(domain: "silence", code: 1) }
    writer.startSession(atSourceTime: .zero)

    var asbd = AudioStreamBasicDescription(
        mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 2 * channels, mFramesPerPacket: 1, mBytesPerFrame: 2 * channels,
        mChannelsPerFrame: channels, mBitsPerChannel: 16, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil,
                                   magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                   formatDescriptionOut: &format)
    guard let format else { throw NSError(domain: "silence", code: 2) }

    let framesPerChunk = 4096
    var frame = 0
    let totalFrames = Int(seconds * sampleRate)
    while frame < totalFrames {
        while !writerInput.isReadyForMoreMediaData { usleep(2000) }
        let count = min(framesPerChunk, totalFrames - frame)
        let bytes = count * Int(asbd.mBytesPerFrame)
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes,
                                           blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                                           dataLength: bytes, flags: 0, blockBufferOut: &block)
        guard let block else { throw NSError(domain: "silence", code: 3) }
        CMBlockBufferFillDataBytes(with: 0, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: count,
            presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(sampleRate)),
            packetDescriptions: nil, sampleBufferOut: &sample)
        guard let sample else { throw NSError(domain: "silence", code: 4) }
        writerInput.append(sample)
        frame += count
    }
    writerInput.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    if let error = writer.error { throw error }
    return url
}

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

        // Video from the recording, audio from generated silence.
        let mix = AVMutableComposition()
        guard let videoTrack = mix.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { failure = "no composition track"; semaphore.signal(); return }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        let silence = AVURLAsset(url: try makeSilence(seconds: duration.seconds))
        if let silent = try await silence.loadTracks(withMediaType: .audio).first,
           let audioTrack = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let silentDuration = try await silence.load(.duration)
            try audioTrack.insertTimeRange(CMTimeRange(start: .zero, duration: min(duration, silentDuration)), of: silent, at: .zero)
        }

        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: targetW, height: targetH)
        composition.frameDuration = CMTime(value: 1, timescale: 30)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        layer.setTransform(CGAffineTransform(scaleX: targetW / natural.width, y: targetH / natural.height), at: .zero)
        instruction.layerInstructions = [layer]
        composition.instructions = [instruction]

        guard let export = AVAssetExportSession(asset: mix, presetName: AVAssetExportPresetHighestQuality) else {
            failure = "no export session"; semaphore.signal(); return
        }
        export.videoComposition = composition
        try? FileManager.default.removeItem(at: output)
        try await export.export(to: output, as: .mp4)
        print("wrote \(output.path): \(Int(natural.width))×\(Int(natural.height)) -> \(Int(targetW))×\(Int(targetH)), \(String(format: "%.1f", duration.seconds)) s, silent stereo AAC")
    } catch {
        failure = "\(error)"
    }
    semaphore.signal()
}
semaphore.wait()
if let failure { FileHandle.standardError.write((failure + "\n").data(using: .utf8)!); exit(1) }
