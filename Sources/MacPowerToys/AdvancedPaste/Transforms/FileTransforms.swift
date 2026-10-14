import AppKit
import AVFoundation
import Foundation

/// Temp-file payloads and AVFoundation transcoding.
/// ponytail: unique temp files per run, no cleanup manager — the OS empties
/// `temporaryDirectory` itself.
@MainActor
enum FileTransforms {
    enum Format {
        case mp4
        case m4a
    }

    static func write(_ contents: String, fileExtension: String) -> URL? {
        guard let data = contents.data(using: .utf8) else { return nil }
        return write(data, fileExtension: fileExtension)
    }

    static func write(_ data: Data, fileExtension: String) -> URL? {
        let url = temporaryURL(fileExtension: fileExtension)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    static func writePNG(_ image: CGImage) -> URL? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        return write(data, fileExtension: "png")
    }

    /// Minimal html shell for plain text pasted as an .html file.
    static func wrapAsHTML(_ text: String) -> String {
        "<html><body><p>"
            + text
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            + "</p></body></html>\n"
    }

    /// H.264/.mp4 for video, AppleM4A/AAC for audio — `AVAssetExportSession`
    /// does the work; the destination is a fresh temp file.
    static func transcode(_ url: URL, to format: Format) async -> URL? {
        let (preset, fileExtension, fileType): (String, String, AVFileType) = switch format {
        case .mp4: (AVAssetExportPresetHighestQuality, "mp4", .mp4)
        case .m4a: (AVAssetExportPresetAppleM4A, "m4a", .m4a)
        }
        let asset = AVURLAsset(url: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset),
              session.supportedFileTypes.contains(fileType)
        else { return nil }

        let destination = temporaryURL(fileExtension: fileExtension)
        session.outputURL = destination
        session.outputFileType = fileType
        session.shouldOptimizeForNetworkUse = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously {
                continuation.resume()
            }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        return destination
    }

    private static func temporaryURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-powertoys-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }
}
