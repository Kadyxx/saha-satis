import Combine
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

    func testEmptyCityListIsAChoiceAndStaysEmpty() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.responsibleCities = []
        XCTAssertTrue(settings.responsibleCities.isEmpty)
        XCTAssertTrue(AppSettings(defaults: defaults).responsibleCities.isEmpty, "Boş liste boş olarak saklanır")
    }

    func testReminderDefaultsMatchSpec() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.fullName, "")
        XCTAssertEqual(settings.jobTitle, "")
        XCTAssertEqual(settings.defaultReminderTime, TimeOfDay(hour: 9))
        XCTAssertTrue(settings.morningSummaryEnabled)
        XCTAssertEqual(settings.morningSummaryTime, TimeOfDay(hour: 8))
        XCTAssertTrue(settings.endOfDayReminderEnabled)
        XCTAssertEqual(settings.endOfDayReminderTime, TimeOfDay(hour: 18))
        XCTAssertFalse(settings.weekendNotificationsEnabled)
        XCTAssertEqual(settings.visitFrequencyImportantDays, 30)
        XCTAssertEqual(settings.visitFrequencyPromisingDays, 60)
        XCTAssertEqual(settings.visitFrequencyWeakDays, 120)
        XCTAssertEqual(settings.quoteFollowUpDays, [3, 7])
        XCTAssertTrue(settings.quoteExpiryWarningEnabled)
        XCTAssertEqual(settings.quoteExpiryWarningDays, 3)
        XCTAssertEqual(settings.crmEmail, "")
    }

    func testAllSettingsPersistAndReload() {
        let defaults = makeDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.fullName = "Ayşe Yılmaz"
        settings.jobTitle = "Satış Mühendisi"
        settings.defaultReminderTime = TimeOfDay(hour: 10, minute: 30)
        settings.morningSummaryEnabled = false
        settings.morningSummaryTime = TimeOfDay(hour: 7, minute: 45)
        settings.endOfDayReminderEnabled = false
        settings.endOfDayReminderTime = TimeOfDay(hour: 17, minute: 15)
        settings.weekendNotificationsEnabled = true
        settings.visitFrequencyImportantDays = 15
        settings.visitFrequencyPromisingDays = 45
        settings.visitFrequencyWeakDays = 90
        settings.quoteFollowUpDays = [2, 5, 10]
        settings.quoteExpiryWarningEnabled = false
        settings.quoteExpiryWarningDays = 5
        settings.crmEmail = "crm@example.com"

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.fullName, "Ayşe Yılmaz")
        XCTAssertEqual(reloaded.jobTitle, "Satış Mühendisi")
        XCTAssertEqual(reloaded.defaultReminderTime, TimeOfDay(hour: 10, minute: 30))
        XCTAssertFalse(reloaded.morningSummaryEnabled)
        XCTAssertEqual(reloaded.morningSummaryTime, TimeOfDay(hour: 7, minute: 45))
        XCTAssertFalse(reloaded.endOfDayReminderEnabled)
        XCTAssertEqual(reloaded.endOfDayReminderTime, TimeOfDay(hour: 17, minute: 15))
        XCTAssertTrue(reloaded.weekendNotificationsEnabled)
        XCTAssertEqual(reloaded.visitFrequencyImportantDays, 15)
        XCTAssertEqual(reloaded.visitFrequencyPromisingDays, 45)
        XCTAssertEqual(reloaded.visitFrequencyWeakDays, 90)
        XCTAssertEqual(reloaded.quoteFollowUpDays, [2, 5, 10])
        XCTAssertFalse(reloaded.quoteExpiryWarningEnabled)
        XCTAssertEqual(reloaded.quoteExpiryWarningDays, 5)
        XCTAssertEqual(reloaded.crmEmail, "crm@example.com")
    }

    func testSettingsPublishChanges() {
        let settings = AppSettings(defaults: makeDefaults())
        var changeCount = 0
        let cancellable = settings.objectWillChange.sink { changeCount += 1 }
        settings.fullName = "Yeni"
        settings.responsibleCities.append("Konya")
        XCTAssertEqual(changeCount, 2)
        cancellable.cancel()
    }
}

final class SettingsHelpersTests: XCTestCase {
    func testTimeOfDayClampsAndConverts() {
        XCTAssertEqual(TimeOfDay(minutes: 9 * 60 + 5), TimeOfDay(hour: 9, minute: 5))
        XCTAssertEqual(TimeOfDay(minutes: -5), TimeOfDay(hour: 0, minute: 0))
        XCTAssertEqual(TimeOfDay(minutes: 99_999), TimeOfDay(hour: 23, minute: 59))
        XCTAssertEqual(TimeOfDay(hour: 18, minute: 30).minutesSinceMidnight, 1110)
    }

    func testTimeOfDayDateRoundTrip() {
        let calendar = TestCalendar.utc
        let time = TimeOfDay(hour: 8, minute: 15)
        let date = time.date(on: TestCalendar.date(2026, 11, 24), calendar: calendar)
        XCTAssertEqual(TimeOfDay(date: date, calendar: calendar), time)
    }

    func testDayListParsing() {
        XCTAssertEqual(DayListFormat.parse("3, 7"), [3, 7])
        XCTAssertEqual(DayListFormat.parse("10 2 5"), [2, 5, 10])
        XCTAssertEqual(DayListFormat.parse("7,7,3,0,999,abc"), [3, 7])
        XCTAssertEqual(DayListFormat.parse(""), [])
        XCTAssertEqual(DayListFormat.format([3, 7, 14]), "3, 7, 14")
    }

    func testTurkishDateAndTitles() {
        let utc = TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(AppFormat.date(TestCalendar.date(2026, 11, 21), timeZone: utc), "21 Kas 2026")
        XCTAssertEqual(CustomerStatus.current.title, "Mevcut")
        XCTAssertEqual(CustomerStatus.potential.title, "Aday")
        XCTAssertEqual(CustomerStatus.passive.title, "Pasif")
        XCTAssertEqual(CustomerRating.promising.title, "Potansiyelli", "Değerlendirme rozeti aynı kalır")
    }

    func testTurkishUppercaseUsesDottedI() {
        XCTAssertEqual("Kişiler".uppercased(with: AppFormat.locale), "KİŞİLER")
        XCTAssertEqual("Değerlendirme".uppercased(with: AppFormat.locale), "DEĞERLENDİRME")
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
