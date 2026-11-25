import XCTest
@testable import SahaSatis

/// Toplam hesabı, iskonto, kalem satırı doğrulama, numaralama, liste kuralları.
final class QuoteMathTests: XCTestCase {
    func testLineTotalAppliesDiscountAndRoundsToCents() {
        XCTAssertEqual(QuoteItem(quantity: 3, unitPrice: 19.99, discountPercent: 10).lineTotal, 53.97)
        XCTAssertEqual(QuoteItem(quantity: 2, unitPrice: 142_500, discountPercent: 5).lineTotal, 270_750)
        XCTAssertEqual(QuoteItem(quantity: 4, unitPrice: 21_200, discountPercent: 10).lineTotal, 76_320)
        XCTAssertEqual(QuoteItem(quantity: 1, unitPrice: 100, discountPercent: 100).lineTotal, 0)
        XCTAssertEqual(QuoteItem(quantity: 3, unitPrice: 0.1).lineTotal, 0.3, "Kayan nokta gürültüsü yuvarlanır")
    }

    func testGrossTotalIgnoresDiscount() {
        let item = QuoteItem(quantity: 4, unitPrice: 250, discountPercent: 10)
        XCTAssertEqual(item.grossTotal, 1000)
        XCTAssertEqual(item.lineTotal, 900)
    }

    func testMoneyRounding() {
        XCTAssertEqual(Money.rounded(1.005 * 100 / 100), 1.0, accuracy: 0.011)
        XCTAssertEqual(Money.rounded(10.126), 10.13)
        XCTAssertEqual(Money.rounded(10.124), 10.12)
    }

    @MainActor
    func testQuoteTotalsAndItemOrder() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-1")
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
        let specs: [(String, Int, Double, Double, Int)] = [("C", 2, 142_500, 5, 2), ("A", 4, 18_750, 0, 0), ("B", 4, 21_200, 10, 1)]
        for spec in specs {
            let item = QuoteItem(catalogNumber: spec.0, quantity: spec.1, unitPrice: spec.2, discountPercent: spec.3)
            item.position = spec.4
            try env.repos.quoteItems.add(item, to: quote)
        }

        XCTAssertEqual(quote.totalAmount, 270_750 + 75_000 + 76_320)
        XCTAssertEqual(quote.subtotalAmount, 285_000 + 75_000 + 84_800)
        XCTAssertEqual(quote.sortedItems.map(\.catalogNumber), ["A", "B", "C"])
        XCTAssertEqual(try env.repos.quoteItems.items(for: quote).map(\.catalogNumber), ["A", "B", "C"])
    }
}

final class QuoteItemRowTests: XCTestCase {
    private func row(qty: String = "1", price: String = "", discount: String = "") -> QuoteItemRow {
        var row = QuoteItemRow()
        row.quantityText = qty
        row.unitPriceText = price
        row.discountText = discount
        return row
    }

    func testParsesTurkishNumbersAndComputesLineTotal() {
        let item = row(qty: "3", price: "1.250,50", discount: "10")
        XCTAssertEqual(item.quantity, 3)
        XCTAssertEqual(item.unitPrice, 1250.5)
        XCTAssertEqual(item.discountPercent, 10)
        XCTAssertEqual(item.grossTotal, 3751.5)
        XCTAssertEqual(item.lineTotal, 3376.35)
        XCTAssertTrue(item.isValid)
    }

    func testEmptyPriceAndDiscountAreZeroButQuantityIsRequired() {
        XCTAssertTrue(row(qty: "1").isValid)
        XCTAssertEqual(row(qty: "1").unitPrice, 0)
        XCTAssertFalse(row(qty: "").isValid)
        XCTAssertFalse(row(qty: "0").isValid)
        XCTAssertFalse(row(qty: "1,5").isValid)
        XCTAssertFalse(row(qty: "-2").isValid)
    }

    func testDiscountMustBeBetweenZeroAndHundred() {
        XCTAssertTrue(row(discount: "100").isValid)
        XCTAssertTrue(row(discount: "12,5").isValid)
        XCTAssertFalse(row(discount: "100,1").isValid)
        XCTAssertFalse(row(discount: "-5").isValid)
        XCTAssertFalse(row(discount: "abc").isValid)
        XCTAssertFalse(row(price: "abc").isValid)
        XCTAssertEqual(row(qty: "2", price: "abc").lineTotal, 0, "Geçersiz satır 0 sayılır")
    }

