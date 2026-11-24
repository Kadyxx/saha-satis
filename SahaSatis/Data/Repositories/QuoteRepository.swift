import Foundation
import SwiftData

@MainActor
protocol QuoteRepository {
    /// En yeni teklif tarihi en üstte.
    func fetchAll() throws -> [Quote]
    func quote(id: UUID) throws -> Quote?
    func quotes(for customer: Customer) throws -> [Quote]
    func quotes(with status: QuoteStatus) throws -> [Quote]
    func add(_ quote: Quote, customer: Customer, opportunity: Opportunity?) throws
    func update(_ quote: Quote) throws
    func delete(_ quote: Quote) throws
    func setStatus(_ quote: Quote, to status: QuoteStatus) throws
}

@MainActor
final class SwiftDataQuoteRepository: QuoteRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func fetchAll() throws -> [Quote] {
        try context.fetchAll(Quote.self).sorted { $0.date > $1.date }
    }

    func quote(id: UUID) throws -> Quote? {
        try context.fetchAll(Quote.self).first { $0.id == id }
    }

    func quotes(for customer: Customer) throws -> [Quote] {
        try fetchAll().filter { $0.customer?.id == customer.id }
    }

    func quotes(with status: QuoteStatus) throws -> [Quote] {
        try fetchAll().filter { $0.status == status }
    }

    func add(_ quote: Quote, customer: Customer, opportunity: Opportunity?) throws {
        if quote.ownerUserID.isEmpty { quote.ownerUserID = ownerUserID }
        context.insert(quote)
        quote.customer = customer
        quote.opportunity = opportunity
        try context.save()
    }

    func update(_ quote: Quote) throws {
        quote.updatedAt = Date()
        try context.save()
    }

    func delete(_ quote: Quote) throws {
        context.delete(quote)
        try context.save()
    }

    func setStatus(_ quote: Quote, to status: QuoteStatus) throws {
        quote.status = status
        quote.updatedAt = Date()
        try context.save()
    }
}
