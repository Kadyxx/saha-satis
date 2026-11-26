import UIKit
import Vision

/// Fotoğraftaki kartvizit metnini Vision ile (cihaz üstünde, ücretsiz) satır satır okur.
enum CardTextRecognizer {
    static let preferredLanguages = ["tr-TR", "en-US"]

    enum Failure: LocalizedError {
        case unreadableImage

        var errorDescription: String? { "Fotoğraf okunamadı." }
    }

    /// Satırlar yukarıdan aşağıya sıralı döner. Ağır iş ana iş parçacığı dışında yapılır.
    static func lines(from imageData: Data) async throws -> [String] {
        guard let image = UIImage(data: imageData), let cgImage = image.cgImage else { throw Failure.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            // Desteklenmeyen dil istenirse istek hata verir; cihazın desteklediklerine süzülür.
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let languages = preferredLanguages.filter { supported.contains($0) }
            request.recognitionLanguages = languages.isEmpty ? ["en-US"] : languages
            try VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:]).perform([request])
            return (request.results ?? [])
                // Vision koordinatlarında y yukarı doğru artar.
                .sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
