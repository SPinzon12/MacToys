import CoreText
import Foundation
import Vision

/// Vision OCR for the Text Extractor: `.accurate` recognition shared by both
/// modes, plus word-level boxes for click hit-testing. Synchronous and
/// thread-agnostic; the session runs it off the main thread.
///
/// Measured on an M4 (macOS 27): the first `.accurate` request ever made by a
/// given executable path takes ~26 s (model preparation, cached on disk per
/// path afterwards; the same binary copied elsewhere pays it again), and
/// Vision serializes every other text request behind it — `.fast` included.
/// Later requests take ~40–190 ms, even across relaunches and rebuilds at the
/// same path. Pinning the GPU or CPU compute device did not avoid it.
enum OCRService {
    /// Runs one throwaway `.accurate` pass at launch, so that one-time
    /// preparation (or the per-launch model load) happens before the hotkey.
    static func warmUp() {
        Task.detached(priority: .utility) {
            guard let image = warmUpImage() else { return }
            _ = try? recognize(image)
        }
    }

    /// A few words of real text: an empty image could return before the
    /// recognizer model is ever loaded.
    private static func warmUpImage() -> CGImage? {
        guard let context = CGContext(
            data: nil, width: 320, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 64))
        let font = CTFontCreateWithName("Helvetica" as CFString, 28, nil)
        let text = NSAttributedString(string: "Warm up OCR", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        context.textPosition = CGPoint(x: 12, y: 20)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
        return context.makeImage()
    }
    /// One recognized word and its box in Vision image space: normalized 0…1,
    /// origin bottom-left — the same orientation as the overlay's view coords.
    struct Word {
        let text: String
        let box: CGRect
    }

    /// Words over a full-screen capture, for the click hit-test.
    static func words(in image: CGImage) throws -> [Word] {
        var words: [Word] = []
        for observation in try recognize(image) {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string
            // Vision boxes whole lines. boundingBox(for:) carves the word ranges
            // out of that line's box — exactly what a click hit-test needs.
            for range in wordRanges(in: text) {
                guard let rectangle = try? candidate.boundingBox(for: range) else { continue }
                words.append(Word(text: String(text[range]), box: rectangle.boundingBox))
            }
        }
        return words
    }

    /// Recognized lines of a cropped region, top to bottom.
    static func lines(in image: CGImage) throws -> [String] {
        try recognize(image)
            // Vision's result order is only approximately reading order.
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
    }

    private static func recognize(_ image: CGImage) throws -> [VNRecognizedTextObservation] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true // Vision's default; stated on purpose
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results ?? []
    }

    /// Whitespace-separated word ranges inside `text`.
    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace {
                text.formIndex(after: &index)
            }
            let start = index
            while index < text.endIndex, !text[index].isWhitespace {
                text.formIndex(after: &index)
            }
            if start < index {
                ranges.append(start..<index)
            }
        }
        return ranges
    }

    /// Small crops OCR badly, so PowerOCR upscales them before recognition;
    /// ×1.5 when either side is under ~200 px, otherwise pass through.
    static func upscaledIfSmall(_ image: CGImage) -> CGImage {
        guard min(image.width, image.height) < 200 else { return image }
        let width = Int(CGFloat(image.width) * 1.5)
        let height = Int(CGFloat(image.height) * 1.5)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
