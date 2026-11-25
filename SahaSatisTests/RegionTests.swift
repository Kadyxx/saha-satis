import XCTest
@testable import SahaSatis

/// Gömülü ilçe listeleri, ilçe adı eşleştirme ve mevcut kayıtların göçü.
@MainActor
final class DistrictCatalogTests: XCTestCase {
    func testCatalogHasOfficialDistrictCountsForEveryDefaultCity() {
        let expected: [String: Int] = [
            "Çanakkale": 12, "Balıkesir": 20, "Bursa": 17, "Bilecik": 8,
            "Yalova": 6, "Eskişehir": 14, "Kütahya": 13, "Afyonkarahisar": 18
        ]
        XCTAssertEqual(Set(AppSettings.defaultCities), Set(expected.keys))
        for (city, count) in expected {
            let list = DistrictCatalog.districts(forCity: city)
            XCTAssertEqual(list?.count, count, city)
            XCTAssertEqual(Set(list ?? []).count, count, "\(city): tekrar eden ilçe yok")
        }
    }

    func testMetropolitanCitiesListTheirCentralDistrictsByName() {
        XCTAssertTrue(DistrictCatalog.districts(forCity: "Bursa")!.contains("Osmangazi"))
        XCTAssertFalse(DistrictCatalog.districts(forCity: "Bursa")!.contains("Merkez"))
        XCTAssertTrue(DistrictCatalog.districts(forCity: "Balıkesir")!.contains("Altıeylül"))
        XCTAssertTrue(DistrictCatalog.districts(forCity: "Yalova")!.contains("Merkez"))
    }

    func testCityLookupIgnoresCaseTurkishCharactersAndKnowsAfyonAlias() {
        XCTAssertEqual(DistrictCatalog.canonicalCity("bursa"), "Bursa")
        XCTAssertEqual(DistrictCatalog.canonicalCity("CANAKKALE"), "Çanakkale")
        XCTAssertEqual(DistrictCatalog.canonicalCity("Eskisehir"), "Eskişehir")
        XCTAssertEqual(DistrictCatalog.canonicalCity("afyon"), "Afyonkarahisar")
        XCTAssertNil(DistrictCatalog.canonicalCity("Ankara"))
        XCTAssertNil(DistrictCatalog.districts(forCity: "Ankara"), "Listede olmayan şehirde ilçe serbest metin")
    }

    func testMatchIsCaseAndTurkishCharacterInsensitive() {
        let cases: [(String, String, String)] = [
            ("Nilufer", "Bursa", "Nilüfer"),
            ("NİLÜFER", "Bursa", "Nilüfer"),
            ("nilüfer", "Bursa", "Nilüfer"),
            ("  Nilüfer ", "Bursa", "Nilüfer"),
            ("IZNIK", "Bursa", "İznik"),
            ("Inegol", "Bursa", "İnegöl"),
            ("Cinarcik", "Yalova", "Çınarcık"),
            ("ciftlikkoy", "Yalova", "Çiftlikköy"),
            ("Altieylul", "Balıkesir", "Altıeylül"),
            ("sindirgi", "balikesir", "Sındırgı"),
            ("Mustafakemalpasa", "Bursa", "Mustafakemalpaşa"),
            ("merkez", "Kütahya", "Merkez")
        ]
        for (text, city, official) in cases {
            XCTAssertEqual(DistrictCatalog.match(text, city: city), official, "\(text) / \(city)")
        }
    }

    func testNoMatchLeavesValueAlone() {
        XCTAssertNil(DistrictCatalog.match("Orta Mahalle", city: "Bursa"))
        XCTAssertNil(DistrictCatalog.match("", city: "Bursa"))
        XCTAssertNil(DistrictCatalog.match("Nilüfer", city: "Yalova"), "İlçe başka şehrin listesinde")
        XCTAssertNil(DistrictCatalog.match("Çankaya", city: "Ankara"))
        XCTAssertEqual(DistrictCatalog.displayName("  Orta Mahalle ", city: "Bursa"), "Orta Mahalle")
        XCTAssertEqual(DistrictCatalog.displayName("nilufer", city: "Bursa"), "Nilüfer")
    }

