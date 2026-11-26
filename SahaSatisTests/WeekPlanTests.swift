import XCTest
@testable import SahaSatis

/// Haftalık şehir planı, ziyaret önerileri (önceliklendirme) ve sabah özeti.
/// Takvim: 24 Kas 2026 Salı … 26 Perşembe, 28 Cumartesi, 29 Pazar, 30 Pazartesi.
final class WeekPlanTests: XCTestCase {
    private let cal = TestCalendar.utc

    private func d(_ day: Int, month: Int = 11) -> Date { TestCalendar.date(2026, month, day) }

    func testDisplayedWeekIsMondayToFridayAndWeekendShowsNextWeek() {
        let midweek = WeekPlan.displayedWeek(at: d(26), calendar: cal)
        XCTAssertEqual(midweek.map { cal.component(.day, from: $0) }, [23, 24, 25, 26, 27])

        let monday = WeekPlan.displayedWeek(at: d(23), calendar: cal)
        XCTAssertEqual(cal.component(.day, from: monday[0]), 23)

        for weekendDay in [28, 29] {
            let week = WeekPlan.displayedWeek(at: d(weekendDay), calendar: cal)
            XCTAssertEqual(week.map { cal.component(.day, from: $0) }, [30, 1, 2, 3, 4], "Hafta sonu: gelecek hafta")
        }
    }

    func testSetCitiesAllowsMultipleAndEmpty() {
        var plan = WeekPlan()
        plan.set(["Bursa", "Yalova"], on: d(24), calendar: cal)
        XCTAssertEqual(plan.cities(on: d(24), calendar: cal), ["Bursa", "Yalova"])
        XCTAssertEqual(plan.cities(on: d(25), calendar: cal), [])
        plan.set([], on: d(24), calendar: cal)
        XCTAssertTrue(plan.cities.isEmpty)
    }

    func testCopyPreviousWeekOverwritesThisWeek() {
        var plan = WeekPlan()
        plan.set(["Bursa"], on: d(16), calendar: cal)            // geçen hafta Pazartesi
        plan.set(["Yalova", "Bilecik"], on: d(18), calendar: cal) // geçen hafta Çarşamba
        plan.set(["Kütahya"], on: d(24), calendar: cal)           // bu hafta Salı (silinmeli: geçen Salı boş)
        let week = WeekPlan.displayedWeek(at: d(26), calendar: cal)
        XCTAssertTrue(plan.hasPreviousWeek(for: week, calendar: cal))

        plan.copyPreviousWeek(into: week, calendar: cal)
        XCTAssertEqual(plan.cities(on: d(23), calendar: cal), ["Bursa"])
        XCTAssertEqual(plan.cities(on: d(24), calendar: cal), [])
        XCTAssertEqual(plan.cities(on: d(25), calendar: cal), ["Yalova", "Bilecik"])
    }

    func testNoPreviousWeekMeansNothingToCopy() {
        let plan = WeekPlan()
        XCTAssertFalse(plan.hasPreviousWeek(for: WeekPlan.displayedWeek(at: d(26), calendar: cal), calendar: cal))
    }

    func testPruneDropsOldEntries() {
        var plan = WeekPlan()
        plan.set(["Bursa"], on: d(1, month: 10), calendar: cal)
        plan.set(["Yalova"], on: d(24), calendar: cal)
        plan.prune(before: d(26), calendar: cal)
        XCTAssertEqual(plan.cities.count, 1)
        XCTAssertEqual(plan.cities(on: d(24), calendar: cal), ["Yalova"])
    }

    // MARK: - Sabah özeti

    func testSummaryBodyMentionsCitiesAndPlannedVisitCount() {
        XCTAssertEqual(
            ReminderPlanner.summaryBody(dueToday: 0, overdue: 0, cities: ["Bursa", "Yalova"], plannedVisits: 3),
            "Bugün Bursa, Yalova: 3 planlı ziyaret"
        )
        XCTAssertEqual(
            ReminderPlanner.summaryBody(dueToday: 4, overdue: 0, cities: ["Bursa"], plannedVisits: 0),
            "Bugün Bursa: planlı ziyaret yok\nBugün 4 takibiniz var"
        )
        XCTAssertNil(ReminderPlanner.summaryBody(dueToday: 0, overdue: 0, cities: [], plannedVisits: 0))
        XCTAssertEqual(
            ReminderPlanner.summaryBody(dueToday: 3, overdue: 0, cities: [], plannedVisits: 0), "Bugün 3 takibiniz var",
            "Şehir planı yoksa eski metin"
        )
    }

