import Foundation
import SwiftData

@Model
final class Visit {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var date: Date = Date()
    var typeRaw: String = VisitType.visit.rawValue
    /// Ham ses metni; her zaman saklanır.
    var transcript: String = ""
    /// Düzenlenmiş (CRM'e uygun) not.
    var summary: String = ""
    /// Ziyaretin konusu (tek satır, isteğe bağlı): geçmiş satırı başlığı ve CRM raporundaki "Konu" satırı.
    var topic: String = ""
    var topics: [String] = []
    var nextStep: String = ""
    var nextStepDate: Date?
    var exportedToCRM: Bool = false
    var exportedAt: Date?

    var customer: Customer?
    @Relationship(inverse: \Contact.visits)
    var contacts: [Contact]?
    var opportunity: Opportunity?
    @Relationship(deleteRule: .nullify, inverse: \FollowUpTask.visit)
    var tasks: [FollowUpTask]?

    init(
        date: Date = Date(),
        type: VisitType = .visit,
        transcript: String = "",
        summary: String = "",
        topic: String = "",
        topics: [String] = [],
        nextStep: String = "",
        nextStepDate: Date? = nil,
        ownerUserID: String = ""
    ) {
        self.date = date
        self.typeRaw = type.rawValue
        self.transcript = transcript
        self.summary = summary
        self.topic = topic
        self.topics = topics
        self.nextStep = nextStep
        self.nextStepDate = nextStepDate
        self.ownerUserID = ownerUserID
    }

    var type: VisitType {
        get { VisitType(rawValue: typeRaw) ?? .visit }
        set { typeRaw = newValue.rawValue }
    }
}

extension Visit {
    /// Ziyaret satırı başlığı: konu; boşsa notun ilk dolu satırı; ikisi de yoksa boş.
    var displayTitle: String {
        let trimmedTopic = VisitText.singleLine(topic)
        if !trimmedTopic.isEmpty { return trimmedTopic }
        return VisitText.firstLine(of: summary)
    }

    /// Başlığın altında gösterilecek not: konu varsa notun tamamı; başlık notun ilk satırından geldiyse
    /// o satır çıkarılmış kalanı (aynı metin iki kez görünmesin).
    var noteBelowTitle: String {
        let note = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard VisitText.singleLine(topic).isEmpty, !note.isEmpty else { return note }
        let lines = note.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return "" }
        return lines[(index + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Konu/not metinleri için küçük yardımcılar (saf mantık).
enum VisitText {
    /// Satır sonlarını ve art arda boşlukları tek boşluğa indirir, kenarları kırpar.
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    /// İlk boş olmayan satır (kırpılmış); yoksa boş.
    static func firstLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

