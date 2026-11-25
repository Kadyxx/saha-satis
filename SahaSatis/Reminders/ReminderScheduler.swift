import Combine
import Foundation

/// Hatırlatma motoru. Tüm `FollowUpTask` kayıtlarından yerel bildirimleri üretir (SPEC → Hatırlatma motoru):
/// her seferinde bekleyen bildirimlerin hepsini silip en yakın 64'ü yeniden planlar.
///
/// Yeniden hesaplama zamanları: uygulama açılışı / öne gelişi, her veri değişikliği (`appDataDidChange`,
/// kısa bir bekleme ile birleştirilir), ayar değişikliği ve `BGAppRefreshTask`.
/// Her hesaplamada önce ziyaret sıklığı görevleri eşitlenir (`VisitFrequencyService`).
@MainActor
final class ReminderScheduler: ObservableObject {
    let repositories: Repositories
    let settings: AppSettings
    private let scheduler: NotificationScheduling
    private let calendar: Calendar
    private let now: () -> Date

    /// Bugün ekranının "bildirimler kapalı" uyarısı için.
    @Published private(set) var authorization: NotificationAuthorization = .notDetermined
    /// Son hesaplanan plan (testler ve hata ayıklama için).
    private(set) var lastPlan: [PlannedNotification] = []
    private(set) var lastErrorMessage: String?

    private var inFlight: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var dataObserver: NSObjectProtocol?
    private var settingsObserver: AnyCancellable?

    init(
        repositories: Repositories,
        settings: AppSettings,
        scheduler: NotificationScheduling,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.repositories = repositories
        self.settings = settings
        self.scheduler = scheduler
        self.calendar = calendar
        self.now = now
    }

    // MARK: - Yaşam döngüsü

    /// Uygulama açılışı: değişiklikleri dinlemeye başla, izin iste (ilk seferde), yeniden planla.
    func start() async {
        observeChanges()
        let status = await scheduler.authorization()
        if status == .notDetermined {
            _ = await scheduler.requestAuthorization()
        }
        await refresh()
    }

    private func observeChanges() {
        guard dataObserver == nil else { return }
        dataObserver = NotificationCenter.default.addObserver(
            forName: .appDataDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.dataDidChange() }
        }
        settingsObserver = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.dataDidChange() }
        }
    }

    /// Art arda gelen değişiklikleri (ör. ziyaret kaydı + görev) tek hesaplamaya indirir.
    /// Hesaplamanın kendi yazdığı görevler yeni bir hesaplamayı tetikler; ikinci hesaplama bir şey
    /// yazmadığı için döngü orada biter.
    private func dataDidChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Hesaplama

    /// Ziyaret sıklığı görevlerini eşitler, planı hesaplar ve sisteme uygular. Çağrılar sıraya girer.
    func refresh() async {
        let previous = inFlight
        let work = Task { @MainActor [self] in
            await previous?.value
            await self.performRefresh()
        }
        inFlight = work
        await work.value
    }

    private func performRefresh() async {
        let current = now()
        let plan: [PlannedNotification]
        do {
            try VisitFrequencyService(
                repositories: repositories,
                rules: settings.visitFrequencyRules,
                calendar: calendar
            ).sync(now: current)
            plan = try makePlan(now: current)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = "Hatırlatmalar hesaplanamadı: \(error.localizedDescription)"
            return
        }
        lastPlan = plan
        await scheduler.replaceAll(with: plan)
        authorization = await scheduler.authorization()
    }

    func makePlan(now: Date) throws -> [PlannedNotification] {
        let snapshots = try repositories.tasks.openTasks().map { task in
            TaskSnapshot(
                id: task.id,
                title: task.title,
                customerName: task.customer?.name,
                customerID: task.customer?.id,
                dueDate: task.dueDate
            )
        }
        let unexported = try repositories.visits.unexportedVisits(on: now, calendar: calendar).count
        return ReminderPlanner.plan(
            tasks: snapshots,
            unexportedVisitsToday: unexported,
            settings: settings.reminderSnapshot,
            now: now,
            calendar: calendar
        )
    }
}
