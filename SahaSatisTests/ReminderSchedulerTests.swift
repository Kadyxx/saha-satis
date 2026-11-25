import XCTest
@testable import SahaSatis

/// Hatırlatma motoru uçtan uca (gerçek SwiftData deposu bellekte, sahte bildirim merkezi).
@MainActor
final class ReminderSchedulerTests: XCTestCase {
    private let cal = TestCalendar.utc
    /// Çarşamba 12:00.
    private let now = TestCalendar.date(2026, 11, 25, 12)

    private func makeSettings() -> SahaSatis.AppSettings {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SahaSatis.AppSettings(defaults: defaults)
    }

    private func makeScheduler(
        _ env: TestEnv,
        settings: SahaSatis.AppSettings,
        mock: MockNotificationScheduler
    ) -> ReminderScheduler {
        let fixedNow = now
        return ReminderScheduler(
            repositories: env.repos,
            settings: settings,
            scheduler: mock,
            calendar: cal,
            now: { fixedNow }
        )
    }

    @discardableResult
    private func addTask(
        _ env: TestEnv,
        _ title: String,
        due: Date,
        customer: Customer?,
        done: Bool = false
    ) throws -> FollowUpTask {
        let task = FollowUpTask(title: title, dueDate: due, source: .manual)
        try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
        if done { try env.repos.tasks.complete(task, at: now) }
        return task
    }

    /// Yalnızca görevleri sınamak için sabah özeti ve gün sonunu kapatır.
    private func quiet(_ settings: SahaSatis.AppSettings) {
        settings.morningSummaryEnabled = false
        settings.endOfDayReminderEnabled = false
    }

    func testRefreshPlansOpenTasksOnly() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Örnek Makina A.Ş.", status: .passive)
        let open = try addTask(env, "Açık", due: TestCalendar.date(2026, 11, 26, 9), customer: customer)
        try addTask(env, "Bitti", due: TestCalendar.date(2026, 11, 26, 10), customer: customer, done: true)
        let settings = makeSettings()
        quiet(settings)
        let mock = MockNotificationScheduler()

        await makeScheduler(env, settings: settings, mock: mock).refresh()