    func testMigrationNormalizesKnownDistrictsAndKeepsTheRest() throws {
        let env = try TestEnv()
        let wrongCase = Customer(name: "A", city: "Bursa", district: "Nilufer")
        let turkishChars = Customer(name: "B", city: "Yalova", district: "cinarcik")
        let unmatched = Customer(name: "C", city: "Bursa", district: "Orta Mahalle")
        let freeCity = Customer(name: "D", city: "Ankara", district: "cankaya")
        let already = Customer(name: "E", city: "Bursa", district: "Nilüfer")
        let empty = Customer(name: "F", city: "Bursa", district: "")
        for customer in [wrongCase, turkishChars, unmatched, freeCity, already, empty] {
            try env.repos.customers.add(customer)
        }

        XCTAssertEqual(try DistrictMigration.run(customers: env.repos.customers), 2)
        XCTAssertEqual(wrongCase.district, "Nilüfer")
        XCTAssertEqual(turkishChars.district, "Çınarcık")
        XCTAssertEqual(unmatched.district, "Orta Mahalle", "Eşleşmeyen olduğu gibi kalır")
        XCTAssertEqual(freeCity.district, "cankaya", "Listede olmayan şehir dokunulmaz")
        XCTAssertEqual(already.district, "Nilüfer")
        XCTAssertEqual(empty.district, "")

        XCTAssertEqual(try DistrictMigration.run(customers: env.repos.customers), 0, "Tekrar çalıştırmak zararsız")
    }
}

/// Müşteri listesinde ilçe filtresi.
@MainActor
final class CustomerDistrictFilterTests: XCTestCase {
    func testDistrictFilterIgnoresCaseAndTurkishCharacters() throws {
        let env = try TestEnv()
        try env.repos.customers.add(Customer(name: "A", city: "Bursa", district: "Nilüfer"))
        try env.repos.customers.add(Customer(name: "B", city: "Bursa", district: "nilufer"))
        try env.repos.customers.add(Customer(name: "C", city: "Bursa", district: "Osmangazi"))
        try env.repos.customers.add(Customer(name: "D", city: "Yalova", district: "Merkez"))

        var filter = CustomerFilter()
        filter.district = "Nilüfer"
        XCTAssertEqual(try env.repos.customers.search(filter).map(\.name), ["A", "B"])
        filter.district = "NILUFER"
        XCTAssertEqual(try env.repos.customers.search(filter).map(\.name), ["A", "B"])

        filter = CustomerFilter()
        filter.city = "Bursa"
        filter.district = "Osmangazi"
        XCTAssertEqual(try env.repos.customers.search(filter).map(\.name), ["C"])
    }

    func testListModelOffersDistrictsFromDataForTheSelectedCity() throws {
        let env = try TestEnv()
        try env.repos.customers.add(Customer(name: "A", city: "Bursa", district: "Nilüfer"))
        try env.repos.customers.add(Customer(name: "B", city: "Bursa", district: "nilufer"))
        try env.repos.customers.add(Customer(name: "C", city: "Bursa", district: "Osmangazi"))
        try env.repos.customers.add(Customer(name: "D", city: "Yalova", district: "Çınarcık"))
        try env.repos.customers.add(Customer(name: "E", city: "Bursa", district: ""))

        let model = CustomerListModel(repository: env.repos.customers)
        XCTAssertEqual(model.districtOptions(), ["Çınarcık", "Nilüfer", "Osmangazi"], "Aynı ilçenin yazımları tek seçenek")
        model.filter.city = "Bursa"
        XCTAssertEqual(model.districtOptions(), ["Nilüfer", "Osmangazi"])
        XCTAssertTrue(model.hasActiveFilter)
        model.filter.city = nil
        model.filter.district = "Nilüfer"
        XCTAssertTrue(model.hasActiveFilter)
    }
}

