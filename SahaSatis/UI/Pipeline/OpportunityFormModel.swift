import Foundation
import Observation

/// Fırsat formunun durumu: müşteri, başlık, açıklama, tahmini tutar, para birimi, aşama, beklenen kapanış tarihi,
/// kayıp sebebi. Kaydetme `OpportunityService` üzerinden yapılır (kapanış hatırlatması dahil).
@MainActor
@Observable
final class OpportunityFormModel {
    let existing: Opportunity?

    var customer: Customer?
    var title = ""
    var details = ""
    /// Kullanıcının yazdığı tutar metni ("1.250,50", "1250.5"); bkz. `AmountParser`.
    var amountText = ""
    var currency: Currency
    var stage: OpportunityStage = .lead
    var hasCloseDate = false
    var closeDate: Date
    var lostReason = ""
    var errorMessage: String?
    private(set) var savedOpportunity: Opportunity?

    private let repositories: Repositories
    private let reminderRules: OpportunityReminderRules
    private let calendar: Calendar

    init(
        repositories: Repositories,
        reminderRules: OpportunityReminderRules,
        defaultCurrency: Currency,
        opportunity: Opportunity? = nil,
        customer: Customer? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.repositories = repositories
        self.reminderRules = reminderRules
        self.calendar = calendar
        self.existing = opportunity
        self.customer = opportunity?.customer ?? customer
        self.currency = opportunity?.currency ?? defaultCurrency
        // Tarih anahtarı açılınca önerilen gün: iki hafta sonrası.
        self.closeDate = calendar.date(byAdding: .day, value: 14, to: now) ?? now

        if let opportunity {
            title = opportunity.title
            details = opportunity.details
            amountText = AmountParser.editingText(opportunity.estimatedValue)
            stage = opportunity.stage
            lostReason = opportunity.lostReason
            if let close = opportunity.expectedCloseDate {
                hasCloseDate = true
                closeDate = close
            }
        }
    }

    var isEditing: Bool { existing != nil }

    /// Boş tutar 0 sayılır; yazılmış ama ayrıştırılamayan tutar geçersizdir.
    var amountValue: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : AmountParser.parse(trimmed)
    }

    var amountIsValid: Bool { amountValue != nil }

    var canSave: Bool {
        customer != nil && !VisitText.singleLine(title).isEmpty && amountIsValid
    }

    /// "Kaybedildi" seçilince kayıp sebebi sorulur.
    var asksLostReason: Bool { stage == .lost }

    @discardableResult
    func save() -> Bool {
        guard canSave, let customer, let amount = amountValue else { return false }
        var draft = OpportunityDraft()
        draft.title = title
        draft.details = details
        draft.estimatedValue = amount
        draft.currency = currency
        draft.stage = stage
        draft.expectedCloseDate = hasCloseDate ? calendar.startOfDay(for: closeDate) : nil
        draft.lostReason = lostReason

        do {
            savedOpportunity = try OpportunityService(repositories: repositories, reminderRules: reminderRules, calendar: calendar)
                .save(draft, customer: customer, existing: existing)
            return true
        } catch {
            errorMessage = "Fırsat kaydedilemedi: \(error.localizedDescription)"
            return false
        }
    }
}
