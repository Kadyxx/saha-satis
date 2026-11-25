import Foundation
import SwiftData

@Model
final class Opportunity {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var title: String = ""
    /// Açıklama (`description` adı NSObject ile çakıştığı için `details`).
    var details: String = ""
    var estimatedValue: Double = 0
    var currencyRaw: String = Currency.tl.rawValue
    var stageRaw: String = OpportunityStage.lead.rawValue
    var expectedCloseDate: Date?
    var lostReason: String = ""

    var customer: Customer?
    @Relationship(deleteRule: .nullify, inverse: \Quote.opportunity)
    var quotes: [Quote]?
    @Relationship(deleteRule: .nullify, inverse: \Visit.opportunity)
    var visits: [Visit]?
    /// Kapanış tarihi hatırlatması gibi bu fırsattan doğan görevler (fırsat silinince onlar da silinir).
    @Relationship(deleteRule: .cascade, inverse: \FollowUpTask.opportunity)
    var tasks: [FollowUpTask]?

    init(
        title: String,
        details: String = "",
        estimatedValue: Double = 0,
        currency: Currency = .tl,
        stage: OpportunityStage = .lead,
        expectedCloseDate: Date? = nil,
        ownerUserID: String = ""
    ) {
        self.title = title
        self.details = details
        self.estimatedValue = estimatedValue
        self.currencyRaw = currency.rawValue
        self.stageRaw = stage.rawValue
        self.expectedCloseDate = expectedCloseDate
        self.ownerUserID = ownerUserID
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .tl }
        set { currencyRaw = newValue.rawValue }
    }

    var stage: OpportunityStage {
        get { OpportunityStage(rawValue: stageRaw) ?? .lead }
        set { stageRaw = newValue.rawValue }
    }
}
