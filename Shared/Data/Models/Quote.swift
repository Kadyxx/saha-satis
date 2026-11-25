import Foundation
import SwiftData

@Model
final class Quote {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var quoteNumber: String = ""
    var date: Date = Date()
    var validUntil: Date?
    var currencyRaw: String = Currency.tl.rawValue
    var statusRaw: String = QuoteStatus.draft.rawValue
    /// Bu teklife özel takip günleri (gönderimden itibaren). Boşsa ayarlardaki varsayılan kullanılır.
    var followUpDays: [Int] = []
    var notes: String = ""
    /// Kaybedildi iken kayıp sebebi (diğer durumlarda boş).
    var lostReason: String = ""
    /// Durum "Gönderildi/Takipte"ye geçtiği an; takip günleri bu günden sayılır. Taslağa dönünce temizlenir.
    var sentAt: Date?

    var customer: Customer?
    var opportunity: Opportunity?
    @Relationship(deleteRule: .cascade, inverse: \QuoteItem.quote)
    var items: [QuoteItem]?
    @Relationship(deleteRule: .cascade, inverse: \FollowUpTask.quote)
    var tasks: [FollowUpTask]?

    init(
        quoteNumber: String = "",
        date: Date = Date(),
        validUntil: Date? = nil,
        currency: Currency = .tl,
        status: QuoteStatus = .draft,
        followUpDays: [Int] = [],
        notes: String = "",
        ownerUserID: String = ""
    ) {
        self.quoteNumber = quoteNumber
        self.date = date
        self.validUntil = validUntil
        self.currencyRaw = currency.rawValue
        self.statusRaw = status.rawValue
        self.followUpDays = followUpDays
        self.notes = notes
        self.ownerUserID = ownerUserID
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .tl }
        set { currencyRaw = newValue.rawValue }
    }

    var status: QuoteStatus {
        get { QuoteStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    /// Hesaplanan: kalem toplamlarının toplamı (kuruşa yuvarlı).
    var totalAmount: Double {
        Money.rounded((items ?? []).reduce(0) { $0 + $1.lineTotal })
    }

    /// Hesaplanan: iskonto uygulanmadan önceki toplam (adet × birim fiyat).
    var subtotalAmount: Double {
        Money.rounded((items ?? []).reduce(0) { $0 + $1.grossTotal })
    }

    /// Kalemler form sırasına göre (`position`, eşitlikte eklenme sırası).
    var sortedItems: [QuoteItem] {
        (items ?? []).sorted { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }
    }

    /// Bu teklif için geçerli takip günleri: kendi listesi doluysa o, değilse verilen varsayılan.
    func effectiveFollowUpDays(defaultDays: [Int]) -> [Int] {
        followUpDays.isEmpty ? defaultDays : followUpDays
    }
}
