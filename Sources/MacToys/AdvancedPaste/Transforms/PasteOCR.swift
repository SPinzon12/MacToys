import Foundation
import Vision

/// Vision OCR for the Image-to-Text transform. T3's `OCRService` is
/// module-private and word-box oriented, so this is a small independent
/// line reader over the same `VNRecognizeTextRequest` approach.
enum PasteOCR {
    /// Recognized lines, top to bottom; nil when nothing was recognized.
    static func text(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let lines = (request.results ?? [])
            // Vision's result order is only approximately reading order.
            .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            .compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }
}
