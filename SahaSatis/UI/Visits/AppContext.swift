import SwiftUI

/// Uygulama genelinde paylaşılan bağımlılıklar (SwiftUI ortamı üzerinden): repository'ler, ayarlar ve
/// konuşma tanıma motoru üreticisi. Ziyaret formu her açılışta yeni bir motorla çalışır.
@MainActor
final class AppContext: ObservableObject {
    let repositories: Repositories
    let settings: AppSettings
    let makeSpeechEngine: () -> SpeechEngine

    init(repositories: Repositories, settings: AppSettings, makeSpeechEngine: @escaping () -> SpeechEngine) {
        self.repositories = repositories
        self.settings = settings
        self.makeSpeechEngine = makeSpeechEngine
    }
}
