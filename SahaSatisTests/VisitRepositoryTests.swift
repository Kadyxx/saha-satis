import XCTest
@testable import SahaSatis

@MainActor
final class VisitRepositoryTests: XCTestCase {
    func testAddLinksCustomerContactsAndOpportunity() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet Yılmaz")
        try env.repos.contacts.add(contact, to: customer)
        let opportunity = Opportunity(title: "Hat 3 PLC yenileme")
        try env.repos.opportunities.add(opportunity, customer: customer)

        let visit = Visit(
            date: TestCalendar.date(2026, 11, 24),
            type: .visit,
            transcript: "ham metin",
            summary: "özet",
            topics: ["PLC", "Hat 3"],
            nextStep: "Teklif hazırlanacak",
            nextStepDate: TestCalendar.date(2026, 11, 28)
        )
        try env.repos.visits.add(visit, customer: customer, contacts: [contact], opportunity: opportunity)

        let stored = try XCTUnwrap(try env.repos.visits.visit(id: visit.id))
        XCTAssertEqual(stored.customer?.id, customer.id)
        XCTAssertEqual(stored.contacts?.map(\.id), [contact.id])
        XCTAssertEqual(stored.opportunity?.id, opportunity.id)
        XCTAssertEqual(stored.topics, ["PLC", "Hat 3"])
        XCTAssertEqual(stored.transcript, "ham metin")
        XCTAssertEqual(stored.ownerUserID, "test-user")
        XCTAssertEqual(customer.lastVisitDate, TestCalendar.date(2026, 11, 24))
    }

    func testVisitsForCustomerNewestFirst() throws {
        let env = try TestEnv()
        let a = try env.makeCustomer("A")
        let b = try env.makeCustomer("B")
        try env.repos.visits.add(Visit(date: TestCalendar.date(2026, 1, 1), summary: "eski"), customer: a, contacts: [], opportunity: nil)
        try env.repos.visits.add(Visit(date: TestCalendar.date(2026, 2, 1), summary: "yeni"), customer: a, contacts: [], opportunity: nil)
        try env.repos.visits.add(Visit(date: TestCalendar.date(2026, 3, 1), summary: "b"), customer: b, contacts: [], opportunity: nil)

        XCTAssertEqual(try env.repos.visits.visits(for: a).map(\.summary), ["yeni", "eski"])
        XCTAssertEqual(try env.repos.visits.fetchAll().count, 3)
    }

    func testVisitsOnDayAndUnexported() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let day = TestCalendar.date(2026, 11, 24, 10)
        let morning = Visit(date: day, summary: "sabah")
        let evening = Visit(date: TestCalendar.date(2026, 11, 24, 18), summary: "akşam")
        let otherDay = Visit(date: TestCalendar.date(2026, 11, 25, 10), summary: "ertesi gün")
        for visit in [morning, evening, otherDay] {
            try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)
        }

        let cal = TestCalendar.utc
        XCTAssertEqual(try env.repos.visits.visits(on: day, calendar: cal).count, 2)

        try env.repos.visits.markExported([morning], at: TestCalendar.date(2026, 11, 24, 19))
        XCTAssertTrue(morning.exportedToCRM)
        XCTAssertEqual(morning.exportedAt, TestCalendar.date(2026, 11, 24, 19))
        XCTAssertEqual(try env.repos.visits.unexportedVisits(on: day, calendar: cal).map(\.summary), ["akşam"])
    }

    func testUpdateAndDelete() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let visit = Visit(summary: "ilk")
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)

        visit.summary = "düzenlendi"
        try env.repos.visits.update(visit)
        XCTAssertEqual(try env.repos.visits.visit(id: visit.id)?.summary, "düzenlendi")

        try env.repos.visits.delete(visit)
        XCTAssertNil(try env.repos.visits.visit(id: visit.id))
        XCTAssertNotNil(try env.repos.customers.customer(id: customer.id))
    }

    func testDeletingContactKeepsVisit() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet Yılmaz")
        try env.repos.contacts.add(contact, to: customer)
        let visit = Visit(summary: "görüşme")
        try env.repos.visits.add(visit, customer: customer, contacts: [contact], opportunity: nil)

        try env.repos.contacts.delete(contact)

        XCTAssertNotNil(try env.repos.visits.visit(id: visit.id))
    }
}
