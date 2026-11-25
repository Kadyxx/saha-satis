import Foundation
import SwiftData

/// Takip / görev. Tüm hatırlatmalar bu kayıtlardan üretilir.
@Model
final class FollowUpTask {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var title: String = ""
    var dueDate: Date = Date()
    var isDone: Bool = false
    var doneAt: Date?
    var sourceRaw: String = TaskSource.manual.rawValue
    /// Planlanmış yerel bildirimin kimliği (bildirim yoksa boş).
    var notificationID: String = ""

    var customer: Customer?
    var quote: Quote?
    var visit: Visit?

    init(
        title: String,
        dueDate: Date = Date(),
        source: TaskSource = .manual,
        ownerUserID: String = ""
    ) {
        self.title = title
        self.dueDate = dueDate
        self.sourceRaw = source.rawValue
        self.ownerUserID = ownerUserID
    }

    var source: TaskSource {
        get { TaskSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
