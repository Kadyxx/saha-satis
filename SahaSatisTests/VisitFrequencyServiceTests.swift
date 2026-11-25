import XCTest
@testable import SahaSatis

/// Ziyaret sıklığı uyarısı: değerlendirmeye göre eşik, müşteri başına tek açık görev, ziyaret girilince kapanma.
@MainActor
final class VisitFrequencyServiceTests: XCTestCase {
    private let cal = TestCalendar.utc
    /// Çarşamba 12:00.
    private let now = TestCalendar.date(2026, 11, 25, 12)

    private func makeService(_ env: TestEnv, rules: VisitFrequencyRules = VisitFrequencyRules()) -> VisitFrequencyService {
        VisitFrequencyService(repositories: env.repos, rules: rules, calendar: cal)
    }

    private func visit(_ env: TestEnv, _ customer: Customer, on date: Date) throws {
        try env.repos.visits.add(Visit(date: date), customer: customer, contacts: [], opportunity: nil)
    }

    private func frequencyTasks(_ env: TestEnv, for customer: Customer) throws -> [FollowUpTask] {
        try env.repos.tasks.tasks(for: customer).filter { $0.source == .visitFrequency }
    }

    private func dueDay(after visit: Date, days: Int) -> Date {
        let day = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: visit))!
        return TimeOfDay(hour: 9).date(on: day, calendar: cal)
    }

    func testThresholdDependsOnRating() throws {
        let env = try TestEnv()
        let important = try env.makeCustomer("Önemli", rating: .important)
        let promising = try env.makeCustomer("Potansiyelli", rating: .promising)
        let weak = try env.makeCustomer("Zayıf", rating: .weak)
        let visitDate = TestCalendar.date(2026, 11, 20, 10)
        for customer in [important, promising, weak] {
            try visit(env, customer, on: visitDate)
        }

        try makeService(env).sync(now: now)

        XCTAssertEqual(try frequencyTasks(env, for: important).first?.dueDate, dueDay(after: visitDate, days: 30))
        XCTAssertEqual(try frequencyTasks(env, for: promising).first?.dueDate, dueDay(after: visitDate, days: 60))
        XCTAssertEqual(try frequencyTasks(env, for: weak).first?.dueDate, dueDay(after: visitDate, days: 120))
    }

    func testThresholdsComeFromSettings() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(rating: .important)
        let visitDate = TestCalendar.date(2026, 11, 20, 10)
        try visit(env, customer, on: visitDate)

        var rules = VisitFrequencyRules()
        rules.importantDays = 14
        try makeService(env, rules: rules).sync(now: now)

        XCTAssertEqual(try frequencyTasks(env, for: customer).first?.dueDate, dueDay(after: visitDate, days: 14))
    }

    func testTaskTimeIsTheReminderTime() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try visit(env, customer, on: TestCalendar.date(2026, 11, 20, 10))

        var rules = VisitFrequencyRules()
        rules.reminderTime = TimeOfDay(hour: 10, minute: 30)
        try makeService(env, rules: rules).sync(now: now)

        let due = try XCTUnwrap(try frequencyTasks(env, for: customer).first?.dueDate)
        XCTAssertEqual(TimeOfDay(date: due, calendar: cal), TimeOfDay(hour: 10, minute: 30))
    }

    func testOnlyOneOpenTaskPerCustomerAndSyncIsIdempotent() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try visit(env, customer, on: TestCalendar.date(2026, 10, 1, 10))
        let service = makeService(env)

        try service.sync(now: now)
        try service.sync(now: now)
        try service.sync(now: now)

        let tasks = try frequencyTasks(env, for: customer)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, VisitFrequencyService.taskTitle)
        XCTAssertEqual(tasks.first?.customer?.id, customer.id)
    }

    func testDuplicateOpenTasksAreReducedToOne() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try visit(env, customer, on: TestCalendar.date(2026, 10, 1, 10))
        for offset in 0..<3 {
            let task = FollowUpTask(
                title: "kopya",
                dueDate: TestCalendar.date(2026, 11, 26 + offset, 9),
                source: .visitFrequency
            )
            try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
        }

        try makeService(env).sync(now: now)

        let open = try frequencyTasks(env, for: customer).filter { !$0.isDone }
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.dueDate, TestCalendar.date(2026, 11, 26, 9), "En yakın olan kalır")
    }

    func testExistingOpenTaskIsNotTouchedEvenIfUserPostponedIt() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try visit(env, customer, on: TestCalendar.date(2026, 10, 1, 10))
        let service = makeService(env)
        try service.sync(now: now)

        let task = try XCTUnwrap(try frequencyTasks(env, for: customer).first)
        let postponed = TestCalendar.date(2026, 12, 20, 9)
        try env.repos.tasks.postpone(task, to: postponed)
        try service.sync(now: now)

        let tasks = try frequencyTasks(env, for: customer)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.dueDate, postponed)
    }

    func testPassiveCustomersGetNoTaskAndLoseOpenOnes() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .current)
        try visit(env, customer, on: TestCalendar.date(2026, 10, 1, 10))
        let service = makeService(env)
        try service.sync(now: now)
        XCTAssertEqual(try frequencyTasks(env, for: customer).count, 1)

        customer.status = .passive
        try env.repos.customers.update(customer)
        try service.sync(now: now)

        XCTAssertTrue(try frequencyTasks(env, for: customer).isEmpty)
    }

    func testNeverVisitedCustomerCountsFromWhenItWasAdded() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(rating: .promising)
        customer.createdAt = TestCalendar.date(2026, 11, 10, 10)

        try makeService(env).sync(now: now)

        XCTAssertEqual(
            try frequencyTasks(env, for: customer).first?.dueDate,
            dueDay(after: TestCalendar.date(2026, 11, 10), days: 60)
        )
    }

    func testOverdueThresholdIsClampedToTodayAtReminderTime() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(rating: .important)
        try visit(env, customer, on: TestCalendar.date(2026, 6, 1, 10))

        try makeService(env).sync(now: now)

        XCTAssertEqual(try frequencyTasks(env, for: customer).first?.dueDate, TestCalendar.date(2026, 11, 25, 9))
    }

    func testDueDateHelper() {
        let nine = TimeOfDay(hour: 9)
        // Eşik geçmiş: bugün.
        XCTAssertEqual(
            VisitFrequencyService.dueDate(
                reference: TestCalendar.date(2026, 1, 1), thresholdDays: 30, reminderTime: nine, now: now, calendar: cal
            ),
            TestCalendar.date(2026, 11, 25, 9)
        )
        // Eşik ileride: referans günü + eşik.
        XCTAssertEqual(
            VisitFrequencyService.dueDate(
                reference: TestCalendar.date(2026, 11, 25, 17), thresholdDays: 30, reminderTime: nine, now: now, calendar: cal
            ),
            TestCalendar.date(2026, 12, 25, 9)
        )
    }

    func testNewVisitClosesTheTaskAndTheNextOneCountsFromTheVisit() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(rating: .promising)
        let realNow = Date()
        try visit(env, customer, on: realNow.addingTimeInterval(-100 * 86_400))
        let service = makeService(env)
        try service.sync(now: realNow)
        let first = try XCTUnwrap(try frequencyTasks(env, for: customer).first)
        XCTAssertFalse(first.isDone)

        // Yeni ziyaret girilince açık görev kapanır (VisitService).
        var draft = VisitDraft()
        draft.date = realNow
        try VisitService(repositories: env.repos, reminderMinutes: 9 * 60, calendar: cal)
            .save(draft, customer: customer, contacts: [], existing: nil)
        XCTAssertTrue(first.isDone)
        XCTAssertNotNil(first.doneAt)

        // Sonraki eşitleme yeni görevi kurar: tek açık görev, 60 gün sonra.
        try service.sync(now: realNow)
        let all = try frequencyTasks(env, for: customer)
        let open = all.filter { !$0.isDone }
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(open.count, 1)
        let due = try XCTUnwrap(open.first?.dueDate)
        XCTAssertGreaterThan(due, realNow.addingTimeInterval(59 * 86_400))
        XCTAssertLessThan(due, realNow.addingTimeInterval(62 * 86_400))
    }

    func testCompletingWithoutVisitRestartsTheClock() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(rating: .important)
        try visit(env, customer, on: TestCalendar.date(2026, 6, 1, 10))
        let service = makeService(env)
        try service.sync(now: now)

        let task = try XCTUnwrap(try frequencyTasks(env, for: customer).first)
        try env.repos.tasks.complete(task, at: TestCalendar.date(2026, 11, 25, 10))
        try service.sync(now: now)

        let open = try frequencyTasks(env, for: customer).filter { !$0.isDone }
        XCTAssertEqual(open.count, 1, "Görev hemen geri gelmez ama yeni sayaç kurulur")
        XCTAssertEqual(open.first?.dueDate, TestCalendar.date(2026, 12, 25, 9))
    }

    func testRulesMapRatings() {
        var rules = VisitFrequencyRules()
        XCTAssertEqual(rules.days(for: .important), 30)
        XCTAssertEqual(rules.days(for: .promising), 60)
        XCTAssertEqual(rules.days(for: .weak), 120)
        rules.weakDays = 90
        XCTAssertEqual(rules.days(for: .weak), 90)
    }

    func testSettingsProduceRules() {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.visitFrequencyImportantDays = 21
        settings.defaultReminderTime = TimeOfDay(hour: 8, minute: 15)

        let rules = settings.visitFrequencyRules
        XCTAssertEqual(rules.importantDays, 21)
        XCTAssertEqual(rules.promisingDays, 60)
        XCTAssertEqual(rules.reminderTime, TimeOfDay(hour: 8, minute: 15))
    }
}
