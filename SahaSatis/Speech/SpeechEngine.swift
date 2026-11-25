import AVFoundation
import Foundation
import Speech

/// Konuşma tanıma motoru. Gerçek uygulama `AppleSpeechEngine` (Speech framework, tr-TR);
/// testlerde ve ekran görüntülerinde `MockSpeechEngine` kullanılır (simülatörde mikrofon yok).
protocol SpeechEngine: AnyObject {
    /// Tanıyıcı bu cihazda/dilde kullanılabilir mi?
    var isAvailable: Bool { get }
    /// Mikrofon ve konuşma tanıma izinlerini ister; ikisi de verildiyse `true`.
    func requestPermissions() async -> Bool
    /// Yeni bir tanıma oturumu başlatır. `onText` o ana kadar tanınan TÜM metinle (oturum başından) çağrılır;
    /// `onFinish` oturum bittiğinde (son sonuç, süre sınırı veya hata) bir kez çağrılır.
    func startSession(
        onText: @escaping @MainActor @Sendable (String) -> Void,
        onFinish: @escaping @MainActor @Sendable (Error?) -> Void
    ) throws
    /// Oturumu hemen durdurur; bundan sonra geri çağrı gelmez.
    func stopSession()
}

enum SpeechEngineError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Konuşma tanıma bu cihazda şu anda kullanılamıyor."
        }
    }
}

/// İzin istekleri. Geri çağrılar rastgele kuyruklarda gelir; bu yüzden actor izolasyonu olmayan
/// serbest fonksiyonlarda tutulur.
enum SpeechPermissions {
    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
