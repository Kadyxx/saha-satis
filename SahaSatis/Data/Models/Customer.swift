import Foundation
import SwiftData

/// Müşteri. Merkezdeki modeldir; diğer modeller ona bağlanır.
/// CloudKit kısıtları: tüm özellikler varsayılan değerli/opsiyonel, `unique` yok, ilişkiler opsiyonel.
@Model
final class Customer {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var name: String = ""
    /// Kullanıcının bölge listesinden seçilir; sabit kodlanmaz.
    var city: String = ""
    var district: String = ""
    /// Organize sanayi bölgesi (OSB).
    var industrialZone: String = ""
    var sector: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?

    var statusRaw: String = CustomerStatus.potential.rawValue
    var ratingRaw: String = CustomerRating.promising.rawValue
    var ratingNote: String = ""
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Contact.customer)
    var contacts: [Contact]?
    @Relationship(deleteRule: .cascade, inverse: \Visit.customer)
    var visits: [Visit]?
    @Relationship(deleteRule: .cascade, inverse: \Opportunity.customer)
    var opportunities: [Opportunity]?
    @Relationship(deleteRule: .cascade, inverse: \Quote.customer)
    var quotes: [Quote]?
    @Relationship(deleteRule: .cascade, inverse: \InstalledProduct.customer)
    var installedBase: [InstalledProduct]?
    @Relationship(deleteRule: .cascade, inverse: \FollowUpTask.customer)
    var tasks: [FollowUpTask]?

    init(
        name: String,
        city: String = "",
        district: String = "",
        industrialZone: String = "",
        sector: String = "",
        address: String = "",
        status: CustomerStatus = .potential,
        rating: CustomerRating = .promising,
        ratingNote: String = "",
        notes: String = "",
        ownerUserID: String = ""
    ) {
        self.name = name
        self.city = city
        self.district = district
        self.industrialZone = industrialZone
        self.sector = sector
        self.address = address
        self.statusRaw = status.rawValue
        self.ratingRaw = rating.rawValue
        self.ratingNote = ratingNote
        self.notes = notes
        self.ownerUserID = ownerUserID
    }

    var status: CustomerStatus {
        get { CustomerStatus(rawValue: statusRaw) ?? .potential }
        set { statusRaw = newValue.rawValue }
    }

    var rating: CustomerRating {
        get { CustomerRating(rawValue: ratingRaw) ?? .promising }
        set { ratingRaw = newValue.rawValue }
    }

    /// Hesaplanan: en yeni ziyaretin tarihi.
    var lastVisitDate: Date? {
        (visits ?? []).map(\.date).max()
    }

    /// Kurulu bazda ömrünü tamamlamış veya üretimi durmuş ürün varsa "Migrasyon fırsatı".
    var hasMigrationOpportunity: Bool {
        (installedBase ?? []).contains { $0.lifecycleStatus.isMigrationCandidate }
    }
}
