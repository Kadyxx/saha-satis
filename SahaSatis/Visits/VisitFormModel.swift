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
    /// "Claude ile düzenle" düğmelerine kaydırır.
    var scrollToAssistant = false
    /// Doluysa açılışta bu cevap yapıştırılmış gibi önizleme gösterilir.
    var pastedReply: String?
}

/// Ziyaret formundaki "Fırsat" seçimi.
enum OpportunityLink: Hashable {
    case none
    case existing(UUID)
    /// "Yeni fırsat aç": başlık `newOpportunityTitle` alanından gelir.
    case new
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
    /// Ziyaretin bağlanacağı fırsat (yok / mevcut / yeni).
    var opportunityLink: OpportunityLink = .none
    var newOpportunityTitle = ""

    let voice: VoiceNoteController
    /// Ham metin: sesli not parçalarının birleşimi (kullanıcı notu düzenlese de değişmez); Claude cevabı
    /// uygulanırken o anki ham not da buraya eklenir.
    private(set) var rawTranscript = ""
    private var lastAppliedSummary: String?

    private let draftStore: VisitDraftStore?
    private let draftDelay: Duration
    /// Formun açılıştaki hali; taslak yalnızca bundan farklıysa saklanır.
    private var baseline = VisitFormDraft()
    /// Depodaki taslak bu forma mı ait (o yazdı ya da ondan geri yüklendi)? Başka taslağı silmemek için.
    private var ownsDraft = false
    /// Kaydedildi veya vazgeçildi: bundan sonra taslak yazılmaz.
    private(set) var isFinished = false
    @ObservationIgnored private var draftTask: Task<Void, Never>?

    private let repositories: Repositories
    private let reminderMinutes: Int
    private let defaultCurrency: Currency

    init(
        repositories: Repositories,
        reminderMinutes: Int,
        defaultCurrency: Currency = .tl,
        engine: SpeechEngine,
        customer: Customer?,
        visit: Visit? = nil,
        seed: VisitFormSeed = VisitFormSeed(),
        draftStore: VisitDraftStore? = nil,
        draftDelay: Duration = .seconds(1),
        restoring restoredDraft: VisitFormDraft? = nil
    ) {
        self.draftStore = draftStore
        self.draftDelay = draftDelay
        self.repositories = repositories
        self.reminderMinutes = reminderMinutes
        self.defaultCurrency = defaultCurrency
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
            if let linked = visit.opportunity { opportunityLink = .existing(linked.id) }
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
        baseline = draftContent
        if let restoredDraft { restore(restoredDraft) }
    }

    // MARK: - Taslak

    /// Formun şu anki içeriği (`savedAt` sabit kalır; değişiklik karşılaştırması için). Kayıt sürerken henüz
    /// forma teslim edilmemiş canlı metin de nota ve ham metne dahildir.
    var draftContent: VisitFormDraft {
        let partial = voice.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        var content = VisitFormDraft()
        content.existingVisitID = existingVisit?.id
        content.customerID = customer?.id
        content.customerName = customer?.name ?? ""
        content.contactIDs = selectedContactIDs.sorted { $0.uuidString < $1.uuidString }
        content.typeRaw = type.rawValue
        content.date = date
        content.topic = topic
        content.note = Self.appending(partial, to: note)
        content.nextStep = nextStep
        content.nextStepDate = hasNextStepDate ? nextStepDate : nil
        if case .existing(let id) = opportunityLink { content.opportunityID = id }
        content.wantsNewOpportunity = opportunityLink == .new
        content.newOpportunityTitle = newOpportunityTitle
        content.rawTranscript = Self.appending(partial, to: rawTranscript)
        content.lastAppliedSummary = lastAppliedSummary
        return content
    }

    var hasUnsavedChanges: Bool {
        guard !isFinished else { return false }
        let content = draftContent
        return content != baseline && (isEditing || content.hasUserInput)
    }

