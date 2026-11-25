import Foundation
import Observation

/// Formdaki bir kalem satırı: alanlar kullanıcının yazdığı metin olarak tutulur, değerler ayrıştırılarak okunur.
struct QuoteItemRow: Identifiable, Equatable {
    var id = UUID()
    var catalogNumber = ""
    var itemDescription = ""
    var quantityText = "1"
    var unitPriceText = ""
    var discountText = ""

    /// Adet: ≥ 1 tam sayı (boş geçersiz).
    var quantity: Int? {
        guard let value = Int(quantityText.trimmingCharacters(in: .whitespaces)), value >= 1 else { return nil }
        return value
    }

    /// Birim fiyat: boş = 0; ayrıştırılamıyorsa nil.
    var unitPrice: Double? { Self.amount(unitPriceText) }

    /// İskonto %: boş = 0; 0–100 dışı veya ayrıştırılamıyorsa nil.
    var discountPercent: Double? {
        guard let value = Self.amount(discountText), value <= 100 else { return nil }
        return value
    }

    var isValid: Bool { quantity != nil && unitPrice != nil && discountPercent != nil }

    /// Hiçbir şey yazılmamış satır (kaydederken atlanır).
    var isBlank: Bool {
        VisitText.singleLine(catalogNumber).isEmpty
            && VisitText.singleLine(itemDescription).isEmpty
            && (unitPrice ?? 1) == 0
    }

    /// Satır toplamı (kuruşa yuvarlı); geçersizse 0.
    var lineTotal: Double {
        guard let quantity, let unitPrice, let discountPercent else { return 0 }
        return Money.rounded(Double(quantity) * unitPrice * (1 - discountPercent / 100))
    }

    /// İskontosuz satır toplamı (kuruşa yuvarlı); geçersizse 0.
    var grossTotal: Double {
        guard let quantity, let unitPrice else { return 0 }
        return Money.rounded(Double(quantity) * unitPrice)
    }

    private static func amount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? 0 : AmountParser.parse(trimmed)
    }

    init() {}

    init(item: QuoteItem) {
        id = item.id
        catalogNumber = item.catalogNumber
        itemDescription = item.itemDescription
        quantityText = String(item.quantity)
        unitPriceText = AmountParser.editingText(item.unitPrice)
        discountText = AmountParser.editingText(item.discountPercent)
    }
}

/// Teklif formunun durumu: başlık alanları, kalemler (ekle/sil/sırala) ve canlı toplamlar.
@MainActor
@Observable
final class QuoteFormModel {
    let existing: Quote?

    var customer: Customer?
    var opportunityID: UUID?
    var number = ""
    var date: Date
    var hasValidUntil = true
    var validUntil: Date
    var currency: Currency
    var items: [QuoteItemRow] = []
    var notes = ""
    var errorMessage: String?
    private(set) var savedQuote: Quote?

    private let repositories: Repositories
    private let reminderRules: QuoteReminderRules
    private let calendar: Calendar

    /// - Parameters:
    ///   - opportunity: Yeni teklifte önceden seçili fırsat (fırsat detayından açılınca).
    init(
        repositories: Repositories,
        reminderRules: QuoteReminderRules,
        defaultCurrency: Currency,
        quote: Quote? = nil,
        customer: Customer? = nil,
        opportunity: Opportunity? = nil,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        self.repositories = repositories
        self.reminderRules = reminderRules
        self.calendar = calendar
        self.existing = quote
        self.date = now
        self.validUntil = calendar.date(byAdding: .day, value: 30, to: now) ?? now
        self.currency = quote?.currency ?? defaultCurrency

        if let quote {
            self.customer = quote.customer
            self.opportunityID = quote.opportunity?.id
            number = quote.quoteNumber
            date = quote.date
            if let valid = quote.validUntil {
                validUntil = valid
            } else {
                hasValidUntil = false
            }
            notes = quote.notes
            items = quote.sortedItems.map(QuoteItemRow.init(item:))
        } else {
            self.customer = opportunity?.customer ?? customer
            self.opportunityID = opportunity?.id
            let existingNumbers = ((try? repositories.quotes.fetchAll()) ?? []).map(\.quoteNumber)
            number = QuoteNumbering.suggest(existing: existingNumbers, date: now, calendar: calendar)
            items = [QuoteItemRow()]
        }
    }

    var isEditing: Bool { existing != nil }

