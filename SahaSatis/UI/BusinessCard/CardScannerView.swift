import AVFoundation
import SwiftUI
import VisionKit

/// Canlı tarayıcıdan o an görünen metni okumak için tutamaç.
final class CardScannerHandle {
    fileprivate var items: [RecognizedItem] = []

    /// Kameranın o anda tanıdığı metin parçaları, yukarıdan aşağıya (parça içindeki satırlar ayrılır).
    func currentLines() -> [String] {
        let texts: [(y: CGFloat, text: String)] = items.compactMap { item in
            guard case .text(let text) = item else { return nil }
            return (text.bounds.topLeft.y, text.transcript)
        }
        return texts
            .sorted { $0.y < $1.y }
            .flatMap { $0.text.components(separatedBy: .newlines) }
    }
}

/// VisionKit `DataScannerViewController` sarmalayıcısı (yalnızca metin).
struct CardScannerView: UIViewControllerRepresentable {
    let handle: CardScannerHandle

    /// Canlı tarama yapılabiliyorsa `true`: cihaz destekliyor ve kamera izni var (henüz sorulmadıysa sorar).
    /// Simülatörde ve izin reddedilince `false` → fotoğraf seçme yoluna düşülür.
    @MainActor
    static func prepare() async -> Bool {
        guard DataScannerViewController.isSupported else { return false }
        guard await AVCaptureDevice.requestAccess(for: .video) else { return false }
        return DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(handle: handle) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(languages: CardTextRecognizer.preferredLanguages)],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let handle: CardScannerHandle

        init(handle: CardScannerHandle) {
            self.handle = handle
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle.items = allItems
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle.items = allItems
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle.items = allItems
        }
    }
}
