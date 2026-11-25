import Foundation

/// Fırsat formunun ürettiği değerler.
struct OpportunityDraft: Equatable {
    var title = ""
    var details = ""
    var estimatedValue: Double = 0
    var currency: Currency = .tl
    var stage: OpportunityStage = .lead
    var expectedCloseDate: Date?
    /// Yalnızca `stage == .lost` iken kaydedilir.
    var lostReason = ""
}

/// Fırsat iş kuralları (Repository'lerin üstünde): kaydetme, aşama değiştirme, silme ve her birinde
/// kapanış hatırlatmasını eşitleme (`OpportunityReminderService`).
@MainActor
struct OpportunityService {
    let repositories: Repositories
    let reminderRules: OpportunityReminderRules
    var calendar: Calendar = .current

    private var reminders: OpportunityReminderService {
        OpportunityReminderService(repositories: repositories, rules: reminderRules, calendar: calendar)
    }

    @discardableResult
    func save(_ draft: OpportunityDraft, customer: Customer, existing: Opportunity?, now: Date = Date()) throws -> Opportunity {
        let opportunity: Opportunity
        if let existing {
            opportunity = existing
            apply(draft, to: opportunity)
            opportunity.customer = customer
            try repositories.opportunities.update(opportunity)
        } else {
            opportunity = Opportunity(title: "")
            apply(draft, to: opportunity)
            try repositories.opportunities.add(opportunity, customer: customer)
        }
        try reminders.refresh(opportunity, now: now)
        return opportunity
    }

    /// Aşamayı değiştirir. `lost` için sebep kaydedilir; Kazanıldı/Kaybedildi olunca bekleyen kapanış
    /// hatırlatması silinir, açık bir aşamaya geri dönülürse (tarih gelecekteyse) yeniden kurulur.
    func setStage(_ opportunity: Opportunity, to stage: OpportunityStage, lostReason: String? = nil, now: Date = Date()) throws {
        let reason = lostReason.map(VisitText.singleLine)
        try repositories.opportunities.setStage(opportunity, to: stage, lostReason: reason)
        try reminders.refresh(opportunity, now: now)
    }

    func delete(_ opportunity: Opportunity) throws {
        try repositories.opportunities.delete(opportunity)
    }

    private func apply(_ draft: OpportunityDraft, to opportunity: Opportunity) {
        opportunity.title = VisitText.singleLine(draft.title)
        opportunity.details = draft.details.trimmingCharacters(in: .whitespacesAndNewlines)
        opportunity.estimatedValue = max(draft.estimatedValue, 0)
        opportunity.currency = draft.currency
        opportunity.stage = draft.stage
        opportunity.expectedCloseDate = draft.expectedCloseDate
        opportunity.lostReason = draft.stage == .lost ? VisitText.singleLine(draft.lostReason) : ""
    }
}
