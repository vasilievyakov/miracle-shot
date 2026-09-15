import CoreGraphics
import MiracleShotCore
import Vision

@MainActor
public final class OCRService: OCRServicing {
    public init() {}

    public func recognize(_ image: CGImage) async throws -> OCRResult {
        try await Task.detached {
            let imageSize = CGSize(width: image.width, height: image.height)
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ru-RU", "en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            try handler.perform([request])

            let observations = request.results ?? []
            let blocks: [TextBlock] = observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return OCRMapping.block(text: candidate.string, normalized: observation.boundingBox,
                                        confidence: candidate.confidence, imageSize: imageSize)
            }
            return OCRResult(blocks: blocks)
        }.value
    }
}
