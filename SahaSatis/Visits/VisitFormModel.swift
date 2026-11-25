import Foundation
import Observation

/// Ekran görüntüsü/DEBUG için formu önceden dolduran başlangıç değerleri.
struct VisitFormSeed {
    var topic = ""
    var note = ""
    var nextStep = ""
    /// Bugünden kaç gün sonrasına takip tarihi konacağı (nil: tarih yok).
    var nextStepInDays: Int?
    /// Müşterinin ilk N kişisi işaretli gelir.
    var selectFirstContacts = 0
    var autoStartRecording = false
}

/// Ziyaret formunun durumu. Veriye yalnızca Repository'ler üzerinden erişir (`VisitService`).
@MainActor
@Observable
final class VisitFormModel {
    let existingVisit: Visit?
    let seed: VisitFormSeed

    var customer: Customer?
    private(set) var contacts: [Contact] = []
    var selectedContactIDs: Set<UUID> = []
    var type: VisitType = .visit
    var date = Date()
    /// Konu: tek satır, isteğe bağlı.
    var topic = ""
    /// Düzenlenebilir görüşme notu; sesli not parçaları buraya eklenir.
    var note = ""
    var nextStep = ""
    var hasNextStepDate = false
    var nextStepDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    var errorMessage: String?

    let voice: VoiceNoteController
    /// Ham ses metni: sesli not parçalarının birleşimi (kullanıcı notu düzenlese de değişmez).
    private(set) var rawTranscript = ""

    private let repositories: Repositories
    private let reminderMinutes: Int

    init(
        repositories: Repositories,
        reminderMinutes: Int,
        engine: SpeechEngine,
        customer: Customer?,
        visit: Visit? = nil,
        seed: VisitFormSeed = VisitFormSeed()
    ) {
        self.repositories = repositories
        self.reminderMinutes = reminderMinutes
        self.existingVisit = visit
        self.seed = seed
        self.voice = VoiceNoteController(engine: engine)
        self.customer = visit?.customer ?? customer

        voice.onCommit = { [weak self] segment in
            self?.appendDictation(segment)
        }

        if let visit {
            type = visit.type
            date = visit.date
            topic = visit.topic
            note = visit.summary
            rawTranscript = visit.transcript
            nextStep = visit.nextStep
            if let day = visit.nextStepDate {
                hasNextStepDate = true
                nextStepDate = day
            }
            reloadContacts()
            selectedContactIDs = Set((visit.contacts ?? []).map(\.id))
        } else {
            topic = seed.topic
            note = seed.note
            nextStep = seed.nextStep
            if let days = seed.nextStepInDays {
                hasNextStepDate = true
                nextStepDate = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
            }
            reloadContacts()
            selectedContactIDs = Set(contacts.prefix(seed.selectFirstContacts).map(\.id))
        }
    }

    var isEditing: Bool { existingVisit != nil }
    var canSave: Bool { customer != nil }

    // MARK: - Müşteri ve kişiler

    /// Müşteri değiştiğinde çağrılır: kişi listesi yenilenir, işaretler sıfırlanır.
    func customerChanged() {
        reloadContacts()
        selectedContactIDs = []
    }

    private func reloadContacts() {
        guard let customer else {
            contacts = []
            return
        }
        contacts = (try? repositories.contacts.contacts(for: customer)) ?? []
    }

    func toggleContact(_ contact: Contact) {
        if selectedContactIDs.contains(contact.id) {
            selectedContactIDs.remove(contact.id)
        } else {
            selectedContactIDs.insert(contact.id)
        }
    }

    // MARK: - Konu önerileri

    static let maxTopicSuggestions = 5

    /// Aynı müşterinin son ziyaret konuları (en yeni önce, boşlar ve tekrarlar atılır, en çok 5). Düzenlenen
    /// ziyaretin kendi konusu ve formdaki mevcut metinle aynı olanlar önerilmez.
    var topicSuggestions: [String] {
        guard let customer, let visits = try? repositories.visits.visits(for: customer) else { return [] }
        let current = VisitText.singleLine(topic).lowercased()
        var seen: Set<String> = [current]
        var result: [String] = []
        for visit in visits where visit.id != existingVisit?.id {
            let text = VisitText.singleLine(visit.topic)
            let key = text.lowercased()
            guard !text.isEmpty, seen.insert(key).inserted else { continue }
            result.append(text)
            if result.count == Self.maxTopicSuggestions { break }
        }
        return result
    }

    // MARK: - Sesli not

    /// Sesli not parçasını nota ve ham metne ekler.
    func appendDictation(_ segment: String) {
        note = note.isEmpty ? segment : note + " " + segment
        rawTranscript = rawTranscript.isEmpty ? segment : rawTranscript + " " + segment
    }

    // MARK: - Kaydetme

    /// Kaydeder; başarılıysa `true`.
    @discardableResult
    func save() -> Bool {
        guard let customer else { return false }
        voice.stop()

        var draft = VisitDraft()
        draft.date = date
        draft.type = type
        draft.topic = VisitText.singleLine(topic)
        draft.summary = note.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.transcript = rawTranscript
        draft.nextStep = nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.nextStepDate = hasNextStepDate ? nextStepDate : nil

        let selected = contacts.filter { selectedContactIDs.contains($0.id) }
        let service = VisitService(repositories: repositories, reminderMinutes: reminderMinutes)
        do {
            try service.save(draft, customer: customer, contacts: selected, existing: existingVisit)
            return true
        } catch {
            errorMessage = "Ziyaret kaydedilemedi: \(error.localizedDescription)"
            return false
        }
    }
}