    func testBlankRows() {
        XCTAssertTrue(QuoteItemRow().isBlank)
        var typed = QuoteItemRow()
        typed.catalogNumber = "1756-L71"
        XCTAssertFalse(typed.isBlank)
        XCTAssertFalse(row(price: "10").isBlank)
        XCTAssertFalse(row(price: "abc").isBlank, "Geçersiz fiyat boş sayılmaz (kullanıcı düzeltmeli)")
    }
}

final class QuoteNumberingTests: XCTestCase {
    private let cal = TestCalendar.utc

    func testSuggestsTheNextNumberInTheYear() {
        let date = TestCalendar.date(2026, 11, 25)
        XCTAssertEqual(QuoteNumbering.suggest(existing: [], date: date, calendar: cal), "T-2026-001")
        XCTAssertEqual(
            QuoteNumbering.suggest(existing: ["T-2026-003", "T-2026-010", "T-2025-099", "ABC", "T-2026-x", ""], date: date, calendar: cal),
            "T-2026-011"
        )
        XCTAssertEqual(QuoteNumbering.suggest(existing: ["T-2026-005"], date: TestCalendar.date(2027, 1, 2), calendar: cal), "T-2027-001")
    }
}

final class QuoteListingTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 12)

    private func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now))! }

    private func quote(
        _ number: String,
        _ status: QuoteStatus,
        valid: Int? = nil,
        dated: Int = 0
    ) -> Quote {
        Quote(quoteNumber: number, date: days(dated), validUntil: valid.map(days), status: status)
    }

    private func state(_ quote: Quote, warning: Int = 3) -> QuoteExpiryState {
        QuoteListing.expiryState(for: quote, warningDays: warning, now: now, calendar: cal)
    }

    func testExpiryStateForPendingQuotes() {
        XCTAssertEqual(state(quote("A", .sent, valid: 0)), .approaching(daysLeft: 0))
        XCTAssertEqual(state(quote("A", .sent, valid: 3)), .approaching(daysLeft: 3))
        XCTAssertEqual(state(quote("A", .followUp, valid: 4)), .none)
        XCTAssertEqual(state(quote("A", .sent, valid: -1)), .expired(daysAgo: 1))
        XCTAssertEqual(state(quote("A", .sent, valid: -5)), .expired(daysAgo: 5))
        XCTAssertEqual(state(quote("A", .sent, valid: 5), warning: 7), .approaching(daysLeft: 5), "Pencere ayardaki gün sayısıdır")
        XCTAssertEqual(state(quote("A", .sent)), .none, "Geçerlilik tarihi yok")
    }

    func testOnlyPendingQuotesAreFlagged() {
        for status in [QuoteStatus.draft, .won, .lost] {
            XCTAssertEqual(state(quote("A", status, valid: 1)), .none, status.title)
            XCTAssertEqual(state(quote("A", status, valid: -3)), .none, status.title)
        }
    }

    func testApproachingQuotesComeFirstSortedByExpiry() {
        let soon = quote("SOON", .sent, valid: 1, dated: -5)
        let expired = quote("EXPIRED", .followUp, valid: -2, dated: -20)
        let calm = quote("CALM", .sent, valid: 10, dated: -1)
        let older = quote("OLDER", .sent, valid: 30, dated: -8)
        let draft = quote("DRAFT", .draft, valid: 1, dated: 0)
        let won = quote("WON", .won, valid: -9, dated: -30)

        let sections = QuoteListing.make(
            quotes: [calm, draft, soon, won, older, expired], filter: nil, warningDays: 3, now: now, calendar: cal
        )

        XCTAssertEqual(sections.approaching.map(\.quoteNumber), ["EXPIRED", "SOON"], "Süresi dolan önce, sonra bitişi yakın olan")
        XCTAssertEqual(sections.others.map(\.quoteNumber), ["DRAFT", "CALM", "OLDER", "WON"], "Diğerleri teklif tarihine göre yeniden eskiye")
    }

    func testStatusFilter() {
        let quotes = [
            quote("S1", .sent, valid: 1), quote("S2", .sent, valid: 20), quote("F", .followUp), quote("W", .won), quote("L", .lost), quote("D", .draft)
        ]
        func numbers(_ status: QuoteStatus?) -> [String] {
            let sections = QuoteListing.make(quotes: quotes, filter: status, warningDays: 3, now: now, calendar: cal)
            return (sections.approaching + sections.others).map(\.quoteNumber).sorted()
        }
        XCTAssertEqual(numbers(nil), ["D", "F", "L", "S1", "S2", "W"])
        XCTAssertEqual(numbers(.sent), ["S1", "S2"])
        XCTAssertEqual(numbers(.followUp), ["F"])
        XCTAssertEqual(numbers(.won), ["W"])
        XCTAssertEqual(numbers(.lost), ["L"])
        XCTAssertEqual(numbers(.draft), ["D"])
        XCTAssertEqual(QuoteListing.make(quotes: quotes, filter: .sent, warningDays: 3, now: now, calendar: cal).approaching.map(\.quoteNumber), ["S1"])
        XCTAssertTrue(QuoteListing.make(quotes: [], filter: nil, warningDays: 3, now: now, calendar: cal).isEmpty)
    }

    func testCounts() {
        let counts = QuoteListing.counts(of: [quote("1", .sent), quote("2", .sent), quote("3", .won)])
        XCTAssertEqual(counts[.sent], 2)
        XCTAssertEqual(counts[.won], 1)
        XCTAssertNil(counts[.lost])
    }

    func testExpiryTexts() {
        let valid = TestCalendar.date(2026, 11, 28)
        XCTAssertEqual(QuoteListing.expiryText(for: .approaching(daysLeft: 0), validUntil: valid), "Geçerlilik bugün bitiyor")
        XCTAssertEqual(QuoteListing.expiryText(for: .approaching(daysLeft: 1), validUntil: valid), "Geçerlilik yarın bitiyor")
        XCTAssertEqual(QuoteListing.expiryText(for: .approaching(daysLeft: 3), validUntil: valid), "Geçerlilik: 3 gün kaldı")
        XCTAssertEqual(QuoteListing.expiryText(for: .expired(daysAgo: 1), validUntil: valid), "Süresi dün doldu")
        XCTAssertEqual(QuoteListing.expiryText(for: .expired(daysAgo: 4), validUntil: valid), "Süresi 4 gün önce doldu")
        XCTAssertTrue(QuoteListing.expiryText(for: .none, validUntil: valid).hasPrefix("Geçerlilik: 28 Kas"))
        XCTAssertEqual(QuoteListing.expiryText(for: .none, validUntil: nil), "")
    }

    func testQuoteStatusOrderAndPendingFlag() {
        XCTAssertEqual(QuoteStatus.allCases.map(\.title), ["Taslak", "Gönderildi", "Takipte", "Kazanıldı", "Kaybedildi"])
        XCTAssertEqual(QuoteStatus.allCases.filter(\.isPending), [.sent, .followUp])
    }
}

