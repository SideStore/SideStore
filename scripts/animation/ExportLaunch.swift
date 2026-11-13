import AppKit
import AVFoundation
import SwiftUI

private func ease(_ progress: Double, x1: Double, x2: Double) -> Double {
    let progress = min(1, max(0, progress))
    func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
        3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
    }
    var low = 0.0
    var high = 1.0
    for _ in 0..<24 {
        let mid = (low + high) / 2
        if cubic(mid, x1, x2) < progress { low = mid } else { high = mid }
    }
    return cubic((low + high) / 2, 0, 1)
}

// Match the app's half-second fade after a short preview hold.
private struct ExportFrame: View {
    var time: Double
    private let size = CGSize(width: 390, height: 844)

    var body: some View {
        let fade = ease((time - 1.5) / 0.5, x1: 0.42, x2: 0.58)
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.08)
            VStack(spacing: 12) {
                Text("UltraStore").font(.largeTitle.bold())
                Text("Launch animation preview").foregroundStyle(.secondary)
                Text("Main interface placeholder").font(.caption).foregroundStyle(.secondary)
            }
            ZStack {
                Color.black
                UltraStoreLaunchLogo(logoSize: size.width * 0.48)
            }
            .opacity(1 - fade)
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

private enum ExportError: Error {
    case renderFailed, pixelBufferFailed, encodingFailed
}

@main
struct ExportLaunch {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let output = directory.appendingPathComponent("animation_launch.mp4")
        if FileManager.default.fileExists(atPath: output.path) {
            try FileManager.default.removeItem(at: output)
        }
        let width = 780
        let height = 1688
        let fps: Int32 = 30
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ExportError.encodingFailed }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<150 {
            while !input.isReadyForMoreMediaData {
                guard writer.status == .writing else { throw writer.error ?? ExportError.encodingFailed }
                try await Task.sleep(nanoseconds: 1_000_000)
            }
            try autoreleasepool {
                let renderer = ImageRenderer(content: ExportFrame(time: Double(frame) / Double(fps)))
                renderer.scale = 2
                guard let image = renderer.cgImage else { throw ExportError.renderFailed }
                if frame == 30 {
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    try bitmap.representation(using: .png, properties: [:])?.write(
                        to: directory.appendingPathComponent("splash-logo.png")
                    )
                }
                var buffer: CVPixelBuffer?
                guard let pool = adaptor.pixelBufferPool,
                      CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
                      let buffer else { throw ExportError.pixelBufferFailed }
                CVPixelBufferLockBaseAddress(buffer, [])
                defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
                guard let context = CGContext(
                    data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                ) else { throw ExportError.pixelBufferFailed }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)) else {
                    throw writer.error ?? ExportError.encodingFailed
                }
            }
        }
        writer.endSession(atSourceTime: CMTime(value: 150, timescale: fps))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ExportError.encodingFailed }
        print("Exported 5 seconds of H.264 video: \(output.path)")
    }
}
