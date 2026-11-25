import Foundation

/// Bir görevin yerel bildirim kimliği. Hatırlatma motoru planlarken, widget da görevi tamamlayınca
/// bekleyen bildirimi silmek için aynı biçimi kullanır.
enum TaskNotificationID {
    static func make(for taskID: UUID) -> String {
        "task.\(taskID.uuidString)"
    }
}
