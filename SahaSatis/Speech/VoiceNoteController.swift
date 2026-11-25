import Foundation
import Observation

/// Sesli not durumu: başlat / duraklat / devam / bitir. Konuşma tanımayı `SpeechEngine` arkasından kullanır.
///
/// Çalışma modeli: her oturumda motor, oturumun tüm metnini (`partialText`) günceller. Duraklatınca, bitirince,
/// motor oturumu kendiliğinden bitirince (uzun kayıtlarda süre sınırı) o metin `onCommit` ile forma teslim edilir
/// (forma "ekleme" olarak girer; kullanıcı metni her zaman elle düzenleyebilir) ve gerekiyorsa yeni oturum açılır.
@MainActor
@Observable
final class VoiceNoteController {
    enum State: Equatable {
        case idle
        case recording
        case paused
        case permissionDenied
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Şu anki oturumda tanınan, henüz forma teslim edilmemiş canlı metin.
    private(set) var partialText = ""
    /// Teslim edilen her parça için çağrılır (boş olmayan, kırpılmış metin).
    @ObservationIgnored var onCommit: ((String) -> Void)?

    private let engine: SpeechEngine
    @ObservationIgnored private var sessionID = 0
    @ObservationIgnored private var quickFinishes = 0
    @ObservationIgnored private var sessionStartedAt = Date()
    private let maxQuickFinishes = 3

    init(engine: SpeechEngine) {
        self.engine = engine
    }

    var isRecording: Bool { state == .recording }

    /// Kaydı başlatır veya (duraklatılmışsa) devam ettirir.
    func start() async {
        guard state != .recording else { return }
        guard engine.isAvailable else {
            state = .unavailable
            return
        }
        guard await engine.requestPermissions() else {
            state = .permissionDenied
            return
        }
        quickFinishes = 0
        beginSession()
    }

    func pause() {
        guard state == .recording else { return }
        endSession()
        state = .paused
    }

    /// Kaydı bitirir; son metin teslim edilir.
    func stop() {
        guard state == .recording || state == .paused else { return }
        if state == .recording { endSession() }
        state = .idle
    }

    // MARK: - Oturum yönetimi

    private func beginSession() {
        sessionID += 1
        let id = sessionID
        partialText = ""
        do {
            try engine.startSession(
                onText: { [weak self] text in
                    guard let self, self.sessionID == id else { return }
                    self.partialText = text
                },
                onFinish: { [weak self] error in
                    self?.handleFinish(sessionID: id, error: error)
                }
            )
            sessionStartedAt = Date()
            state = .recording
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Mevcut oturumu kapatır ve canlı metni teslim eder; sonraki oturum geri çağrıları yok sayılır.
    private func endSession() {
        commitPartial()
        engine.stopSession()
        sessionID += 1
    }

    private func commitPartial() {
        let text = partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        partialText = ""
        if !text.isEmpty {
            onCommit?(text)
        }
    }

    private func handleFinish(sessionID id: Int, error: Error?) {
        guard id == sessionID, state == .recording else { return }
        let ranFor = Date().timeIntervalSince(sessionStartedAt)
        endSession()

        // Çok kısa sürede tekrar tekrar biten oturum sonsuz döngüye girmesin.
        quickFinishes = ranFor < 2 ? quickFinishes + 1 : 0
        if quickFinishes >= maxQuickFinishes {
            state = .failed(error?.localizedDescription ?? "Konuşma tanıma durdu.")
            return
        }
        // Uzun kayıtlarda tanıyıcı oturumu bitirir; kullanıcı durdurmadıysa yeni oturumla sürdür.
        beginSession()
    }
}