    /// Müşteri değişince bağlı fırsat seçimi sıfırlanır (fırsatlar müşteriye aittir).
    func customerChanged() {
        opportunityID = nil
    }

    // MARK: - Fırsat

    /// Seçilebilecek fırsatlar: müşterinin açık fırsatları (+ teklifin zaten bağlı olduğu fırsat, kapanmış olsa bile).
    var availableOpportunities: [Opportunity] {
        guard let customer, let all = try? repositories.opportunities.opportunities(for: customer) else { return [] }
        return PipelineGrouping.groups(from: all.filter { $0.stage.isOpen || $0.id == opportunityID }).flatMap(\.opportunities)
    }

    private func selectedOpportunity() -> Opportunity? {
        guard let opportunityID else { return nil }
        return try? repositories.opportunities.opportunity(id: opportunityID)
    }

    // MARK: - Kalemler

    func addItem() {
        items.append(QuoteItemRow())
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func canMove(_ id: UUID, by offset: Int) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        return items.indices.contains(index + offset)
    }

    func moveItem(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), items.indices.contains(index + offset) else { return }
        items.swapAt(index, index + offset)
    }

    // MARK: - Toplamlar (canlı)

    /// İskontosuz toplam.
    var subtotal: Double { Money.rounded(items.reduce(0) { $0 + $1.grossTotal }) }
    /// Genel toplam: kalem toplamlarının toplamı.
    var total: Double { Money.rounded(items.reduce(0) { $0 + $1.lineTotal }) }
    var discountTotal: Double { Money.rounded(subtotal - total) }

    // MARK: - Kaydetme

    var itemsAreValid: Bool { items.allSatisfy(\.isValid) }

    var canSave: Bool {
        customer != nil && !VisitText.singleLine(number).isEmpty && itemsAreValid
    }

    @discardableResult
    func save() -> Bool {
        guard canSave, let customer else { return false }
        var draft = QuoteDraft()
        draft.number = number
        draft.date = date
        draft.validUntil = hasValidUntil ? validUntil : nil
        draft.currency = currency
        draft.notes = notes
        draft.opportunity = selectedOpportunity()
        draft.items = items.filter { !$0.isBlank }.compactMap { row in
            guard let quantity = row.quantity, let price = row.unitPrice, let discount = row.discountPercent else { return nil }
            return QuoteItemDraft(
                id: row.id, catalogNumber: row.catalogNumber, itemDescription: row.itemDescription,
                quantity: quantity, unitPrice: price, discountPercent: discount
            )
        }

        do {
            savedQuote = try QuoteService(repositories: repositories, reminderRules: reminderRules, calendar: calendar)
                .save(draft, customer: customer, existing: existing)
            return true
        } catch {
            errorMessage = "Teklif kaydedilemedi: \(error.localizedDescription)"
            return false
        }
    }
}

/// Teklifler listesinin durumu: durum filtresi, bölümler ve sayılar.
@MainActor
@Observable
final class QuoteListModel {
    private let repositories: Repositories
    private let calendar: Calendar

    var filter: QuoteStatus?
    private(set) var sections = QuoteSections()
    private(set) var counts: [QuoteStatus: Int] = [:]
    private(set) var totalCount = 0
    private(set) var warningDays = 3
    private(set) var now = Date()
    var errorMessage: String?

    init(repositories: Repositories, calendar: Calendar = .current) {
        self.repositories = repositories
        self.calendar = calendar
    }

    /// `warningDays`: Ayarlar'daki geçerlilik uyarısı gün sayısı (bu kadar veya daha az kalan teklifler vurgulanır).
    func reload(warningDays: Int, now: Date = Date()) {
        do {
            let all = try repositories.quotes.fetchAll()
            self.warningDays = warningDays
            self.now = now
            totalCount = all.count
            counts = QuoteListing.counts(of: all)
            sections = QuoteListing.make(quotes: all, filter: filter, warningDays: warningDays, now: now, calendar: calendar)
        } catch {
            errorMessage = "Teklifler yüklenemedi: \(error.localizedDescription)"
        }
    }

    func count(for status: QuoteStatus?) -> Int {
        guard let status else { return totalCount }
        return counts[status] ?? 0
    }

    func expiryState(for quote: Quote) -> QuoteExpiryState {
        QuoteListing.expiryState(for: quote, warningDays: warningDays, now: now, calendar: calendar)
    }
}
