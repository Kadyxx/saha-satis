import Foundation

/// Ziyaret notu yardımcısına verilen girdi.
struct NoteAssistantInput: Equatable {
    var rawNote: String
    var customerName: String
    /// Görüşülen kişiler ("Ad Soyad (Unvan)").
    var contacts: [String]
    var today: Date
    /// Ayarlardaki talimat metni; boşsa varsayılan kullanılır.
    var instruction: String
}

/// Yardımcının önerdiği alanlar. Kullanıcı önizlemede onaylamadan forma yazılmaz.
struct NoteSuggestion: Equatable {
    var topic = ""
    var summary = ""
    var nextStep = ""
    var followUpDate: Date?
    /// `false`: cevap şablona uymuyor; `summary` metnin tamamıdır.
    var followsTemplate = true
    var warnings: [String] = []
}

enum NoteAssistantResponse: Equatable {
    /// Metni kullanıcı bir yapay zekâ uygulamasına götürür; cevabı sonra panodan yapıştırır.
    case handoff(text: String)
    /// Öneri doğrudan döner (ileride API uygulaması).
    case suggestion(NoteSuggestion)
}

/// Ziyaret notunu düzenleme yardımcısı. Şimdiki uygulama `ShareToClaudeAssistant` (API yok); ileride API ile çalışan
/// bir uygulama aynı protokolle eklenip `.suggestion` döndürebilir.
protocol NoteAssistant {
    func request(_ input: NoteAssistantInput) async throws -> NoteAssistantResponse
}

/// API kullanmaz: talimat + not tek metin halinde hazırlanır, kullanıcı paylaşım menüsünden Claude uygulamasını seçer.
struct ShareToClaudeAssistant: NoteAssistant {
    var calendar: Calendar = .current

    /// Hazırlanan metinde ham notun başlığı. Panoda hâlâ gönderilen metin olup olmadığını anlamak için de kullanılır.
    static let noteHeading = "Ham not:"

    func request(_ input: NoteAssistantInput) async throws -> NoteAssistantResponse {
        .handoff(text: prompt(for: input))
    }

    func prompt(for input: NoteAssistantInput) -> String {
        let instruction = input.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = calendar.dateComponents([.day, .month, .year], from: input.today)
        let today = String(format: "%02d.%02d.%04d", parts.day ?? 0, parts.month ?? 0, parts.year ?? 0)
        let contacts = input.contacts.isEmpty ? "-" : input.contacts.joined(separator: ", ")
        return """
        \(instruction.isEmpty ? AppSettings.defaultClaudeInstruction : instruction)

        Bugünün tarihi: \(today)
        Müşteri: \(input.customerName)
        Görüşülen kişiler: \(contacts)

        \(Self.noteHeading)
        \(input.rawNote.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    /// Panodaki metin Claude'un cevabı değil, gönderdiğimiz metnin kendisi mi?
    static func isOwnPrompt(_ text: String) -> Bool {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains(noteHeading) && lines.contains { $0.hasPrefix("Bugünün tarihi:") }
    }
}
