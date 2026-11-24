import Foundation
import SwiftData

@MainActor
protocol QuoteItemRepository {
    /// Eklenme sırasına göre.
    func items(for quote: Quote) throws -> [QuoteItem]
    func item(id: UUID) throws -> QuoteItem?
    func add(_ item: QuoteItem, to quote: Quote) throws
    func update(_ item: QuoteItem) throws
    func delete(_ item: QuoteItem) throws
}

@MainActor
final class SwiftDataQuoteItemRepository: QuoteItemRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func items(for quote: Quote) throws -> [QuoteItem] {
        try context.fetchAll(QuoteItem.self)
            .filter { $0.quote?.id == quote.id }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func item(id: UUID) throws -> QuoteItem? {
        try context.fetchAll(QuoteItem.self).first { $0.id == id }
    }

    func add(_ item: QuoteItem, to quote: Quote) throws {
        if item.ownerUserID.isEmpty { item.ownerUserID = ownerUserID }
        context.insert(item)
        item.quote = quote
        quote.updatedAt = Date()
        try context.save()
    }

    func update(_ item: QuoteItem) throws {
        let now = Date()
        item.updatedAt = now
        item.quote?.updatedAt = now
        try context.save()
    }

    func delete(_ item: QuoteItem) throws {
        item.quote?.updatedAt = Date()
        context.delete(item)
        try context.save()
    }
}
