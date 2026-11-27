import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Ortak (App Group) SwiftData deposundan widget verisini okur. Widget uzantısı ve uygulama aynı kodu kullanır.
@MainActor
enum WidgetDataLoader {
    static func load(repositories: Repositories) throws -> WidgetData {
        let tasks = try repositories.tasks.openTasks().map { task in
            WidgetTask(id: task.id, title: task.title, customerName: task.customer?.name, dueDate: task.dueDate)
        }

        let pending = try repositories.quotes.fetchAll().filter { $0.status == .sent || $0.status == .followUp }
        let totals: [WidgetMoney] = Currency.allCases.compactMap { currency in
            let amount = pending.filter { $0.currency == currency }.reduce(0) { $0 + $1.totalAmount }
            return amount > 0 ? WidgetMoney(currency: currency, amount: amount) : nil
        }

        let unexported = try repositories.visits.fetchAll().filter { !$0.exportedToCRM }.count
        return WidgetData(
            tasks: tasks,
            pendingQuoteCount: pending.count,
            pendingQuoteTotals: totals,
            unexportedVisitCount: unexported
        )
    }

    /// Gerçek depoyu açar; açılamazsa boş veri döner (widget "Bugün için takip yok" gösterir).
    /// App Group yoksa uygulamanın deposuna erişilemez; widget kendi klasöründe boş bir depo oluşturmaz.
    static func loadFromStore(isGroupAvailable: Bool = AppGroup.isAvailable) -> WidgetData {
        guard isGroupAvailable else { return WidgetData() }
        do {
            let container = try Persistence.makeContainer()
            return try withExtendedLifetime(container) {
                try load(repositories: Repositories.swiftData(context: container.mainContext))
            }
        } catch {
            return WidgetData()
        }
    }
}

/// Widget'taki onay kutusunun işi.
@MainActor
enum WidgetTaskCompleter {
    /// Görevi tamamlar. Görev yoksa veya zaten tamamsa `false`.
    @discardableResult
    static func complete(taskID: UUID, repositories: Repositories, now: Date = Date()) throws -> Bool {
        guard let task = try repositories.tasks.task(id: taskID), !task.isDone else { return false }
        try repositories.tasks.complete(task, at: now)
        return true
    }

    /// `CompleteTaskIntent`'in kullandığı yol: gerçek depoda tamamla, bekleyen bildirimi sil, widget'ları yenile.
    /// (Uygulama arka plandaysa bildirimler bir sonraki açılış / günlük yenilemede de yeniden hesaplanır.)
    @discardableResult
    static func completeInStore(taskID: UUID) -> Bool {
        var completed = false
        if let container = try? Persistence.makeContainer() {
            withExtendedLifetime(container) {
                let repositories = Repositories.swiftData(context: container.mainContext)
                completed = (try? complete(taskID: taskID, repositories: repositories)) ?? false
            }
        }
        if completed {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [TaskNotificationID.make(for: taskID)])
        }
        WidgetCenter.shared.reloadAllTimelines()
        return completed
    }
}
