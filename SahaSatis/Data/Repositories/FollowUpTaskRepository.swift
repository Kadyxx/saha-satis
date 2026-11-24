import Foundation
import SwiftData

@MainActor
protocol FollowUpTaskRepository {
    func fetchAll() throws -> [FollowUpTask]
    func task(id: UUID) throws -> FollowUpTask?
    func tasks(for customer: Customer) throws -> [FollowUpTask]
    /// Tamamlanmamış görevler, vade tarihine göre artan.
    func openTasks() throws -> [FollowUpTask]
    /// Vadesi `date`'ten önce olan tamamlanmamış görevler (gecikmiş).
    func overdueTasks(asOf date: Date, calendar: Calendar) throws -> [FollowUpTask]
    /// Vadesi verilen güne düşen tamamlanmamış görevler.
    func openTasks(on day: Date, calendar: Calendar) throws -> [FollowUpTask]
    /// Bildirim motoru için: vadesi en yakın `limit` tamamlanmamış görev (iOS en fazla 64 bildirim planlar).
    func nextOpenTasks(limit: Int) throws -> [FollowUpTask]
    func add(_ task: FollowUpTask, customer: Customer?, quote: Quote?, visit: Visit?) throws
    func update(_ task: FollowUpTask) throws
    func delete(_ task: FollowUpTask) throws
    func complete(_ task: FollowUpTask, at date: Date) throws
    func postpone(_ task: FollowUpTask, to newDueDate: Date) throws
    /// Bir teklifin bekleyen (tamamlanmamış) takiplerini siler; teklif kazanıldı/kaybedildi olunca kullanılır.
    func cancelOpenTasks(for quote: Quote) throws
}

extension FollowUpTaskRepository {
    func overdueTasks(asOf date: Date) throws -> [FollowUpTask] {
        try overdueTasks(asOf: date, calendar: .current)
    }

    func openTasks(on day: Date) throws -> [FollowUpTask] {
        try openTasks(on: day, calendar: .current)
    }
}

@MainActor
final class SwiftDataFollowUpTaskRepository: FollowUpTaskRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func fetchAll() throws -> [FollowUpTask] {
        try context.fetchAll(FollowUpTask.self).sorted { $0.dueDate < $1.dueDate }
    }

    func task(id: UUID) throws -> FollowUpTask? {
        try context.fetchAll(FollowUpTask.self).first { $0.id == id }
    }

    func tasks(for customer: Customer) throws -> [FollowUpTask] {
        try fetchAll().filter { $0.customer?.id == customer.id }
    }

    func openTasks() throws -> [FollowUpTask] {
        try fetchAll().filter { !$0.isDone }
    }

    func overdueTasks(asOf date: Date, calendar: Calendar) throws -> [FollowUpTask] {
        let startOfDay = calendar.startOfDay(for: date)
        return try openTasks().filter { $0.dueDate < startOfDay }
    }

    func openTasks(on day: Date, calendar: Calendar) throws -> [FollowUpTask] {
        try openTasks().filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
    }

    func nextOpenTasks(limit: Int) throws -> [FollowUpTask] {
        Array(try openTasks().prefix(max(0, limit)))
    }

    func add(_ task: FollowUpTask, customer: Customer?, quote: Quote?, visit: Visit?) throws {
        if task.ownerUserID.isEmpty { task.ownerUserID = ownerUserID }
        context.insert(task)
        task.customer = customer
        task.quote = quote
        task.visit = visit
        try context.save()
    }

    func update(_ task: FollowUpTask) throws {
        task.updatedAt = Date()
        try context.save()
    }

    func delete(_ task: FollowUpTask) throws {
        context.delete(task)
        try context.save()
    }

    func complete(_ task: FollowUpTask, at date: Date) throws {
        task.isDone = true
        task.doneAt = date
        task.updatedAt = Date()
        try context.save()
    }

    func postpone(_ task: FollowUpTask, to newDueDate: Date) throws {
        task.dueDate = newDueDate
        task.updatedAt = Date()
        try context.save()
    }

    func cancelOpenTasks(for quote: Quote) throws {
        let pending = try openTasks().filter { $0.quote?.id == quote.id }
        for task in pending {
            context.delete(task)
        }
        try context.save()
    }
}