    func testMorningSummaryNotificationCarriesCityAndPlannedVisits() {
        let now = TestCalendar.date(2026, 11, 25, 7)
        var settings = ReminderSettingsSnapshot()
        settings.endOfDayEnabled = false
        settings.cityPlan = [WeekPlan.key(d(25), calendar: cal): ["Bursa"]]
        func visit(_ name: String) -> TaskSnapshot {
            TaskSnapshot(id: UUID(), title: WeekPlanTask.titlePrefix + name, customerName: name, customerID: nil,
                         dueDate: TestCalendar.date(2026, 11, 25, 9))
        }
        let plan = ReminderPlanner.plan(
            tasks: [visit("A"), visit("B")], unexportedVisitsToday: 0, settings: settings, now: now, calendar: cal
        )
        let summary = plan.first { $0.id == "summary.2026-11-25" }
        XCTAssertEqual(summary?.body, "Bugün Bursa: 2 planlı ziyaret\nBugün 2 takibiniz var")
    }

    func testMorningSummaryForPlannedDayWithoutTasksIsStillSent() {
        let now = TestCalendar.date(2026, 11, 25, 7)
        var settings = ReminderSettingsSnapshot()
        settings.endOfDayEnabled = false
        settings.cityPlan = [WeekPlan.key(d(26), calendar: cal): ["Balıkesir"]]
        let plan = ReminderPlanner.plan(tasks: [], unexportedVisitsToday: 0, settings: settings, now: now, calendar: cal)
        XCTAssertEqual(plan.first { $0.id == "summary.2026-11-26" }?.body, "Bugün Balıkesir: planlı ziyaret yok")
        XCTAssertNil(plan.first { $0.id == "summary.2026-11-25" }, "Planı ve işi olmayan gün için özet yok")
    }
}

