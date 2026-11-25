import Foundation

/// Sahte konuşma motoru: testlerde ve DEBUG ekran görüntülerinde kullanılır.
/// `emit`/`finish` ile tanıma sonuçları elle sürülür; `autoEmit` doluysa her oturum başında
/// sıradaki metin kendiliğinden gönderilir.
final class MockSpeechEngine: SpeechEngine {
    var isAvailable: Bool
    var permissionGranted: Bool
    var startError: Error?
    var autoEmit: [String]

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var textHandler: (@MainActor @Sendable (String) -> Void)?
    private var finishHandler: (@MainActor @Sendable (Error?) -> Void)?

    init(isAvailable: Bool = true, permissionGranted: Bool = true, autoEmit: [String] = []) {
        self.isAvailable = isAvailable
        self.permissionGranted = permissionGranted
        self.autoEmit = autoEmit
    }

    func requestPermissions() async -> Bool {
        permissionGranted
    }

    func startSession(
        onText: @escaping @MainActor @Sendable (String) -> Void,
        onFinish: @escaping @MainActor @Sendable (Error?) -> Void
    ) throws {
        if let startError { throw startError }
        startCount += 1
        textHandler = onText
        finishHandler = onFinish
        if !autoEmit.isEmpty {
            let text = autoEmit[(startCount - 1) % autoEmit.count]
            Task { @MainActor in onText(text) }
        }
    }

    func stopSession() {
        stopCount += 1
        textHandler = nil
        finishHandler = nil
    }

    /// Mevcut oturumda tanınan (tüm) metni gönderir.
    @MainActor
    func emit(_ text: String) {
        textHandler?(text)
    }

    /// Mevcut oturumu bitirir (`error == nil`: son sonuç / süre sınırı).
    @MainActor
    func finish(_ error: Error? = nil) {
        finishHandler?(error)
    }
}