/// Bölge ekranının mantığı: filtreler, şehir/ilçe/OSB seviyeleri.
@MainActor
final class RegionBuilderTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 12)
    private let regionCities = ["Çanakkale", "Bursa", "Yalova"]

    private var context: RegionContext {
        RegionContext(rules: VisitFrequencyRules(), now: now, calendar: cal)
    }

    private func make(
        _ env: TestEnv, _ name: String, city: String = "Bursa", district: String = "Nilüfer", zone: String = "",
        status: CustomerStatus = .current, rating: CustomerRating = .promising,
        lastVisitDaysAgo: Int? = nil, createdDaysAgo: Int = 5
    ) throws -> Customer {
        let customer = Customer(name: name, city: city, district: district, industrialZone: zone, status: status, rating: rating)
        customer.createdAt = now.addingTimeInterval(-Double(createdDaysAgo) * 86_400)
        try env.repos.customers.add(customer)
        if let lastVisitDaysAgo {
            let date = now.addingTimeInterval(-Double(lastVisitDaysAgo) * 86_400)
            try env.repos.visits.add(Visit(date: date), customer: customer, contacts: [], opportunity: nil)
        }
        return customer
    }

    private func addQuote(_ env: TestEnv, _ customer: Customer, status: QuoteStatus) throws {
        try env.repos.quotes.add(Quote(quoteNumber: "T-\(UUID().uuidString.prefix(4))", status: status), customer: customer, opportunity: nil)
    }

    private func addTask(_ env: TestEnv, _ customer: Customer, daysFromNow: Int, done: Bool = false) throws {
        let task = FollowUpTask(title: "Takip", dueDate: now.addingTimeInterval(Double(daysFromNow) * 86_400), source: .manual)
        task.isDone = done
        try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
    }

    private func names(_ customers: [Customer]) -> [String] { customers.map(\.name).sorted() }

    // MARK: Filtreler

    func testStatusAndRatingFilters() throws {
        let env = try TestEnv()
        let all = [
            try make(env, "Mevcut Önemli", status: .current, rating: .important),
            try make(env, "Aday Önemli", status: .potential, rating: .important),
            try make(env, "Pasif Zayıf", status: .passive, rating: .weak),
            try make(env, "Aday Zayıf", status: .potential, rating: .weak)
        ]
        var filter = RegionFilter()
        XCTAssertEqual(RegionBuilder.filtered(all, filter: filter, context: context).count, 4, "Boş filtre hepsi")

        filter.status = .potential
        XCTAssertEqual(names(RegionBuilder.filtered(all, filter: filter, context: context)), ["Aday Zayıf", "Aday Önemli"])
        filter.rating = .important
        XCTAssertEqual(names(RegionBuilder.filtered(all, filter: filter, context: context)), ["Aday Önemli"])
        filter = RegionFilter()
        filter.rating = .weak
        XCTAssertEqual(names(RegionBuilder.filtered(all, filter: filter, context: context)), ["Aday Zayıf", "Pasif Zayıf"])
    }

    func testPendingQuoteFilterCountsOnlySentAndFollowUp() throws {
        let env = try TestEnv()
        let sent = try make(env, "Gönderildi")
        let followUp = try make(env, "Takipte")
        let draft = try make(env, "Taslak")
        let won = try make(env, "Kazanıldı")
        _ = try make(env, "Teklifsiz")
        try addQuote(env, sent, status: .sent)
        try addQuote(env, followUp, status: .followUp)
        try addQuote(env, draft, status: .draft)
        try addQuote(env, won, status: .won)

        var filter = RegionFilter()
        filter.pendingQuote = true
        let all = try env.repos.customers.fetchAll()
        XCTAssertEqual(names(RegionBuilder.filtered(all, filter: filter, context: context)), ["Gönderildi", "Takipte"])
    }

    func testVisitFrequencyFilterUsesRatingThresholdsAndSkipsPassive() throws {
        let env = try TestEnv()
        // Eşikler: Önemli 30, Potansiyelli 60, Zayıf 120 gün.
        _ = try make(env, "Önemli 31 gün", rating: .important, lastVisitDaysAgo: 31)
        _ = try make(env, "Önemli 29 gün", rating: .important, lastVisitDaysAgo: 29)
        _ = try make(env, "Önemli tam 30", rating: .important, lastVisitDaysAgo: 30)
        _ = try make(env, "Potansiyelli 45 gün", rating: .promising, lastVisitDaysAgo: 45)
        _ = try make(env, "Potansiyelli 61 gün", rating: .promising, lastVisitDaysAgo: 61)
        _ = try make(env, "Zayıf 119 gün", rating: .weak, lastVisitDaysAgo: 119)
        _ = try make(env, "Zayıf 130 gün", rating: .weak, lastVisitDaysAgo: 130)
        _ = try make(env, "Ziyaretsiz eski kayıt", rating: .important, createdDaysAgo: 40)
        _ = try make(env, "Ziyaretsiz yeni kayıt", rating: .important, createdDaysAgo: 3)
        _ = try make(env, "Pasif eski", status: .passive, rating: .important, lastVisitDaysAgo: 200)

        var filter = RegionFilter()
        filter.visitOverdue = true
        let all = try env.repos.customers.fetchAll()
        XCTAssertEqual(
            names(RegionBuilder.filtered(all, filter: filter, context: context)),
            ["Önemli 31 gün", "Önemli tam 30", "Potansiyelli 61 gün", "Zayıf 130 gün", "Ziyaretsiz eski kayıt"].sorted()
        )
    }

    func testMigrationFilterAndCombinedFilters() throws {
        let env = try TestEnv()
        let eol = try make(env, "Ömrünü tamamlıyor", rating: .important)
        let discontinued = try make(env, "Üretimi durdu", rating: .weak)
        let active = try make(env, "Aktif ürün", rating: .important)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "A", lifecycleStatus: .endOfLife), to: eol)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "B", lifecycleStatus: .discontinued), to: discontinued)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "C", lifecycleStatus: .active), to: active)

        var filter = RegionFilter()
        filter.migration = true
        let all = try env.repos.customers.fetchAll()
        XCTAssertEqual(names(RegionBuilder.filtered(all, filter: filter, context: context)), ["Ömrünü tamamlıyor", "Üretimi durdu"].sorted())
        filter.rating = .important
        XCTAssertEqual(names(RegionBuilder.filtered(all, filter: filter, context: context)), ["Ömrünü tamamlıyor"], "Filtreler birlikte (VE) çalışır")
        XCTAssertEqual(filter.activeCount, 2)
        XCTAssertTrue(filter.isActive)
        XCTAssertFalse(RegionFilter().isActive)
    }

    // MARK: Seviye 1: şehirler

    func testCitiesListRegionCitiesInOrderWithCountsAndSummaries() throws {
        let env = try TestEnv()
        let a = try make(env, "A", city: "Bursa")
        _ = try make(env, "B", city: "bursa", district: "Osmangazi")     // yazım farkı: yine Bursa
        let c = try make(env, "C", city: "Yalova", district: "Merkez")
        _ = try make(env, "D", city: "Ankara", district: "Çankaya")       // bölge dışı şehir
        _ = try make(env, "E", city: "", district: "")                    // şehri yok
        try addQuote(env, a, status: .sent)
        try addQuote(env, a, status: .followUp)
        try addQuote(env, a, status: .lost)
        try addTask(env, a, daysFromNow: -2)                              // gecikmiş
        try addTask(env, a, daysFromNow: -3, done: true)                  // tamamlanmış: sayılmaz
        try addTask(env, a, daysFromNow: 0)                               // bugün: gecikmiş değil
        try addTask(env, c, daysFromNow: -1)

        let cities = RegionBuilder.cities(
            customers: try env.repos.customers.fetchAll(), regionCities: regionCities, filter: RegionFilter(), context: context
        )
        XCTAssertEqual(cities.map(\.city), ["Çanakkale", "Bursa", "Yalova", "Ankara", ""],
                       "Bölge şehirleri Ayarlar sırasıyla (boş da olsa), sonra bölge dışı, en sonda şehri olmayanlar")
        XCTAssertEqual(cities.map(\.stats.customers), [0, 2, 1, 1, 1])
        XCTAssertEqual(cities[1].stats.pendingQuotes, 2)
        XCTAssertEqual(cities[1].stats.overdueTasks, 1)
        XCTAssertEqual(cities[2].stats.overdueTasks, 1)
        XCTAssertEqual(cities[0].stats, RegionStats())
    }

    func testCityCountsFollowTheFilter() throws {
        let env = try TestEnv()
        _ = try make(env, "Önemli", city: "Bursa", rating: .important)
        _ = try make(env, "Zayıf", city: "Bursa", rating: .weak)
        _ = try make(env, "Yalova Zayıf", city: "Yalova", district: "Merkez", rating: .weak)

        var filter = RegionFilter()
        filter.rating = .weak
        let cities = RegionBuilder.cities(
            customers: try env.repos.customers.fetchAll(), regionCities: regionCities, filter: filter, context: context
        )
        XCTAssertEqual(cities.map(\.stats.customers), [0, 1, 1])
    }

    // MARK: Seviye 2: ilçeler

    func testDistrictsGroupSpellingVariantsSortInTurkishOrderAndPutBlankLast() throws {
        let env = try TestEnv()
        _ = try make(env, "A", district: "Nilüfer")
        _ = try make(env, "B", district: "nilufer")
        _ = try make(env, "C", district: "Osmangazi")
        _ = try make(env, "D", district: "İnegöl")
        _ = try make(env, "E", district: "Gemlik")
        _ = try make(env, "F", district: "")
        _ = try make(env, "G", district: "Orta Mahalle")                  // listede yok: olduğu gibi
        _ = try make(env, "H", city: "Yalova", district: "Merkez")        // başka şehir

        let districts = RegionBuilder.districts(
            inCity: "Bursa", customers: try env.repos.customers.fetchAll(), regionCities: regionCities,
            filter: RegionFilter(), context: context
        )
        XCTAssertEqual(districts.map(\.district), ["Gemlik", "İnegöl", "Nilüfer", "Orta Mahalle", "Osmangazi", ""])
        XCTAssertEqual(districts.map(\.stats.customers), [1, 1, 2, 1, 1, 1])
    }

    func testDistrictsOfACityNotInRegionList() throws {
        let env = try TestEnv()
        _ = try make(env, "A", city: "Ankara", district: "Çankaya")
        _ = try make(env, "B", city: "Ankara", district: "çankaya")
        let districts = RegionBuilder.districts(
            inCity: "Ankara", customers: try env.repos.customers.fetchAll(), regionCities: regionCities,
            filter: RegionFilter(), context: context
        )
        XCTAssertEqual(districts.count, 1, "Listede olmayan şehirde de yazım farkları tek ilçe")
        XCTAssertEqual(districts.first?.stats.customers, 2)
    }

    func testDistrictsAreHiddenWhenFilterRemovesAllTheirCustomers() throws {
        let env = try TestEnv()
        _ = try make(env, "A", district: "Nilüfer", status: .current)
        _ = try make(env, "B", district: "Osmangazi", status: .potential)
        var filter = RegionFilter()
        filter.status = .potential
        let districts = RegionBuilder.districts(
            inCity: "Bursa", customers: try env.repos.customers.fetchAll(), regionCities: regionCities,
            filter: filter, context: context
        )
        XCTAssertEqual(districts.map(\.district), ["Osmangazi"])
    }

    // MARK: Seviye 3: müşteriler (OSB'ye göre)

    func testZoneGroupsSortNamedZonesFirstAndPutZonelessCustomersInTheirOwnLastGroup() throws {
        let env = try TestEnv()
        _ = try make(env, "Zeta", zone: "Bursa OSB")
        _ = try make(env, "Alfa", zone: " Bursa   OSB ")                // boşluk farkı: aynı grup
        _ = try make(env, "OSB'siz 2")
        _ = try make(env, "Orta", zone: "Demirtaş OSB")
        _ = try make(env, "OSB'siz 1", zone: "")
        _ = try make(env, "Başka ilçe", district: "Osmangazi", zone: "Bursa OSB")

        let groups = RegionBuilder.zoneGroups(
            inCity: "Bursa", district: "nilufer", customers: try env.repos.customers.fetchAll(),
            regionCities: regionCities, filter: RegionFilter(), context: context
        )
        XCTAssertEqual(groups.map(\.zone), ["Bursa OSB", "Demirtaş OSB", ""])
        XCTAssertEqual(groups[0].customers.map(\.name), ["Alfa", "Zeta"], "Grup içinde ada göre")
        XCTAssertEqual(groups[1].customers.map(\.name), ["Orta"])
        XCTAssertEqual(groups[2].customers.map(\.name), ["OSB'siz 1", "OSB'siz 2"])
    }

    func testZoneGroupsHonourFilterAndEmptyResult() throws {
        let env = try TestEnv()
        _ = try make(env, "Önemli", zone: "Bursa OSB", rating: .important)
        _ = try make(env, "Zayıf", rating: .weak)
        var filter = RegionFilter()
        filter.rating = .important
        let groups = RegionBuilder.zoneGroups(
            inCity: "Bursa", district: "Nilüfer", customers: try env.repos.customers.fetchAll(),
            regionCities: regionCities, filter: filter, context: context
        )
        XCTAssertEqual(groups.map(\.zone), ["Bursa OSB"])
        filter.rating = nil
        filter.migration = true
        XCTAssertTrue(RegionBuilder.zoneGroups(
            inCity: "Bursa", district: "Nilüfer", customers: try env.repos.customers.fetchAll(),
            regionCities: regionCities, filter: filter, context: context
        ).isEmpty)
    }

    // MARK: Model

    func testModelLoadsCustomersAndBuildsAllLevels() throws {
        let env = try TestEnv()
        _ = try make(env, "A", city: "Bursa", district: "Nilüfer", zone: "Bursa OSB")
        let suiteName = "region-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)

        let model = RegionModel(repositories: env.repos, settings: settings)
        model.reload()
        XCTAssertEqual(model.cities.first { $0.city == "Bursa" }?.stats.customers, 1)
        XCTAssertEqual(model.districts(inCity: "Bursa").map(\.district), ["Nilüfer"])
        XCTAssertEqual(model.zoneGroups(inCity: "Bursa", district: "Nilüfer").map(\.zone), ["Bursa OSB"])
        XCTAssertEqual(model.stats(inCity: "Bursa").customers, 1)
        model.filter.status = .passive
        XCTAssertEqual(model.stats(inCity: "Bursa").customers, 0)
    }

    func testRegionSampleShowcaseSpansDistrictsZonesAndFlags() throws {
        let env = try TestEnv()
        try SampleData.load(into: env.repos)
        try SampleData.loadRegionShowcase(into: env.repos)
        let customers = try env.repos.customers.fetchAll()

        let districts = RegionBuilder.districts(
            inCity: "Bursa", customers: customers, regionCities: AppSettings.defaultCities,
            filter: RegionFilter(), context: RegionContext(rules: VisitFrequencyRules())
        )
        XCTAssertEqual(Set(districts.map(\.district)), ["İnegöl", "Kestel", "Nilüfer", "Osmangazi"])
        let groups = RegionBuilder.zoneGroups(
            inCity: "Bursa", district: "Nilüfer", customers: customers, regionCities: AppSettings.defaultCities,
            filter: RegionFilter(), context: RegionContext(rules: VisitFrequencyRules())
        )
        XCTAssertEqual(groups.map(\.zone), ["Bursa OSB", ""], "OSB'li grup ve OSB'siz grup")
        XCTAssertGreaterThanOrEqual(groups[0].customers.count, 2)
        XCTAssertGreaterThanOrEqual(groups[1].customers.count, 2)
    }
}
