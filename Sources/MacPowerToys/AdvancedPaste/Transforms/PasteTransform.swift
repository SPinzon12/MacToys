import Foundation

/// The transforms the ⌃⇧V menu offers. Case order is menu display order;
/// `available(for:)` is the menu-validity rule the tests pin down.
enum PasteTransform: String, CaseIterable, Sendable {
    case plainText
    case imageToText
    case txtFile
    case pngFile
    case htmlFile
    case structuredToJSON
    case htmlToMarkdown
    case videoToMP4
    case audioToM4A

    var title: String {
        switch self {
        case .plainText: "Plain Text"
        case .imageToText: "Image to Text (OCR)"
        case .txtFile: "Paste as .txt File"
        case .pngFile: "Paste as .png File"
        case .htmlFile: "Paste as .html File"
        case .structuredToJSON: "XML/CSV → JSON"
        case .htmlToMarkdown: "HTML → Markdown"
        case .videoToMP4: "Video → MP4"
        // ponytail: upstream offers MP3; Apple ships no public MP3 encoder,
        // so audio transcodes honestly land as AAC/.m4a (documented in README).
        case .audioToM4A: "Audio → M4A"
        }
    }

    /// Transforms valid for the current clipboard content, in menu order.
    static func available(for content: ClipboardContent) -> [PasteTransform] {
        allCases.filter { $0.isAvailable(content) }
    }

    func isAvailable(_ content: ClipboardContent) -> Bool {
        switch self {
        case .plainText, .txtFile:
            return content.hasText || content.hasHTML
        case .imageToText, .pngFile:
            return content.image != nil
        case .htmlFile:
            return content.hasHTML || content.hasText
        case .structuredToJSON:
            return content.hasText
        case .htmlToMarkdown:
            return content.hasHTML
        case .videoToMP4:
            return content.fileURLs.contains {
                Self.videoExtensions.contains($0.pathExtension.lowercased())
            }
        case .audioToM4A:
            return content.fileURLs.contains {
                Self.audioExtensions.contains($0.pathExtension.lowercased())
            }
        }
    }

    /// Runs the transform. File payloads are unique temp files; the
    /// coordinator writes the result to the pasteboard and pastes.
    @MainActor
    func run(_ content: ClipboardContent) async -> PastePayload? {
        switch self {
        case .plainText:
            return TextTransforms.plainText(from: content).map(PastePayload.text)
        case .imageToText:
            guard let image = content.image,
                  let text = PasteOCR.text(in: image)
            else { return nil }
            return .text(text)
        case .txtFile:
            guard let text = TextTransforms.plainText(from: content),
                  let url = FileTransforms.write(text, fileExtension: "txt")
            else { return nil }
            return .file(url)
        case .pngFile:
            guard let image = content.image,
                  let url = FileTransforms.writePNG(image)
            else { return nil }
            return .file(url)
        case .htmlFile:
            let html = content.hasHTML
                ? content.html!
                : FileTransforms.wrapAsHTML(content.text ?? "")
            guard let url = FileTransforms.write(html, fileExtension: "html") else { return nil }
            return .file(url)
        case .structuredToJSON:
            guard let text = content.text else { return nil }
            return TextTransforms.structuredToJSON(text).map(PastePayload.text)
        case .htmlToMarkdown:
            guard let html = content.html else { return nil }
            return .text(TextTransforms.htmlToMarkdown(html))
        case .videoToMP4:
            guard let url = content.fileURLs.first(where: {
                Self.videoExtensions.contains($0.pathExtension.lowercased())
            }) else { return nil }
            return await FileTransforms.transcode(url, to: .mp4).map(PastePayload.file)
        case .audioToM4A:
            guard let url = content.fileURLs.first(where: {
                Self.audioExtensions.contains($0.pathExtension.lowercased())
            }) else { return nil }
            return await FileTransforms.transcode(url, to: .m4a).map(PastePayload.file)
        }
    }

    // Extension sniffing only: no UniformTypeIdentifiers (not in the allowed
    // framework list); AVFoundation does the real work at run time.
    private static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mpg", "mpeg", "3gp"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "aif", "caf", "flac"
    ]
}
