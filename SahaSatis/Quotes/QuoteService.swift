import Foundation

/// Teklif kalemi formu → servis.
struct QuoteItemDraft: Identifiable, Equatable {
    /// Mevcut kalemden geliyorsa `QuoteItem.id`, yeni satırsa rastgele (depoda karşılığı yoktur).
    var id = UUID()
    var catalogNumber = ""
    var itemDescription = ""
    var quantity = 1
    var unitPrice: Double = 0
    var discountPercent: Double = 0

    /// Satır toplamı (kuruşa yuvarlı): adet × birim fiyat × (1 − iskonto%).
    var lineTotal: Double {
        Money.rounded(Double(quantity) * unitPrice * (1 - discountPercent / 100))
    }
}

/// Teklif formunun ürettiği değerler.
struct QuoteDraft {
    var number = ""
    var date = Date()
    var validUntil: Date?
    var currency: Currency = .tl
    var notes = ""
    var opportunity: Opportunity?
    /// Form sırasıyla.
    var items: [QuoteItemDraft] = []
}

/// Teklif iş kuralları (Repository'lerin üstünde): kaydetme, durum değiştirme, takip günleri, silme; her birinde
/// takip/geçerlilik görevlerini eşitleme (`QuoteReminderService`).
@MainActor
struct QuoteService {
    let repositories: Repositories
    let reminderRules: QuoteReminderRules
    var calendar: Calendar = .current

    private var reminders: QuoteReminderService {
        QuoteReminderService(repositories: repositories, rules: reminderRules, calendar: calendar)
    }

    /// Yeni teklif Taslak olarak açılır. Kalemler form sırasıyla saklanır (mevcutlar güncellenir, olmayanlar silinir).
    @discardableResult
    func save(_ draft: QuoteDraft, customer: Customer, existing: Quote?, now: Date = Date()) throws -> Quote {
        let quote: Quote
        if let existing {
            quote = existing
            apply(draft, to: quote)
            quote.customer = customer
            quote.opportunity = draft.opportunity
            try repositories.quotes.update(quote)
        } else {
            quote = Quote()
            apply(draft, to: quote)
            try repositories.quotes.add(quote, customer: customer, opportunity: draft.opportunity)
        }
        try syncItems(draft.items, for: quote)
        // Geçerlilik tarihi/numara değişmiş olabilir: açık geçerlilik uyarısını güncelle.
        try reminders.refresh(quote, now: now, replaceFollowUps: false, updateExisting: true)
        return quote
    }

    /// Durumu değiştirir.
    /// - Bekleyen duruma (Gönderildi/Takipte) ilk geçişte `sentAt = şimdi` olur ve takip günleri + geçerlilik uyarısı
    ///   kurulur; Gönderildi ↔ Takipte arasında görevler değişmez.
    /// - Taslak, Kazanıldı, Kaybedildi: bekleyen tüm takip/uyarı görevleri silinir. Taslağa dönünce `sentAt` temizlenir.
    /// - `lost` için sebep kaydedilir (diğer durumlarda temizlenir).
    func setStatus(_ quote: Quote, to status: QuoteStatus, lostReason: String? = nil, now: Date = Date()) throws {
        let wasPending = quote.status.isPending
        let becomesPending = status.isPending && !wasPending
        if becomesPending { quote.sentAt = now }
        if status == .draft { quote.sentAt = nil }
        quote.lostReason = status == .lost ? VisitText.singleLine(lostReason ?? "") : ""
        try repositories.quotes.setStatus(quote, to: status)
        try reminders.refresh(quote, now: now, replaceFollowUps: becomesPending, updateExisting: becomesPending)
    }

    /// Teklife özel takip günleri (boş liste = Ayarlar'daki varsayılan). Açık takip görevleri yeni günlere göre yeniden kurulur.
    func setFollowUpDays(_ quote: Quote, to days: [Int], now: Date = Date()) throws {
        quote.followUpDays = Array(Set(days.filter { (1...365).contains($0) })).sorted()
        try repositories.quotes.update(quote)
        try reminders.refresh(quote, now: now, replaceFollowUps: true, updateExisting: false)
    }

    func delete(_ quote: Quote) throws {
        try repositories.quotes.delete(quote)
    }

    /// Teklif kazanılınca "bağlı fırsat da Kazanıldı olsun mu?" sorusu için: bağlı fırsat varsa ve henüz Kazanıldı değilse o.
    static func opportunityToWin(for quote: Quote) -> Opportunity? {
        guard let opportunity = quote.opportunity, opportunity.stage != .won else { return nil }
        return opportunity
    }

    // MARK: - Yardımcılar

    private func apply(_ draft: QuoteDraft, to quote: Quote) {
        quote.quoteNumber = VisitText.singleLine(draft.number)
        quote.date = draft.date
        quote.validUntil = draft.validUntil.map { calendar.startOfDay(for: $0) }
        quote.currency = draft.currency
        quote.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func syncItems(_ drafts: [QuoteItemDraft], for quote: Quote) throws {
        let existing = try repositories.quoteItems.items(for: quote)
        let byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let keptIDs = Set(drafts.map(\.id))
        for item in existing where !keptIDs.contains(item.id) {
            try repositories.quoteItems.delete(item)
        }
        for (index, draft) in drafts.enumerated() {
            if let item = byID[draft.id] {
                fill(item, from: draft, position: index)
                try repositories.quoteItems.update(item)
            } else {
                let item = QuoteItem()
                fill(item, from: draft, position: index)
                try repositories.quoteItems.add(item, to: quote)
            }
        }
    }

    private func fill(_ item: QuoteItem, from draft: QuoteItemDraft, position: Int) {
        item.catalogNumber = VisitText.singleLine(draft.catalogNumber)
        item.itemDescription = draft.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        item.quantity = max(draft.quantity, 1)
        item.unitPrice = max(draft.unitPrice, 0)
        item.discountPercent = min(max(draft.discountPercent, 0), 100)
        item.position = position
    }
}
