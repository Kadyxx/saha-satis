import Foundation
import UserNotifications

/// `UNUserNotificationCenter` ile gerçek yerel bildirim planlayıcısı.
@MainActor
final class SystemNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        registerCategories()
    }

    /// Görev bildirimlerindeki aksiyonlar: Tamamlandı, Yarına ertele.
    private func registerCategories() {
        let complete = UNNotificationAction(
            identifier: NotificationIdentifiers.completeAction,
            title: "Tamamlandı",
            options: []
        )
        let postpone = UNNotificationAction(
            identifier: NotificationIdentifiers.postponeAction,
            title: "Yarına ertele",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: NotificationIdentifiers.taskCategory,
            actions: [complete, postpone],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func authorization() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func replaceAll(with notifications: [PlannedNotification]) async {
        center.removeAllPendingNotificationRequests()
        for notification in notifications where notification.fireDate.timeIntervalSinceNow > 2 {
            try? await center.add(request(for: notification))
        }
    }

    private func request(for notification: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default

        var info: [AnyHashable: Any] = [:]
        if let taskID = notification.taskID {
            info[NotificationIdentifiers.taskIDKey] = taskID.uuidString
        }
        if let customerID = notification.customerID {
            info[NotificationIdentifiers.customerIDKey] = customerID.uuidString
        }
        content.userInfo = info
        if notification.kind == .task {
            content.categoryIdentifier = NotificationIdentifiers.taskCategory
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: notification.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
    }
}
