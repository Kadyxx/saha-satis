import Foundation
import SwiftData

@MainActor
protocol OpportunityRepository {
    /// En yeni oluşturulan en üstte.
    func fetchAll() throws -> [Opportunity]
    func opportunity(id: UUID) throws -> Opportunity?
    func opportunities(for customer: Customer) throws -> [Opportunity]
    func opportunities(in stage: OpportunityStage) throws -> [Opportunity]
    func add(_ opportunity: Opportunity, customer: Customer) throws
    func update(_ opportunity: Opportunity) throws
    func delete(_ opportunity: Opportunity) throws
    /// Aşamayı değiştirir; `lost` için sebep kaydedilir, diğer aşamalarda sebep temizlenir.
    func setStage(_ opportunity: Opportunity, to stage: OpportunityStage, lostReason: String?) throws
}

@MainActor
final class SwiftDataOpportunityRepository: OpportunityRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func fetchAll() throws -> [Opportunity] {
        try context.fetchAll(Opportunity.self).sorted { $0.createdAt > $1.createdAt }
    }

    func opportunity(id: UUID) throws -> Opportunity? {
        try context.fetchAll(Opportunity.self).first { $0.id == id }
    }

    func opportunities(for customer: Customer) throws -> [Opportunity] {
        try fetchAll().filter { $0.customer?.id == customer.id }
    }

    func opportunities(in stage: OpportunityStage) throws -> [Opportunity] {
        try fetchAll().filter { $0.stage == stage }
    }

    func add(_ opportunity: Opportunity, customer: Customer) throws {
        if opportunity.ownerUserID.isEmpty { opportunity.ownerUserID = ownerUserID }
        context.insert(opportunity)
        opportunity.customer = customer
        try context.save()
    }

    func update(_ opportunity: Opportunity) throws {
        opportunity.updatedAt = Date()
        try context.save()
    }

    func delete(_ opportunity: Opportunity) throws {
        context.delete(opportunity)
        try context.save()
    }

    func setStage(_ opportunity: Opportunity, to stage: OpportunityStage, lostReason: String?) throws {
        opportunity.stage = stage
        opportunity.lostReason = stage == .lost ? (lostReason ?? "") : ""
        opportunity.updatedAt = Date()
        try context.save()
    }
}
