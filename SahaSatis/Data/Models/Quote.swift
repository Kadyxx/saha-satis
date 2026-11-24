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

    /// Hesaplanan: kalem toplamlarının toplamı.
    var totalAmount: Double {
        (items ?? []).reduce(0) { $0 + $1.lineTotal }
    }

    /// Bu teklif için geçerli takip günleri: kendi listesi doluysa o, değilse verilen varsayılan.
    func effectiveFollowUpDays(defaultDays: [Int]) -> [Int] {
        followUpDays.isEmpty ? defaultDays : followUpDays
    }
}
