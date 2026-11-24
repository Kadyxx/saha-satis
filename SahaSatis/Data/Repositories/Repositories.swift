import Foundation
import SwiftData

/// Tüm repository'lerin tek noktadan erişimi. Görünümler ve servisler yalnızca protokolleri
/// bilir; Faz 5'te sunucuya geçerken yalnızca bu yapının kurulumu değişir.
@MainActor
struct Repositories {
    let customers: CustomerRepository
    let contacts: ContactRepository
    let visits: VisitRepository
    let tasks: FollowUpTaskRepository
    let opportunities: OpportunityRepository
    let quotes: QuoteRepository
    let quoteItems: QuoteItemRepository
    let installedProducts: InstalledProductRepository

    /// SwiftData uygulamaları. `ownerUserID`, boş bırakılmış kayıtlara eklenirken damgalanır.
    static func swiftData(context: ModelContext, ownerUserID: String = "") -> Repositories {
        Repositories(
            customers: SwiftDataCustomerRepository(context: context, ownerUserID: ownerUserID),
            contacts: SwiftDataContactRepository(context: context, ownerUserID: ownerUserID),
            visits: SwiftDataVisitRepository(context: context, ownerUserID: ownerUserID),
            tasks: SwiftDataFollowUpTaskRepository(context: context, ownerUserID: ownerUserID),
            opportunities: SwiftDataOpportunityRepository(context: context, ownerUserID: ownerUserID),
            quotes: SwiftDataQuoteRepository(context: context, ownerUserID: ownerUserID),
            quoteItems: SwiftDataQuoteItemRepository(context: context, ownerUserID: ownerUserID),
            installedProducts: SwiftDataInstalledProductRepository(context: context, ownerUserID: ownerUserID)
        )
    }
}
