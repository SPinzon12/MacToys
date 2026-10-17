import Foundation
import Testing
import CoreGraphics
@testable import MacToys

/// Which transforms the ⌃⇧V menu offers for a given clipboard snapshot.
struct MenuValidityTests {
    private let videoURL = URL(fileURLWithPath: "/tmp/clip.mov")
    private let audioURL = URL(fileURLWithPath: "/tmp/song.mp3")
    private let otherURL = URL(fileURLWithPath: "/tmp/notes.txt")

    private var image: CGImage? {
        CGImage(
            width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data([0, 0, 0, 255]) as CFData)!,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    @Test func emptyClipboardOffersNothing() {
        #expect(PasteTransform.available(for: ClipboardContent()).isEmpty)
        // Present-but-empty fields must not create menu entries either.
        #expect(PasteTransform.available(for: ClipboardContent(text: "", html: "")).isEmpty)
    }

    @Test func textOnlyClipboard() {
        let content = ClipboardContent(text: "hello")
        #expect(
            PasteTransform.available(for: content)
                == [.plainText, .txtFile, .htmlFile, .structuredToJSON]
        )
    }

    @Test func imageOnlyClipboard() {
        let content = ClipboardContent(image: image)
        #expect(PasteTransform.available(for: content) == [.imageToText, .pngFile])
    }

    @Test func htmlOnlyClipboard() {
        let content = ClipboardContent(html: "<p>hi</p>")
        #expect(
            PasteTransform.available(for: content)
                == [.plainText, .txtFile, .htmlFile, .htmlToMarkdown]
        )
    }

    @Test func fileOnlyClipboards() {
        #expect(
            PasteTransform.available(for: ClipboardContent(fileURLs: [videoURL]))
                == [.videoToMP4]
        )
        #expect(
            PasteTransform.available(for: ClipboardContent(fileURLs: [audioURL]))
                == [.audioToM4A]
        )
        #expect(
            PasteTransform.available(for: ClipboardContent(fileURLs: [otherURL])).isEmpty
        )
    }

    @Test func mixedClipboardOffersTheUnion() {
        let content = ClipboardContent(
            text: "hello", html: "<p>hi</p>", image: image, fileURLs: [videoURL]
        )
        #expect(
            PasteTransform.available(for: content)
                == [.plainText, .imageToText, .txtFile, .pngFile, .htmlFile,
                    .structuredToJSON, .htmlToMarkdown, .videoToMP4]
        )
    }
}
