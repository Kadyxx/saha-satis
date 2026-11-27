import SwiftUI

/// Uygulama genelinde paylaşılan bağımlılıklar (SwiftUI ortamı üzerinden): repository'ler, ayarlar,
/// konuşma tanıma motoru üreticisi ve hatırlatma motoru. Ziyaret formu her açılışta yeni bir motorla çalışır.
@MainActor
final class AppContext: ObservableObject {
    let repositories: Repositories
    let settings: AppSettings
    let makeSpeechEngine: () -> SpeechEngine
    let reminders: ReminderScheduler
    /// Bildirim temsilcisi; `UNUserNotificationCenter.delegate` zayıf tuttuğu için burada saklanır.
    let notificationResponder = NotificationResponder()
    /// Ziyaret notu yardımcısı ("Claude ile düzenle"). İleride API uygulaması burada değiştirilir.
    let noteAssistant: NoteAssistant = ShareToClaudeAssistant()
    /// Görev/ziyaret/teklif değişince widget'ları yeniler.
    let widgetReloader = WidgetReloader()

    /// Başka bir ekrandan (bildirime dokunma, Bugün satırı) istenen sekme ve müşteri.
    /// Ekranlar işledikten sonra `nil`'e çeker.
    @Published var requestedTab: AppTab?
    @Published var customerToOpen: UUID?
    /// Widget'taki "+ Ziyaret" bağlantısı: ziyaret formunu uygulama düzeyinde açar.
    @Published var presentVisitForm = false

    // MARK: Yarım kalan ziyaret notu

    let draftStore: VisitDraftStore
    /// Cevap bekleyen taslak ("devam et / sil" sorusu).
    @Published var pendingDraft: VisitFormDraft?
    /// "Devam et" denildi: form bu taslakla açılır.
    @Published var resumingDraft: VisitFormDraft?

    // MARK: Yedekleme

    let backups: BackupRepository?
    /// Geri yükleme sırasında tüm ekranlar kaldırılır: silinen kayıtlara bakan görünüm kalmasın.
    @Published private(set) var isRestoring = false
    @Published var restoreResult: String?

    init(
        repositories: Repositories,
        settings: AppSettings,
        makeSpeechEngine: @escaping () -> SpeechEngine,
        notificationScheduler: NotificationScheduling,
        draftStore: VisitDraftStore? = nil,
        backups: BackupRepository? = nil
    ) {
        let drafts = draftStore ?? InMemoryVisitDraftStore()
        self.draftStore = drafts
        _pendingDraft = Published(initialValue: drafts.load())
        self.backups = backups
        self.repositories = repositories
        self.settings = settings
        self.makeSpeechEngine = makeSpeechEngine
        self.reminders = ReminderScheduler(
            repositories: repositories,
            settings: settings,
            scheduler: notificationScheduler
        )
        notificationResponder.handler = { [weak self] response in
            await self?.handleNotification(response)
        }
    }

    /// Form beklenmedik şekilde kapandıysa, kapanma animasyonu bitince taslağı sorar.
    func checkForPendingDraft(after delay: Duration = .milliseconds(700)) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            self.resumingDraft = nil
            self.pendingDraft = self.draftStore.load()
        }
    }

    func resumePendingDraft() {
        resumingDraft = pendingDraft
        pendingDraft = nil
    }

    func discardPendingDraft() {
        draftStore.delete()
        pendingDraft = nil
    }

    /// Tüm verinin ve ayarların yedek dosyası içeriği.
    func makeBackup(now: Date = Date()) throws -> BackupFile {
        guard let backups else { throw BackupError.damaged }
        return BackupFile(
            createdAt: now,
            appVersion: AppInfo.versionText,
            data: try backups.snapshot(),
            settings: BackupSettings(settings)
        )
    }

    /// Cihazdaki veriyi yedektekiyle değiştirir. `pause`: ekranların kaldırılması için beklenen süre.
    func restore(_ file: BackupFile, pause: Duration = .milliseconds(600)) async {
        guard let backups, !isRestoring else { return }
        isRestoring = true
        try? await Task.sleep(for: pause)
        do {
            try backups.replaceAll(with: file.data)
            file.settings?.apply(to: settings)
            // Taslak eski veriye ait kayıtlara bağlı olabilir.
            discardPendingDraft()
            customerToOpen = nil
            restoreResult = "Yedek geri yüklendi: \(file.data.customers.count) müşteri, \(file.data.visits.count) ziyaret."
        } catch {
            restoreResult = "Geri yüklenemedi, verileriniz değişmedi: \(error.localizedDescription)"
        }
        requestedTab = .settings
        isRestoring = false
    }

    /// Müşteri detayını Müşteriler sekmesinde açar.
    func open(customer: Customer) {
        customerToOpen = customer.id
        requestedTab = .customers
    }

    /// Widget bağlantıları (`sahasatis://...`). Görev: müşterisi varsa detayı, yoksa Bugün ekranı.
    func handle(url: URL) {
        guard let link = WidgetLink(url: url) else { return }
        switch link {
        case .today:
            requestedTab = .today
        case .newVisit:
            // Önce yarım kalan not sorusu yanıtlanmalı (yeni form taslağın üstüne yazardı).
            if pendingDraft == nil { presentVisitForm = true }
        case .task(let id):
            if let customer = (try? repositories.tasks.task(id: id))?.customer {
                open(customer: customer)
            } else {
                requestedTab = .today
            }
        }
    }

    /// Bildirim aksiyonları (Tamamlandı / Yarına ertele) ve bildirime dokunma (ilgili kaydı aç).
    func handleNotification(_ response: NotificationResponse) async {
        let actions = TaskActionService(repositories: repositories)
        let task = response.taskID.flatMap { try? repositories.tasks.task(id: $0) }

        if response.isComplete {
            if let task { try? actions.complete(task) }
        } else if response.isPostpone {
            if let task { try? actions.postpone(task, .tomorrow) }
        } else {
            // Bildirime dokunuldu: görevin müşterisi varsa detayı, yoksa Bugün ekranı.
            if let customerID = response.customerID {
                customerToOpen = customerID
                requestedTab = .customers
            } else {
                requestedTab = .today
            }
        }
        await reminders.refresh()
    }
}
