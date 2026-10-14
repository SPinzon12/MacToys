import Foundation
import Vision

/// Vision OCR for the Text Extractor: `.accurate` recognition shared by both
/// modes, plus word-level boxes for click hit-testing.
enum OCRService {
    /// One recognized word and its box in Vision image space: normalized 0…1,
    /// origin bottom-left — the same orientation as the overlay's view coords.
    struct Word {
        let text: String
        let box: CGRect
    }

    /// Words over a full-screen capture. Computed once per session and cached,
    /// so the first click pays for the OCR and later clicks are instant.
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