        XCTAssertEqual(mock.calls.count, 1)
        XCTAssertEqual(mock.lastPlan.map(\.taskID), [open.id])
        XCTAssertEqual(mock.lastPlan.first?.title, "Örnek Makina A.Ş.")
        XCTAssertEqual(mock.lastPlan.first?.customerID, customer.id)
    }

    func testRefreshNeverPlansMoreThan64() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        let start = TestCalendar.date(2026, 11, 26, 0)
        for index in 0..<100 {
            try addTask(env, "T\(index)", due: cal.date(byAdding: .hour, value: index, to: start)!, customer: customer)
        }
        let settings = makeSettings()
        quiet(settings)
        settings.weekendNotificationsEnabled = true
        let mock = MockNotificationScheduler()

        await makeScheduler(env, settings: settings, mock: mock).refresh()

        XCTAssertEqual(mock.lastPlan.count, 64)
        XCTAssertEqual(mock.lastPlan.map(\.body), (0..<64).map { "T\($0)" })
    }

    func testWeekendSettingChangesThePlan() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        try addTask(env, "Cumartesi işi", due: TestCalendar.date(2026, 11, 28, 10), customer: customer)
        let settings = makeSettings()
        quiet(settings)
        let mock = MockNotificationScheduler()
        let scheduler = makeScheduler(env, settings: settings, mock: mock)

        settings.weekendNotificationsEnabled = false
        await scheduler.refresh()
        XCTAssertEqual(mock.lastPlan.first?.fireDate, TestCalendar.date(2026, 11, 30, 10), "Pazartesi'ye kaydı")

        settings.weekendNotificationsEnabled = true
        await scheduler.refresh()
        XCTAssertEqual(mock.lastPlan.first?.fireDate, TestCalendar.date(2026, 11, 28, 10))
    }

    func testReminderTimeSettingsDriveSummaryAndEndOfDay() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        try addTask(env, "Bugünkü iş", due: TestCalendar.date(2026, 11, 26, 9), customer: customer)
        try env.repos.visits.add(
            Visit(date: TestCalendar.date(2026, 11, 25, 10)),
            customer: customer, contacts: [], opportunity: nil
        )
        let settings = makeSettings()
        settings.morningSummaryTime = SahaSatis.TimeOfDay(hour: 7, minute: 45)
        settings.endOfDayReminderTime = SahaSatis.TimeOfDay(hour: 17, minute: 30)
        let mock = MockNotificationScheduler()
        // Şimdi: Çarşamba 07:00 (özet ve gün sonu henüz gelmedi).
        let early = TestCalendar.date(2026, 11, 25, 7)
        let scheduler = ReminderScheduler(
            repositories: env.repos, settings: settings, scheduler: mock, calendar: cal, now: { early }
        )

        await scheduler.refresh()

        let endOfDay = try XCTUnwrap(mock.lastPlan.first { $0.kind == .endOfDay })
        XCTAssertEqual(endOfDay.fireDate, TestCalendar.date(2026, 11, 25, 17, 30))
        XCTAssertEqual(endOfDay.body, "1 ziyaret CRM'e aktarılmadı")
        let summary = try XCTUnwrap(mock.lastPlan.first { $0.kind == .morningSummary })
        XCTAssertEqual(summary.fireDate, TestCalendar.date(2026, 11, 26, 7, 45))
    }

    func testExportedVisitsDoNotTriggerEndOfDayReminder() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        let visit = Visit(date: TestCalendar.date(2026, 11, 25, 10))
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)
        try env.repos.visits.markExported([visit], at: now)
        let settings = makeSettings()
        let mock = MockNotificationScheduler()
        let early = TestCalendar.date(2026, 11, 25, 7)
        let scheduler = ReminderScheduler(
            repositories: env.repos, settings: settings, scheduler: mock, calendar: cal, now: { early }
        )

        await scheduler.refresh()

        XCTAssertFalse(mock.lastPlan.contains { $0.kind == .endOfDay })
    }

    func testRefreshCreatesAndPlansVisitFrequencyTask() async throws {
        let env = try TestEnv()
        // 8 Kas'taki ziyaret + önemli (30 gün) = 8 Ara Salı 09:00.
        let customer = try env.makeCustomer("Sık Ziyaret Ltd.", rating: .important)
        try env.repos.visits.add(
            Visit(date: TestCalendar.date(2026, 11, 8, 10)),
            customer: customer, contacts: [], opportunity: nil
        )
        let settings = makeSettings()
        quiet(settings)
        let mock = MockNotificationScheduler()

        await makeScheduler(env, settings: settings, mock: mock).refresh()

        let tasks = try env.repos.tasks.tasks(for: customer)
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.source, .visitFrequency)
        XCTAssertEqual(mock.lastPlan.count, 1)
        XCTAssertEqual(mock.lastPlan.first?.fireDate, TestCalendar.date(2026, 12, 8, 9))
        XCTAssertEqual(mock.lastPlan.first?.title, "Sık Ziyaret Ltd.")
        XCTAssertEqual(mock.lastPlan.first?.body, VisitFrequencyService.taskTitle)
    }

    func testAuthorizationStateIsPublished() async throws {
        let env = try TestEnv()
        let mock = MockNotificationScheduler(state: .denied)
        let scheduler = makeScheduler(env, settings: makeSettings(), mock: mock)

        await scheduler.refresh()

        XCTAssertEqual(scheduler.authorization, .denied)
    }

    func testStartAsksForPermissionOnlyWhenNotDetermined() async throws {
        let env = try TestEnv()
        let undecided = MockNotificationScheduler(state: .notDetermined)
        await makeScheduler(env, settings: makeSettings(), mock: undecided).start()
        XCTAssertEqual(undecided.requestCount, 1)
        XCTAssertEqual(undecided.calls.count, 1)

        let denied = MockNotificationScheduler(state: .denied)
        await makeScheduler(env, settings: makeSettings(), mock: denied).start()
        XCTAssertEqual(denied.requestCount, 0, "Reddedilmişse yeniden sorulmaz")
    }

    func testDataChangeTriggersRescheduling() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        let settings = makeSettings()
        quiet(settings)
        let mock = MockNotificationScheduler()
        let scheduler = makeScheduler(env, settings: settings, mock: mock)
        await scheduler.start()
        XCTAssertEqual(mock.lastPlan.count, 0)

        // Repository kaydı → bildirim → (kısa bekleme) → yeniden planlama
        let task = try addTask(env, "Yeni", due: TestCalendar.date(2026, 11, 26, 9), customer: customer)

        var waited = 0
        while mock.lastPlan.isEmpty && waited < 50 {
            try await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        XCTAssertEqual(mock.lastPlan.map(\.taskID), [task.id])
    }

    func testBurstOfChangesIsCoalesced() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        let settings = makeSettings()
        quiet(settings)
        let mock = MockNotificationScheduler()
        let scheduler = makeScheduler(env, settings: settings, mock: mock)
        await scheduler.start()
        let baseline = mock.calls.count

        for index in 0..<5 {
            try addTask(env, "T\(index)", due: TestCalendar.date(2026, 11, 26, 9 + index), customer: customer)
        }
        try await Task.sleep(for: .milliseconds(1500))

        XCTAssertEqual(mock.lastPlan.count, 5)
        XCTAssertLessThanOrEqual(mock.calls.count - baseline, 2, "Beş kayıt birkaç değil, en çok bir-iki hesaplama üretir")
    }
}
