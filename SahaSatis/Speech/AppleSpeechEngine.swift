import AVFoundation
import Foundation
import Speech

/// Apple Speech framework ile Türkçe (tr-TR) canlı konuşma tanıma.
/// Yalnızca ana iş parçacığından kullanılır. Gerçek cihaz gerektirir; CI'da çalıştırılmaz.
final class AppleSpeechEngine: SpeechEngine {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool {
        recognizer?.isAvailable ?? false
    }

    func requestPermissions() async -> Bool {
        guard await SpeechPermissions.requestSpeech() else { return false }
        return await SpeechPermissions.requestMicrophone()
    }

    func startSession(
        onText: @escaping @MainActor @Sendable (String) -> Void,
        onFinish: @escaping @MainActor @Sendable (Error?) -> Void
    ) throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechEngineError.unavailable
        }
        stopSession()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }
        audioEngine.prepare()
        try audioEngine.start()

        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in onText(text) }
                if result.isFinal {
                    Task { @MainActor in onFinish(nil) }
                    return
                }
            }
            if let error {
                Task { @MainActor in onFinish(error) }
            }
        }
    }

    func stopSession() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
