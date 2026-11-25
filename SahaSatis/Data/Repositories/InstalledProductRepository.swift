import Foundation
import SwiftData

@MainActor
protocol InstalledProductRepository {
    /// Katalog numarasına göre sıralı.
    func products(for customer: Customer) throws -> [InstalledProduct]
    func product(id: UUID) throws -> InstalledProduct?
    /// Ömrünü tamamlayan veya üretimi duran ürünler (migrasyon fırsatı), tüm müşterilerde.
    func migrationCandidates() throws -> [InstalledProduct]
    func add(_ product: InstalledProduct, to customer: Customer) throws
    func update(_ product: InstalledProduct) throws
    func delete(_ product: InstalledProduct) throws
}

@MainActor
final class SwiftDataInstalledProductRepository: InstalledProductRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func products(for customer: Customer) throws -> [InstalledProduct] {
        try context.fetchAll(InstalledProduct.self)
            .filter { $0.customer?.id == customer.id }
            .sorted { $0.catalogNumber.localizedCaseInsensitiveCompare($1.catalogNumber) == .orderedAscending }
    }

    func product(id: UUID) throws -> InstalledProduct? {
        try context.fetchAll(InstalledProduct.self).first { $0.id == id }
    }

    func migrationCandidates() throws -> [InstalledProduct] {
        try context.fetchAll(InstalledProduct.self)
            .filter { $0.lifecycleStatus.isMigrationCandidate }
            .sorted { $0.catalogNumber.localizedCaseInsensitiveCompare($1.catalogNumber) == .orderedAscending }
    }

    func add(_ product: InstalledProduct, to customer: Customer) throws {
        if product.ownerUserID.isEmpty { product.ownerUserID = ownerUserID }
        context.insert(product)
        product.customer = customer
        try context.saveAndNotify()
    }

    func update(_ product: InstalledProduct) throws {
        product.updatedAt = Date()
        try context.saveAndNotify()
    }

    func delete(_ product: InstalledProduct) throws {
        context.delete(product)
        try context.saveAndNotify()
    }
}
