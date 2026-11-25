import Foundation

enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

/// Bildirim iznini ve bekleyen bildirimleri yöneten sistem katmanı. Testlerde ve ekran görüntülerinde
/// sahte/boş uygulamalar kullanılır; gerçek uygulama `SystemNotificationScheduler`'dır.
@MainActor
protocol NotificationScheduling: AnyObject {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    /// Bekleyen TÜM bildirimleri silip verilenleri planlar.
    func replaceAll(with notifications: [PlannedNotification]) async
}

/// Hiçbir şey yapmaz (DEBUG ekran görüntüleri: izin penceresi görüntüyü kapatmasın).
@MainActor
final class NullNotificationScheduler: NotificationScheduling {
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> Bool { true }
    func replaceAll(with notifications: [PlannedNotification]) async {}
}

/// Bildirim kimlikleri ve aksiyonları (planlayıcı ile yanıt işleyicisi aynı sabitleri kullanır).
enum NotificationIdentifiers {
    static let taskCategory = "task"
    static let completeAction = "task.complete"
    static let postponeAction = "task.postpone"
    static let taskIDKey = "taskID"
    static let customerIDKey = "customerID"
}
