import XCTest
@testable import SahaSatis

final class ContactLinkTests: XCTestCase {
    func testDialURLKeepsDigitsAndLeadingPlus() {
        XCTAssertEqual(ContactLink.dialURL("0555 123 45 67")?.absoluteString, "tel:05551234567")
        XCTAssertEqual(ContactLink.dialURL("+90 (555) 123 45 67")?.absoluteString, "tel:+905551234567")
        XCTAssertNil(ContactLink.dialURL(""))
        XCTAssertNil(ContactLink.dialURL("yok"))
    }

    func testInternationalNumberAssumesTurkey() {
        XCTAssertEqual(ContactLink.internationalNumber("0555 123 45 67"), "905551234567")
        XCTAssertEqual(ContactLink.internationalNumber("5551234567"), "905551234567")
        XCTAssertEqual(ContactLink.internationalNumber("+90 555 123 45 67"), "905551234567")
        XCTAssertEqual(ContactLink.internationalNumber("0090 555 123 45 67"), "905551234567")
        XCTAssertEqual(ContactLink.internationalNumber("+49 170 1234567"), "491701234567")
        XCTAssertNil(ContactLink.internationalNumber("  "))
    }

    func testWhatsAppAndMailURLs() {
        XCTAssertEqual(ContactLink.whatsAppURL("0555 123 45 67")?.absoluteString, "https://wa.me/905551234567")
        XCTAssertNil(ContactLink.whatsAppURL(""))
        XCTAssertEqual(ContactLink.mailURL(" ahmet@example.com ")?.absoluteString, "mailto:ahmet@example.com")
        XCTAssertNil(ContactLink.mailURL("gecersiz"))
        XCTAssertNil(ContactLink.mailURL(""))
    }
}

final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultCitiesMatchSpec() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.responsibleCities, [
            "Çanakkale", "Balıkesir", "Bursa", "Bilecik",
            "Yalova", "Eskişehir", "Kütahya", "Afyonkarahisar"
        ])
    }

    func testCitiesAreChangeableAndPersisted() {
        let defaults = makeDefaults()
        AppSettings(defaults: defaults).responsibleCities = ["Ankara", "Konya"]
        XCTAssertEqual(AppSettings(defaults: defaults).responsibleCities, ["Ankara", "Konya"])
    }

    func testEmptyStoredListFallsBackToDefaults() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.responsibleCities = []
        XCTAssertEqual(settings.responsibleCities, AppSettings.defaultCities)
    }
}

@MainActor
final class CustomerListModelTests: XCTestCase {
    func testReloadAppliesFilterAndSort() throws {
        let env = try TestEnv()
        try env.makeCustomer("Bursa Önemli", city: "Bursa", status: .current, rating: .important)
        try env.makeCustomer("Bursa Zayıf", city: "Bursa", status: .potential, rating: .weak)
        try env.makeCustomer("Yalova Zayıf", city: "Yalova", status: .potential, rating: .weak)

        let model = CustomerListModel(repository: env.repos.customers)
        model.reload()
        XCTAssertEqual(model.customers.count, 3)
        XCTAssertFalse(model.hasActiveFilter)

        model.filter.city = "Bursa"
        model.filter.rating = .weak
        model.reload()
        XCTAssertEqual(model.customers.map(\.name), ["Bursa Zayıf"])
        XCTAssertTrue(model.hasActiveFilter)

        model.filter = CustomerFilter(searchText: "yalova")
        model.reload()
        XCTAssertEqual(model.customers.map(\.name), ["Yalova Zayıf"])
    }

    func testCityOptionsIncludeRegionThenExtraCities() throws {
        let env = try TestEnv()
        try env.makeCustomer("A", city: "Bursa")
        try env.makeCustomer("B", city: "Ankara")

        let model = CustomerListModel(repository: env.repos.customers)
        let options = model.cityOptions(regionCities: ["Bursa", "Yalova"])
        XCTAssertEqual(options, ["Bursa", "Yalova", "Ankara"])
    }
}

final class CustomerDraftTests: XCTestCase {
    func testDraftRoundTripAndTrimming() {
        let customer = Customer(name: "Örnek", city: "Bursa", district: "Nilüfer", status: .current, rating: .weak, ratingNote: "not")
        var draft = CustomerDraft(customer: customer)
        XCTAssertEqual(draft.city, "Bursa")
        XCTAssertEqual(draft.rating, .weak)

        draft.name = "  Yeni Ad  "
        draft.rating = .important
        draft.apply(to: customer)

        XCTAssertEqual(customer.name, "Yeni Ad")
        XCTAssertEqual(customer.rating, .important)
        XCTAssertEqual(customer.district, "Nilüfer")
        XCTAssertTrue(CustomerDraft().trimmedName.isEmpty)
    }

    func testLocationText() {
        XCTAssertEqual(Customer(name: "A", city: "Bursa", district: "Nilüfer").locationText, "Bursa / Nilüfer")
        XCTAssertEqual(Customer(name: "A", city: "Bursa").locationText, "Bursa")
        XCTAssertEqual(Customer(name: "A").locationText, "")
    }
}

#if DEBUG
@MainActor
final class SampleDataTests: XCTestCase {
    func testSampleDataCoversCitiesRatingsAndMigrationTag() throws {
        let env = try TestEnv()
        try SampleData.load(into: env.repos)

        let customers = try env.repos.customers.fetchAll()
        XCTAssertEqual(customers.count, 6)
        XCTAssertGreaterThanOrEqual(Set(customers.map(\.city)).count, 5)
        XCTAssertEqual(Set(customers.map(\.rating)), Set(CustomerRating.allCases))
        XCTAssertEqual(Set(customers.map(\.status)), Set(CustomerStatus.allCases))

        let showcase = try XCTUnwrap(customers.first { $0.name == SampleData.showcaseName })
        XCTAssertTrue(showcase.hasMigrationOpportunity)
        XCTAssertEqual(try env.repos.contacts.contacts(for: showcase).count, 2)
    }
}
#endif
