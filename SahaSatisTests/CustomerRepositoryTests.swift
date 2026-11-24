import XCTest
@testable import SahaSatis

@MainActor
final class CustomerRepositoryTests: XCTestCase {
    func testAddAndFetchById() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Örnek Makina A.Ş.")

        let found = try env.repos.customers.customer(id: customer.id)
        XCTAssertEqual(found?.name, "Örnek Makina A.Ş.")
        XCTAssertEqual(found?.ownerUserID, "test-user", "ownerUserID boşsa repository damgalar")
        XCTAssertNil(try env.repos.customers.customer(id: UUID()))
    }

    func testDefaultsAndEnumRawStorage() throws {
        let env = try TestEnv()
        let customer = Customer(name: "Yeni")
        try env.repos.customers.add(customer)

        XCTAssertEqual(customer.status, .potential)
        XCTAssertEqual(customer.rating, .promising)
        customer.status = .passive
        customer.rating = .weak
        XCTAssertEqual(customer.statusRaw, "passive")
        XCTAssertEqual(customer.ratingRaw, "weak")
        XCTAssertNil(customer.latitude)
        XCTAssertNil(customer.lastVisitDate)
    }

    func testUpdateTouchesUpdatedAt() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let before = customer.updatedAt

        customer.notes = "Not"
        try env.repos.customers.update(customer)

        XCTAssertGreaterThanOrEqual(customer.updatedAt, before)
        XCTAssertEqual(try env.repos.customers.customer(id: customer.id)?.notes, "Not")
    }

    func testFilterByCityStatusRating() throws {
        let env = try TestEnv()
        try env.makeCustomer("A", city: "Bursa", status: .current, rating: .important)
        try env.makeCustomer("B", city: "Bursa", status: .potential, rating: .weak)
        try env.makeCustomer("C", city: "Yalova", status: .potential, rating: .promising)

        let repo = env.repos.customers
        XCTAssertEqual(try repo.search(CustomerFilter(city: "Bursa")).count, 2)
        XCTAssertEqual(try repo.search(CustomerFilter(status: .potential)).count, 2)
        XCTAssertEqual(try repo.search(CustomerFilter(rating: .promising)).map(\.name), ["C"])
        XCTAssertEqual(try repo.search(CustomerFilter(city: "Bursa", status: .potential)).map(\.name), ["B"])
        XCTAssertEqual(try repo.fetchAll().count, 3)
    }

    func testSearchMatchesNameAndCityIgnoringCase() throws {
        let env = try TestEnv()
        try env.makeCustomer("Örnek Makina A.Ş.", city: "Bursa")
        try env.makeCustomer("Başka Firma", city: "Yalova")

        let repo = env.repos.customers
        XCTAssertEqual(try repo.search(CustomerFilter(searchText: "ÖRNEK")).map(\.name), ["Örnek Makina A.Ş."])
        XCTAssertEqual(try repo.search(CustomerFilter(searchText: "yalova")).map(\.name), ["Başka Firma"])
        XCTAssertTrue(try repo.search(CustomerFilter(searchText: "olmayan")).isEmpty)
    }

    func testSortByLastVisit() throws {
        let env = try TestEnv()
        let old = try env.makeCustomer("Eski")
        let recent = try env.makeCustomer("Yeni")
        let never = try env.makeCustomer("Hiç")

        try env.repos.visits.add(Visit(date: TestCalendar.date(2026, 1, 10)), customer: old, contacts: [], opportunity: nil)
        try env.repos.visits.add(Visit(date: TestCalendar.date(2026, 3, 10)), customer: recent, contacts: [], opportunity: nil)

        let newestFirst = try env.repos.customers.search(CustomerFilter(sort: .lastVisitNewestFirst))
        XCTAssertEqual(newestFirst.map(\.name), ["Yeni", "Eski", "Hiç"])

        let oldestFirst = try env.repos.customers.search(CustomerFilter(sort: .lastVisitOldestFirst))
        XCTAssertEqual(oldestFirst.map(\.name), ["Hiç", "Eski", "Yeni"])
        XCTAssertNotNil(never)
    }

    func testDeleteCascadesToChildren() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try env.repos.contacts.add(Contact(fullName: "Ahmet Yılmaz"), to: customer)
        try env.repos.visits.add(Visit(), customer: customer, contacts: [], opportunity: nil)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "1756-L71"), to: customer)
        try env.repos.tasks.add(FollowUpTask(title: "Ara"), customer: customer, quote: nil, visit: nil)
        try env.repos.opportunities.add(Opportunity(title: "Hat 3"), customer: customer)
        try env.repos.quotes.add(Quote(quoteNumber: "T-1"), customer: customer, opportunity: nil)

        try env.repos.customers.delete(customer)

        XCTAssertTrue(try env.repos.customers.fetchAll().isEmpty)
        XCTAssertTrue(try env.context.fetchAll(Contact.self).isEmpty)
        XCTAssertTrue(try env.repos.visits.fetchAll().isEmpty)
        XCTAssertTrue(try env.context.fetchAll(InstalledProduct.self).isEmpty)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
        XCTAssertTrue(try env.repos.opportunities.fetchAll().isEmpty)
        XCTAssertTrue(try env.repos.quotes.fetchAll().isEmpty)
    }

    func testMigrationOpportunityFlag() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        XCTAssertFalse(customer.hasMigrationOpportunity)

        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "1756-L71", lifecycleStatus: .active), to: customer)
        XCTAssertFalse(customer.hasMigrationOpportunity)

        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "PLC-5", lifecycleStatus: .discontinued), to: customer)
        XCTAssertTrue(customer.hasMigrationOpportunity)
    }
}
