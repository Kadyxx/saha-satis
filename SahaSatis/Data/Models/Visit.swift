import Foundation
import SwiftData

@Model
final class Visit {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var ownerUserID: String = ""

    var date: Date = Date()
    var typeRaw: String = VisitType.visit.rawValue
    /// Ham ses metni; her zaman saklanır.
    var transcript: String = ""
    /// Düzenlenmiş (CRM'e uygun) not.
    var summary: String = ""
    var topics: [String] = []
    var nextStep: String = ""
    var nextStepDate: Date?
    var exportedToCRM: Bool = false
    var exportedAt: Date?

    var customer: Customer?
    @Relationship(inverse: \Contact.visits)
    var contacts: [Contact]?
    var opportunity: Opportunity?
    @Relationship(deleteRule: .nullify, inverse: \FollowUpTask.visit)
    var tasks: [FollowUpTask]?

    init(
        date: Date = Date(),
        type: VisitType = .visit,
        transcript: String = "",
        summary: String = "",
        topics: [String] = [],
        nextStep: String = "",
        nextStepDate: Date? = nil,
        ownerUserID: String = ""
    ) {
        self.date = date
        self.typeRaw = type.rawValue
        self.transcript = transcript
        self.summary = summary
        self.topics = topics
        self.nextStep = nextStep
        self.nextStepDate = nextStepDate
        self.ownerUserID = ownerUserID
    }

    var type: VisitType {
        get { VisitType(rawValue: typeRaw) ?? .visit }
        set { typeRaw = newValue.rawValue }
    }
}
