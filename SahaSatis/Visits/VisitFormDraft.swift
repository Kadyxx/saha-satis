import Foundation

/// Ziyaret formunun kaydedilmemiş hali. Uygulama kapanırsa bir sonraki açılışta forma geri yüklenir.
struct VisitFormDraft: Codable, Equatable, Sendable {
    /// Düzenlenen ziyaret (yeni ziyarette nil).
    var existingVisitID: UUID?
    var customerID: UUID?
    /// Yalnızca "yarım kalan not" sorusunda gösterilir.
    var customerName = ""
    var contactIDs: [UUID] = []
    var typeRaw = VisitType.visit.rawValue
    var date = Date()
    var topic = ""
    var note = ""
    var nextStep = ""
    /// Takip tarihi kapalıysa nil.
    var nextStepDate: Date?
    var opportunityID: UUID?
    var wantsNewOpportunity = false
    var newOpportunityTitle = ""
    var rawTranscript = ""
    var lastAppliedSummary: String?
    var savedAt = Date(timeIntervalSinceReferenceDate: 0)

    /// Kullanıcının kaybetmek istemeyeceği bir şey girildi mi? Yalnızca müşteri seçmek sayılmaz.
    var hasUserInput: Bool {
        let texts = [topic, note, nextStep, rawTranscript, newOpportunityTitle]
        return texts.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !contactIDs.isEmpty
            || nextStepDate != nil
    }
}

/// Tek taslaklık yerel depo (aynı anda yalnızca bir ziyaret formu açık olabilir).
@MainActor
protocol VisitDraftStore: AnyObject {
    func load() -> VisitFormDraft?
    func save(_ draft: VisitFormDraft) throws
    func delete()
}

/// Uygulamanın Application Support klasöründe tek JSON dosyası. Cihazdan çıkmaz.
@MainActor
final class FileVisitDraftStore: VisitDraftStore {
    private let url: URL

    init(url: URL = FileVisitDraftStore.defaultURL) {
        self.url = url
    }

    nonisolated static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "visit-draft.json")
    }

    /// Dosya yoksa veya okunamıyorsa nil.
    func load() -> VisitFormDraft? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(VisitFormDraft.self, from: data)
    }

    func save(_ draft: VisitFormDraft) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(draft).write(to: url, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Testler ve ekran görüntüsü modu: diske yazmaz.
@MainActor
final class InMemoryVisitDraftStore: VisitDraftStore {
    private(set) var draft: VisitFormDraft?
    private(set) var saveCount = 0

    init(draft: VisitFormDraft? = nil) {
        self.draft = draft
    }

    func load() -> VisitFormDraft? { draft }

    func save(_ draft: VisitFormDraft) throws {
        self.draft = draft
        saveCount += 1
    }

    func delete() {
        draft = nil
    }
}