    /// İçerik değişince çağrılır. Art arda değişiklikler tek yazmada birleşir; bekleyen yazma ertelenmez,
    /// böylece aralıksız yazarken veya konuşurken de en geç `draftDelay` sonra kaydedilir.
    func scheduleDraftSave() {
        guard draftStore != nil, !isFinished, draftTask == nil else { return }
        let delay = draftDelay
        draftTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushDraft()
        }
    }

    /// Hemen yazar (uygulama arka plana giderken). Değişiklik kalmadıysa kendi taslağını siler.
    func flushDraft(now: Date = Date()) {
        draftTask?.cancel()
        draftTask = nil
        guard let draftStore, !isFinished else { return }
        if hasUnsavedChanges {
            var draft = draftContent
            draft.savedAt = now
            do {
                try draftStore.save(draft)
                ownsDraft = true
            } catch {
                // Taslak yedek amaçlıdır; yazılamaması formu engellemez.
            }
        } else if ownsDraft {
            draftStore.delete()
            ownsDraft = false
        }
    }

    /// Kaydetme ve vazgeçme: taslak silinir, bir daha yazılmaz.
    func discardDraft() {
        draftTask?.cancel()
        draftTask = nil
        isFinished = true
        if ownsDraft { draftStore?.delete() }
        ownsDraft = false
    }

    /// Taslağı forma geri yükler. Bu arada silinmiş kişi ve fırsat atlanır.
    private func restore(_ draft: VisitFormDraft) {
        if existingVisit == nil {
            customer = draft.customerID.flatMap { try? repositories.customers.customer(id: $0) } ?? customer
            reloadContacts()
        }
        selectedContactIDs = Set(draft.contactIDs).intersection(contacts.map(\.id))
        type = VisitType(rawValue: draft.typeRaw) ?? .visit
        date = draft.date
        topic = draft.topic
        note = draft.note
        nextStep = draft.nextStep
        hasNextStepDate = draft.nextStepDate != nil
        if let day = draft.nextStepDate { nextStepDate = day }
        rawTranscript = draft.rawTranscript
        lastAppliedSummary = draft.lastAppliedSummary
        newOpportunityTitle = draft.newOpportunityTitle
        if draft.wantsNewOpportunity {
            opportunityLink = .new
        } else if let id = draft.opportunityID, (try? repositories.opportunities.opportunity(id: id)) != nil {
            opportunityLink = .existing(id)
        } else {
            opportunityLink = .none
        }
        ownsDraft = true
    }

    private static func appending(_ segment: String, to text: String) -> String {
        if segment.isEmpty { return text }
        return text.isEmpty ? segment : text + " " + segment
    }

    var isEditing: Bool { existingVisit != nil }
    var canSave: Bool {
        guard customer != nil else { return false }
        if opportunityLink == .new { return !VisitText.singleLine(newOpportunityTitle).isEmpty }
        return true
    }

    // MARK: - Müşteri ve kişiler

    /// Müşteri değiştiğinde çağrılır: kişi listesi yenilenir, işaretler sıfırlanır.
    func customerChanged() {
        reloadContacts()
        selectedContactIDs = []
        opportunityLink = .none
        newOpportunityTitle = ""
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

    // MARK: - Fırsat

    /// Seçilebilecek fırsatlar: müşterinin açık fırsatları (+ düzenlenen ziyaretin zaten bağlı olduğu fırsat,
    /// kapanmış olsa bile). Beklenen kapanış tarihi yakın olan önce.
    var availableOpportunities: [Opportunity] {
        guard let customer, let all = try? repositories.opportunities.opportunities(for: customer) else { return [] }
        let linkedID = existingVisit?.opportunity?.id
        return PipelineGrouping.groups(from: all.filter { $0.stage.isOpen || $0.id == linkedID })
            .flatMap(\.opportunities)
    }

    private func selectedOpportunity() -> Opportunity? {
        guard case .existing(let id) = opportunityLink else { return nil }
        return try? repositories.opportunities.opportunity(id: id)
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
        note = Self.appending(segment, to: note)
        rawTranscript = Self.appending(segment, to: rawTranscript)
    }

    // MARK: - Claude ile düzenleme

    var canAskAssistant: Bool {
        customer != nil && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func assistantInput(instruction: String, today: Date = Date()) -> NoteAssistantInput {
        NoteAssistantInput(
            rawNote: note,
            customerName: customer?.name ?? "",
            contacts: contacts.filter { selectedContactIDs.contains($0.id) }.map { contact in
                contact.title.isEmpty ? contact.fullName : "\(contact.fullName) (\(contact.title))"
            },
            today: today,
            instruction: instruction
        )
    }

    /// Onaylanan öneriyi forma yazar. Değiştirilmeden önce ham not `transcript`'te saklanır.
    /// Boş gelen alanlar formdaki haliyle kalır; şablona uymayan cevapta yalnızca not değişir.
    func apply(_ suggestion: NoteSuggestion) {
        voice.stop()
        preserveRawNote()
        if !suggestion.summary.isEmpty {
            note = suggestion.summary
            lastAppliedSummary = suggestion.summary
        }
        guard suggestion.followsTemplate else { return }
        if !suggestion.topic.isEmpty { topic = suggestion.topic }
        if !suggestion.nextStep.isEmpty { nextStep = suggestion.nextStep }
        if let day = suggestion.followUpDate {
            hasNextStepDate = true
            nextStepDate = day
        }
    }

    /// Notta, ham metinde henüz bulunmayan bir şey varsa (elle yazılan veya düzeltilen not) ham metne eklenir.
    /// Önceki öneri değiştirilmeden duruyorsa ham not sayılmaz.
    private func preserveRawNote() {
        let current = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, current != lastAppliedSummary, !rawTranscript.contains(current) else { return }
        rawTranscript = rawTranscript.isEmpty ? current : rawTranscript + "\n\n" + current
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
        draft.newOpportunityTitle = opportunityLink == .new ? newOpportunityTitle : ""

        let selected = contacts.filter { selectedContactIDs.contains($0.id) }
        let service = VisitService(repositories: repositories, reminderMinutes: reminderMinutes, defaultCurrency: defaultCurrency)
        do {
            try service.save(draft, customer: customer, contacts: selected, opportunity: selectedOpportunity(), existing: existingVisit)
            discardDraft()
            return true
        } catch {
            errorMessage = "Ziyaret kaydedilemedi: \(error.localizedDescription)"
            return false
        }
    }
}
