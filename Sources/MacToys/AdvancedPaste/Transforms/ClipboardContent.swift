import CoreGraphics
import Foundation

/// Snapshot of everything the pasteboard offered when ⌃⇧V fired.
/// Pure data: transforms read this, never the pasteboard directly, which is
/// what makes the transform layer unit-testable.
struct ClipboardContent {
    var text: String?
    var html: String?
    var image: CGImage?
    var fileURLs: [URL]

    init(
        text: String? = nil,
        html: String? = nil,
        image: CGImage? = nil,
        fileURLs: [URL] = []
    ) {
        self.text = text
        self.html = html
        self.image = image
        self.fileURLs = fileURLs
    }

    /// Empty strings count as absent: apps do put `""` on the pasteboard.
    var hasText: Bool { !(text?.isEmpty ?? true) }
    var hasHTML: Bool { !(html?.isEmpty ?? true) }
}

/// What a transform hands back for the pasteboard write.
enum PastePayload {
    case text(String)
    case image(CGImage)
    case file(URL)
}
