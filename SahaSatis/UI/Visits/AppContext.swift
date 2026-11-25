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

    /// Başka bir ekrandan (bildirime dokunma, Bugün satırı) istenen sekme ve müşteri.
    /// Ekranlar işledikten sonra `nil`'e çeker.
    @Published var requestedTab: AppTab?
    @Published var customerToOpen: UUID?

    init(
        repositories: Repositories,
        settings: AppSettings,
        makeSpeechEngine: @escaping () -> SpeechEngine,
        notificationScheduler: NotificationScheduling
    ) {
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

    /// Müşteri detayını Müşteriler sekmesinde açar.
    func open(customer: Customer) {
        customerToOpen = customer.id
        requestedTab = .customers
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
