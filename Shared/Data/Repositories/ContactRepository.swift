import Foundation
import SwiftData

@MainActor
protocol ContactRepository {
    /// Önce asıl kişi, sonra ada göre.
    func contacts(for customer: Customer) throws -> [Contact]
    func contact(id: UUID) throws -> Contact?
    /// Müşterinin ilk kişisi otomatik asıl kişi olur; `isPrimary` ile eklenirse diğerleri asıl olmaktan çıkar.
    func add(_ contact: Contact, to customer: Customer) throws
    func update(_ contact: Contact) throws
    func delete(_ contact: Contact) throws
    /// Müşteride tek asıl kişi olacak şekilde işaretler.
    func setPrimary(_ contact: Contact) throws
}

@MainActor
final class SwiftDataContactRepository: ContactRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func contacts(for customer: Customer) throws -> [Contact] {
        try context.fetchAll(Contact.self)
            .filter { $0.customer?.id == customer.id }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
    }

    func contact(id: UUID) throws -> Contact? {
        try context.fetchAll(Contact.self).first { $0.id == id }
    }

    func add(_ contact: Contact, to customer: Customer) throws {
        if contact.ownerUserID.isEmpty { contact.ownerUserID = ownerUserID }
        let existing = try contacts(for: customer)
        context.insert(contact)
        contact.customer = customer
        if existing.isEmpty {
            contact.isPrimary = true
        } else if contact.isPrimary {
            existing.forEach { $0.isPrimary = false }
        }
        try context.saveAndNotify()
    }

    func update(_ contact: Contact) throws {
        contact.updatedAt = Date()
        try context.saveAndNotify()
    }

    func delete(_ contact: Contact) throws {
        context.delete(contact)
        try context.saveAndNotify()
    }

    func setPrimary(_ contact: Contact) throws {
        if let customer = contact.customer {
            for other in try contacts(for: customer) where other.id != contact.id {
                other.isPrimary = false
            }
        }
        contact.isPrimary = true
        contact.updatedAt = Date()
        try context.saveAndNotify()
    }
}
