import XCTest
@testable import SahaSatis

@MainActor
final class OpportunityRepositoryTests: XCTestCase {
    func testAddFetchAndStageFilter() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let a = Opportunity(title: "A", estimatedValue: 1000, currency: .usd, stage: .lead)
        let b = Opportunity(title: "B", stage: .quoted)
        try env.repos.opportunities.add(a, customer: customer)
        try env.repos.opportunities.add(b, customer: customer)

        XCTAssertEqual(try env.repos.opportunities.opportunities(for: customer).count, 2)
        XCTAssertEqual(try env.repos.opportunities.opportunities(in: .quoted).map(\.title), ["B"])
        XCTAssertEqual(a.currency, .usd)
        XCTAssertEqual(a.currencyRaw, "USD")
        XCTAssertEqual(a.ownerUserID, "test-user")
    }

    func testSetStageLostStoresReasonAndClearsOtherwise() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: "Hat 3")
        try env.repos.opportunities.add(opportunity, customer: customer)

        try env.repos.opportunities.setStage(opportunity, to: .lost, lostReason: "Fiyat")
        XCTAssertEqual(opportunity.stage, .lost)
        XCTAssertEqual(opportunity.lostReason, "Fiyat")
        XCTAssertFalse(opportunity.stage.isOpen)

        try env.repos.opportunities.setStage(opportunity, to: .negotiation, lostReason: nil)
        XCTAssertEqual(opportunity.stage, .negotiation)
        XCTAssertEqual(opportunity.lostReason, "")
        XCTAssertTrue(opportunity.stage.isOpen)
    }

    func testDeleteOpportunityKeepsQuotesAndVisits() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: "Hat 3")
        try env.repos.opportunities.add(opportunity, customer: customer)
        let quote = Quote(quoteNumber: "T-1")
        try env.repos.quotes.add(quote, customer: customer, opportunity: opportunity)
        let visit = Visit()
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: opportunity)

        try env.repos.opportunities.delete(opportunity)

        XCTAssertNotNil(try env.repos.quotes.quote(id: quote.id))
        XCTAssertNil(try env.repos.quotes.quote(id: quote.id)?.opportunity)
        XCTAssertNotNil(try env.repos.visits.visit(id: visit.id))
    }
}

@MainActor
final class QuoteRepositoryTests: XCTestCase {
    func testAddAndQueries() throws {
        let env = try TestEnv()
        let a = try env.makeCustomer("A")
        let b = try env.makeCustomer("B")
        let q1 = Quote(quoteNumber: "T-1", date: TestCalendar.date(2026, 1, 1), status: .sent)
        let q2 = Quote(quoteNumber: "T-2", date: TestCalendar.date(2026, 2, 1), status: .draft)
        let q3 = Quote(quoteNumber: "T-3", date: TestCalendar.date(2026, 3, 1), status: .sent)
        try env.repos.quotes.add(q1, customer: a, opportunity: nil)
        try env.repos.quotes.add(q2, customer: a, opportunity: nil)
        try env.repos.quotes.add(q3, customer: b, opportunity: nil)

        XCTAssertEqual(try env.repos.quotes.quotes(for: a).map(\.quoteNumber), ["T-2", "T-1"])
        XCTAssertEqual(try env.repos.quotes.quotes(with: .sent).map(\.quoteNumber), ["T-3", "T-1"])
        XCTAssertEqual(try env.repos.quotes.fetchAll().count, 3)
    }

    func testSetStatus() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-1")
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)

        try env.repos.quotes.setStatus(quote, to: .won)

        XCTAssertEqual(quote.status, .won)
        XCTAssertEqual(quote.statusRaw, "won")
        XCTAssertTrue(quote.status.isClosed)
    }

    func testFollowUpDaysFallBackToDefaults() {
        let quote = Quote()
        XCTAssertEqual(quote.effectiveFollowUpDays(defaultDays: [3, 7]), [3, 7])
        quote.followUpDays = [2, 5, 10]
        XCTAssertEqual(quote.effectiveFollowUpDays(defaultDays: [3, 7]), [2, 5, 10])
    }

    func testDeleteQuoteCascadesItemsAndTasks() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-1")
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
        try env.repos.quoteItems.add(QuoteItem(catalogNumber: "1756-L71", quantity: 1, unitPrice: 100), to: quote)
        try env.repos.tasks.add(FollowUpTask(title: "takip"), customer: customer, quote: quote, visit: nil)

        try env.repos.quotes.delete(quote)

        XCTAssertTrue(try env.context.fetchAll(QuoteItem.self).isEmpty)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
        XCTAssertNotNil(try env.repos.customers.customer(id: customer.id))
    }
}

@MainActor
final class QuoteItemRepositoryTests: XCTestCase {
    func testLineTotalAppliesQuantityAndDiscount() {
        let item = QuoteItem(quantity: 4, unitPrice: 250, discountPercent: 10)
        XCTAssertEqual(item.lineTotal, 900, accuracy: 0.0001)
        XCTAssertEqual(QuoteItem(quantity: 2, unitPrice: 100).lineTotal, 200, accuracy: 0.0001)
    }

    func testQuoteTotalIsSumOfItems() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-1", currency: .eur)
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
        XCTAssertEqual(quote.totalAmount, 0, accuracy: 0.0001)

        try env.repos.quoteItems.add(QuoteItem(catalogNumber: "A", quantity: 2, unitPrice: 100), to: quote)
        try env.repos.quoteItems.add(QuoteItem(catalogNumber: "B", quantity: 1, unitPrice: 500, discountPercent: 20), to: quote)

        XCTAssertEqual(quote.totalAmount, 600, accuracy: 0.0001)
        XCTAssertEqual(quote.currency, .eur)
        XCTAssertEqual(try env.repos.quoteItems.items(for: quote).map(\.catalogNumber), ["A", "B"])
    }

    func testUpdateAndDeleteItemChangeTotal() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-1")
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
        let item = QuoteItem(catalogNumber: "A", quantity: 1, unitPrice: 100)
        try env.repos.quoteItems.add(item, to: quote)

        item.quantity = 3
        try env.repos.quoteItems.update(item)
        XCTAssertEqual(quote.totalAmount, 300, accuracy: 0.0001)

        try env.repos.quoteItems.delete(item)
        XCTAssertEqual(quote.totalAmount, 0, accuracy: 0.0001)
        XCTAssertNil(try env.repos.quoteItems.item(id: item.id))
    }
}