@MainActor
final class VisitSuggesterTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 26, 9)
    private let cities = AppSettings.defaultCities

    private var context: RegionContext {
        RegionContext(rules: VisitFrequencyRules(), now: now, calendar: cal)
    }

    private func suggest(_ env: TestEnv, cities planned: [String] = ["Bursa"], planned ids: Set<UUID> = []) throws -> [VisitSuggestion] {
        VisitSuggester.suggestions(
            cities: planned, customers: try env.repos.customers.fetchAll(), regionCities: cities,
            context: context, expiryWarningDays: 3, plannedCustomerIDs: ids
        )
    }

    /// Hiçbir nedeni olmayan taze müşteri: yeni eklenmiş, aday değil.
    private func quietCustomer(_ env: TestEnv, _ name: String, city: String = "Bursa", rating: CustomerRating = .promising) throws -> Customer {
        let customer = try env.makeCustomer(name, city: city, status: .current, rating: rating)
        customer.createdAt = now
        return customer
    }

    func testPriorityOrderFollowsSpec() throws {
        let env = try TestEnv()
        let never = try env.makeCustomer("E Aday", status: .potential)
        never.createdAt = now
        let opp = try quietCustomer(env, "D Fırsat")
        try env.repos.opportunities.add(Opportunity(title: "Yeni hat", stage: .qualified), customer: opp)
        let frequency = try quietCustomer(env, "C Sıklık", rating: .important)
        frequency.createdAt = TestCalendar.date(2026, 9, 1)
        let quote = try quietCustomer(env, "B Teklif")
        try env.repos.quotes.add(
            Quote(quoteNumber: "T-1", validUntil: TestCalendar.date(2026, 11, 28), status: .sent), customer: quote, opportunity: nil
        )
        let overdue = try quietCustomer(env, "A Gecikmiş")
        try env.repos.tasks.add(
            FollowUpTask(title: "Ara", dueDate: TestCalendar.date(2026, 11, 20)), customer: overdue, quote: nil, visit: nil, opportunity: nil
        )

        let result = try suggest(env)
        XCTAssertEqual(result.map(\.customer.name), ["A Gecikmiş", "B Teklif", "C Sıklık", "D Fırsat", "E Aday"])
        XCTAssertEqual(result.map { $0.primary.priority }, [0, 1, 2, 3, 4])
    }

    func testCustomerWithSeveralReasonsRanksByStrongestAndKeepsAllReasons() throws {
        let env = try TestEnv()
        let customer = try quietCustomer(env, "Çok nedenli")
        try env.repos.tasks.add(
            FollowUpTask(title: "Ara", dueDate: TestCalendar.date(2026, 11, 1)), customer: customer, quote: nil, visit: nil, opportunity: nil
        )
        try env.repos.opportunities.add(Opportunity(title: "Hat 3", stage: .quoted), customer: customer)
        let result = try suggest(env)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].reasons, [.overdueTasks(1), .openOpportunity(title: "Hat 3", count: 1)])
        XCTAssertEqual(result[0].reasons.map(\.text), ["1 gecikmiş takip", "Açık fırsat: Hat 3"])
    }

    func testOnlyPlannedCitiesAreSuggestedAndCityMatchIsLenient() throws {
        let env = try TestEnv()
        for (name, city) in [("Bursalı", "bursa"), ("Yalovalı", "Yalova"), ("Ankaralı", "Ankara")] {
            let customer = try env.makeCustomer(name, city: city, status: .potential)
            customer.createdAt = now
        }
        XCTAssertEqual(try suggest(env, cities: ["Bursa"]).map(\.customer.name), ["Bursalı"])
        XCTAssertEqual(Set(try suggest(env, cities: ["Bursa", "Yalova"]).map(\.customer.name)), ["Bursalı", "Yalovalı"])
        XCTAssertTrue(try suggest(env, cities: []).isEmpty)
    }

    func testPassiveAndReasonlessCustomersAreNotSuggested() throws {
        let env = try TestEnv()
        _ = try quietCustomer(env, "Sakin")
        let passive = try env.makeCustomer("Pasif", status: .passive)
        passive.createdAt = TestCalendar.date(2026, 1, 1)
        XCTAssertTrue(try suggest(env).isEmpty)
    }

    func testSameTierSortsByRatingThenName() throws {
        let env = try TestEnv()
        for (name, rating) in [("Z Önemli", CustomerRating.important), ("B Zayıf", .weak), ("A Zayıf", .weak), ("M Potansiyelli", .promising)] {
            let customer = try env.makeCustomer(name, status: .potential, rating: rating)
            customer.createdAt = now
        }
        XCTAssertEqual(
            try suggest(env).map(\.customer.name), ["Z Önemli", "M Potansiyelli", "A Zayıf", "B Zayıf"]
        )
    }

    func testExpiredPendingQuoteCountsButClosedOrFarQuotesDoNot() throws {
        let env = try TestEnv()
        let expired = try quietCustomer(env, "Süresi doldu")
        try env.repos.quotes.add(Quote(quoteNumber: "1", validUntil: TestCalendar.date(2026, 11, 20), status: .followUp), customer: expired, opportunity: nil)
        let far = try quietCustomer(env, "Uzak")
        try env.repos.quotes.add(Quote(quoteNumber: "2", validUntil: TestCalendar.date(2026, 12, 30), status: .sent), customer: far, opportunity: nil)
        let won = try quietCustomer(env, "Kazanıldı")
        try env.repos.quotes.add(Quote(quoteNumber: "3", validUntil: TestCalendar.date(2026, 11, 27), status: .won), customer: won, opportunity: nil)

        let result = try suggest(env)
        XCTAssertEqual(result.map(\.customer.name), ["Süresi doldu"])
        XCTAssertEqual(result[0].primary.text, "Teklif süresi doldu")
    }

    func testFrequencyAndPlanTasksDoNotCountAsOverdueFollowUps() throws {
        let env = try TestEnv()
        let customer = try quietCustomer(env, "Sıklık görevi")
        try env.repos.tasks.add(
            FollowUpTask(title: "Ziyaret zamanı geldi", dueDate: TestCalendar.date(2026, 11, 1), source: .visitFrequency),
            customer: customer, quote: nil, visit: nil, opportunity: nil
        )
        try env.repos.tasks.add(
            FollowUpTask(title: "Ziyaret: Sıklık görevi", dueDate: TestCalendar.date(2026, 11, 2)),
            customer: customer, quote: nil, visit: nil, opportunity: nil
        )
        XCTAssertTrue(try suggest(env).isEmpty)
    }

    func testPlannedFlagComesFromGivenIDs() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Aday", status: .potential)
        customer.createdAt = now
        XCTAssertFalse(try suggest(env)[0].isPlanned)
        XCTAssertTrue(try suggest(env, planned: [customer.id])[0].isPlanned)
    }

    // MARK: - Plana ekle

    func testAddToPlanCreatesVisitTaskAtReminderTimeAndIsIdempotent() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Örnek Makina A.Ş.")
        let day = TestCalendar.date(2026, 11, 27, 0)

        XCTAssertTrue(try WeekPlanTask.add(customer: customer, day: day, reminderTime: TimeOfDay(hour: 9, minute: 30), repositories: env.repos, calendar: cal))
        XCTAssertFalse(try WeekPlanTask.add(customer: customer, day: day, reminderTime: TimeOfDay(hour: 9, minute: 30), repositories: env.repos, calendar: cal))

        let tasks = try env.repos.tasks.tasks(for: customer)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Ziyaret: Örnek Makina A.Ş.")
        XCTAssertEqual(tasks[0].dueDate, TestCalendar.date(2026, 11, 27, 9, 30))
        XCTAssertEqual(try WeekPlanTask.plannedCustomerIDs(on: day, repositories: env.repos, calendar: cal), [customer.id])
    }
}
