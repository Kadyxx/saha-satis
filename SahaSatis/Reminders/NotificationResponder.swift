import Foundation
import UserNotifications

/// Bildirime dokunma veya aksiyon düğmesi.
struct NotificationResponse: Equatable, Sendable {
    let actionID: String
    let taskID: UUID?
    let customerID: UUID?

    var isComplete: Bool { actionID == NotificationIdentifiers.completeAction }
    var isPostpone: Bool { actionID == NotificationIdentifiers.postponeAction }
}

/// `UNUserNotificationCenter` temsilcisi: uygulama açıkken de afiş gösterir, aksiyonları `handler`'a iletir.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    var handler: (@MainActor (NotificationResponse) async -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let parsed = NotificationResponse(
            actionID: response.actionIdentifier,
            taskID: (info[NotificationIdentifiers.taskIDKey] as? String).flatMap { UUID(uuidString: $0) },
            customerID: (info[NotificationIdentifiers.customerIDKey] as? String).flatMap { UUID(uuidString: $0) }
        )
        Task { @MainActor in
            await self.handler?(parsed)
            completionHandler()
        }
    }
}
