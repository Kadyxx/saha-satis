import Foundation
import SwiftData

@MainActor
protocol VisitRepository {
    /// En yeni ziyaret en üstte.
    func fetchAll() throws -> [Visit]
    func visit(id: UUID) throws -> Visit?
    func visits(for customer: Customer) throws -> [Visit]
    func visits(on day: Date, calendar: Calendar) throws -> [Visit]
    func unexportedVisits(on day: Date, calendar: Calendar) throws -> [Visit]
    func add(_ visit: Visit, customer: Customer, contacts: [Contact], opportunity: Opportunity?) throws
    func update(_ visit: Visit) throws
    func delete(_ visit: Visit) throws
    /// Gün sonu dışa aktarmadan sonra ziyaretleri aktarıldı olarak işaretler.
    func markExported(_ visits: [Visit], at date: Date) throws
}

extension VisitRepository {
    func visits(on day: Date) throws -> [Visit] {
        try visits(on: day, calendar: .current)
    }

    func unexportedVisits(on day: Date) throws -> [Visit] {
        try unexportedVisits(on: day, calendar: .current)
    }
}

@MainActor
final class SwiftDataVisitRepository: VisitRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func fetchAll() throws -> [Visit] {
        try context.fetchAll(Visit.self).sorted { $0.date > $1.date }
    }

    func visit(id: UUID) throws -> Visit? {
        try context.fetchAll(Visit.self).first { $0.id == id }
    }

    func visits(for customer: Customer) throws -> [Visit] {
        try fetchAll().filter { $0.customer?.id == customer.id }
    }

    func visits(on day: Date, calendar: Calendar) throws -> [Visit] {
        try fetchAll().filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    func unexportedVisits(on day: Date, calendar: Calendar) throws -> [Visit] {
        try visits(on: day, calendar: calendar).filter { !$0.exportedToCRM }
    }

    func add(_ visit: Visit, customer: Customer, contacts: [Contact], opportunity: Opportunity?) throws {
        if visit.ownerUserID.isEmpty { visit.ownerUserID = ownerUserID }
        context.insert(visit)
        visit.customer = customer
        visit.contacts = contacts
        visit.opportunity = opportunity
        try context.saveAndNotify()
    }

    func update(_ visit: Visit) throws {
        visit.updatedAt = Date()
        try context.saveAndNotify()
    }

    func delete(_ visit: Visit) throws {
        context.delete(visit)
        try context.saveAndNotify()
    }

    func markExported(_ visits: [Visit], at date: Date) throws {
        for visit in visits {
            visit.exportedToCRM = true
            visit.exportedAt = date
            visit.updatedAt = Date()
        }
        try context.saveAndNotify()
    }
}