/// Form modeli: kalemler (ekle/sil/sırala), canlı toplamlar, kaydetme.
@MainActor
final class QuoteFormModelTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 12)
    private let rules = QuoteReminderRules(defaultFollowUpDays: [3, 7], expiryEnabled: true, expiryDaysBefore: 3, reminderTime: TimeOfDay(hour: 9))

    private func model(
        _ env: TestEnv,
        currency: Currency = .tl,
        quote: Quote? = nil,
        customer: Customer? = nil,
        opportunity: Opportunity? = nil
    ) -> QuoteFormModel {
        QuoteFormModel(
            repositories: env.repos, reminderRules: rules, defaultCurrency: currency,
            quote: quote, customer: customer, opportunity: opportunity, calendar: cal, now: now
        )
    }

    private func fill(_ model: QuoteFormModel, at index: Int, catalog: String = "", qty: String = "1", price: String = "", discount: String = "") {
        model.items[index].catalogNumber = catalog
        model.items[index].quantityText = qty
        model.items[index].unitPriceText = price
        model.items[index].discountText = discount
    }

    func testNewQuoteDefaults() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try env.repos.quotes.add(Quote(quoteNumber: "T-2026-004"), customer: customer, opportunity: nil)

        let form = model(env, currency: .usd)

        XCTAssertEqual(form.number, "T-2026-005")
        XCTAssertEqual(form.currency, .usd)
        XCTAssertEqual(form.date, now)
        XCTAssertTrue(form.hasValidUntil)
        XCTAssertEqual(form.validUntil, TestCalendar.date(2026, 12, 25, 12), "Bir ay geçerli")
        XCTAssertEqual(form.items.count, 1)
        XCTAssertFalse(form.canSave, "Müşteri seçilmedi")
        form.customer = customer
        XCTAssertTrue(form.canSave)
        form.number = "  "
        XCTAssertFalse(form.canSave)
    }

    func testItemsAreAddedRemovedAndReordered() throws {
        let env = try TestEnv()
        let form = model(env)
        form.addItem()
        form.addItem()
        fill(form, at: 0, catalog: "A")
        fill(form, at: 1, catalog: "B")
        fill(form, at: 2, catalog: "C")
        let ids = form.items.map(\.id)

        XCTAssertFalse(form.canMove(ids[0], by: -1), "İlk kalem yukarı taşınamaz")
        XCTAssertTrue(form.canMove(ids[0], by: 1))
        XCTAssertFalse(form.canMove(ids[2], by: 1))

        form.moveItem(ids[0], by: 1)
        XCTAssertEqual(form.items.map(\.catalogNumber), ["B", "A", "C"])
        form.moveItem(ids[2], by: -1)
        XCTAssertEqual(form.items.map(\.catalogNumber), ["B", "C", "A"])
        form.moveItem(ids[2], by: -5)
        XCTAssertEqual(form.items.map(\.catalogNumber), ["B", "C", "A"], "Sınır dışına taşıma yok sayılır")

        form.removeItem(ids[1])
        XCTAssertEqual(form.items.map(\.catalogNumber), ["C", "A"])
    }

    func testLiveTotals() throws {
        let env = try TestEnv()
        let form = model(env)
        form.addItem()
        form.addItem()
        fill(form, at: 0, catalog: "A", qty: "2", price: "142.500", discount: "5")
        fill(form, at: 1, catalog: "B", qty: "4", price: "21.200", discount: "10")
        form.addItem()
        fill(form, at: 2, catalog: "C", qty: "1", price: "18.750,50")

        XCTAssertEqual(form.items[0].lineTotal, 270_750)
        XCTAssertEqual(form.items[1].lineTotal, 76_320)
        XCTAssertEqual(form.subtotal, 285_000 + 84_800 + 18_750.5)
        XCTAssertEqual(form.total, 270_750 + 76_320 + 18_750.5)
        XCTAssertEqual(form.discountTotal, 14_250 + 8_480)
    }

    func testInvalidRowBlocksSaving() throws {
        let env = try TestEnv()
        let form = model(env, customer: try env.makeCustomer())
        fill(form, at: 0, catalog: "A", qty: "0", price: "10")
        XCTAssertFalse(form.itemsAreValid)
        XCTAssertFalse(form.canSave)
        fill(form, at: 0, catalog: "A", qty: "2", price: "10")
        XCTAssertTrue(form.canSave)
    }

    func testSaveCreatesDraftQuoteWithOrderedItemsAndSkipsBlankRows() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let form = model(env, currency: .eur, customer: customer)
        form.addItem()
        form.addItem()
        fill(form, at: 0, catalog: "1756-L71", qty: "2", price: "142.500", discount: "5")
        // 2. satır boş bırakıldı
        fill(form, at: 2, catalog: "1756-IB16", qty: "4", price: "18.750")
        form.items[0].itemDescription = "İşlemci"
        form.notes = "  Not  "

        XCTAssertTrue(form.save())

        let quote = try XCTUnwrap(form.savedQuote)
        XCTAssertEqual(quote.status, .draft)
        XCTAssertEqual(quote.currency, .eur)
        XCTAssertEqual(quote.quoteNumber, "T-2026-001")
        XCTAssertEqual(quote.notes, "Not")
        XCTAssertEqual(quote.customer?.id, customer.id)
        XCTAssertNil(quote.sentAt)
        XCTAssertEqual(quote.sortedItems.map(\.catalogNumber), ["1756-L71", "1756-IB16"])
        XCTAssertEqual(quote.sortedItems.map(\.position), [0, 1])
        XCTAssertEqual(quote.totalAmount, 270_750 + 75_000)
        XCTAssertEqual(quote.validUntil, TestCalendar.date(2026, 12, 25, 0), "Gün başına yuvarlanır")
    }

    func testEditingUpdatesDeletesAndReordersItems() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let first = model(env, customer: customer)
        first.addItem()
        first.addItem()
        fill(first, at: 0, catalog: "A", price: "100")
        fill(first, at: 1, catalog: "B", price: "200")
        fill(first, at: 2, catalog: "C", price: "300")
        XCTAssertTrue(first.save())
        let quote = try XCTUnwrap(first.savedQuote)
        let originalIDs = quote.sortedItems.map(\.id)

        let editing = model(env, quote: quote)
        XCTAssertEqual(editing.items.map(\.catalogNumber), ["A", "B", "C"])
        XCTAssertEqual(editing.items.map(\.id), originalIDs, "Satır kimliği kalem kimliğidir")
        editing.removeItem(originalIDs[1])
        editing.moveItem(originalIDs[2], by: -1)
        editing.items[0].unitPriceText = "350"
        editing.addItem()
        fill(editing, at: 2, catalog: "D", price: "50")
        XCTAssertTrue(editing.save())

        XCTAssertEqual(quote.sortedItems.map(\.catalogNumber), ["C", "A", "D"])
        XCTAssertEqual(Array(quote.sortedItems.map(\.id).prefix(2)), [originalIDs[2], originalIDs[0]], "Mevcut kalemler yerinde güncellenir")
        XCTAssertEqual(quote.sortedItems[0].unitPrice, 350)
        XCTAssertEqual(try env.repos.quoteItems.items(for: quote).count, 3)
        XCTAssertEqual(try env.repos.quotes.fetchAll().count, 1)
    }

    func testOpportunityChoice() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let other = try env.makeCustomer("Başka")
        let open = Opportunity(title: "Açık", stage: .quoted)
        let won = Opportunity(title: "Kazanılan", stage: .won)
        let foreign = Opportunity(title: "Başkasının", stage: .lead)
        try env.repos.opportunities.add(open, customer: customer)
        try env.repos.opportunities.add(won, customer: customer)
        try env.repos.opportunities.add(foreign, customer: other)

        let form = model(env, customer: customer)
        XCTAssertEqual(form.availableOpportunities.map(\.title), ["Açık"])
        form.opportunityID = open.id
        XCTAssertTrue(form.save())
        XCTAssertEqual(form.savedQuote?.opportunity?.id, open.id)
        XCTAssertEqual(open.quotes?.count, 1)

        form.customer = other
        form.customerChanged()
        XCTAssertNil(form.opportunityID)
    }

    func testFormFromOpportunityPreselectsCustomerAndOpportunity() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: "Hat 3", stage: .quoted)
        try env.repos.opportunities.add(opportunity, customer: customer)

        let form = model(env, opportunity: opportunity)

        XCTAssertEqual(form.customer?.id, customer.id)
        XCTAssertEqual(form.opportunityID, opportunity.id)
        XCTAssertTrue(form.canSave)
    }

    func testEditingKeepsAClosedLinkedOpportunityAvailable() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let won = Opportunity(title: "Kazanılan", stage: .won)
        try env.repos.opportunities.add(won, customer: customer)
        let quote = Quote(quoteNumber: "T-1")
        try env.repos.quotes.add(quote, customer: customer, opportunity: won)

        let form = model(env, quote: quote)

        XCTAssertEqual(form.opportunityID, won.id)
        XCTAssertEqual(form.availableOpportunities.map(\.title), ["Kazanılan"])
    }
}

/// Teklif no çakışma uyarısı: aynı numara başka tekliftedir → uyarı; kaydetmeyi engellemez.
@MainActor
final class QuoteNumberWarningTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 12)
    private let rules = QuoteReminderRules(defaultFollowUpDays: [3, 7], expiryEnabled: true, expiryDaysBefore: 3, reminderTime: TimeOfDay(hour: 9))

    private func form(_ env: TestEnv, quote: Quote? = nil, customer: Customer? = nil) -> QuoteFormModel {
        QuoteFormModel(
            repositories: env.repos, reminderRules: rules, defaultCurrency: .tl,
            quote: quote, customer: customer, calendar: cal, now: now
        )
    }

    func testWarnsWhenAnotherQuoteHasTheSameNumberButStillSaves() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try env.repos.quotes.add(Quote(quoteNumber: "T-2026-004"), customer: customer, opportunity: nil)

        let model = form(env, customer: customer)
        XCTAssertNil(model.duplicateNumberQuote, "Öneri (T-2026-005) çakışmaz")

        model.number = "t-2026-004 "
        XCTAssertEqual(model.duplicateNumberQuote?.quoteNumber, "T-2026-004", "Büyük/küçük harf ve boşluk yok sayılır")
        XCTAssertTrue(model.canSave, "Uyarı kaydetmeyi engellemez")
        XCTAssertTrue(model.save())

        model.number = ""
        XCTAssertNil(model.duplicateNumberQuote)
    }

    func testEditingAQuoteDoesNotWarnAboutItself() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-2026-004")
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
        try env.repos.quotes.add(Quote(quoteNumber: "T-2026-005"), customer: customer, opportunity: nil)

        let model = form(env, quote: quote)
        XCTAssertNil(model.duplicateNumberQuote)
        model.number = "T-2026-005"
        XCTAssertNotNil(model.duplicateNumberQuote)
    }
}
