import XCTest
@testable import SahaSatis

/// Zamanlama mantığı, 64 sınırı, hafta sonu kaydırma (saf mantık; SwiftData yok).
/// Takvim: 24 Kas 2026 Salı, 25 Çarşamba, 26 Perşembe, 27 Cuma, 28 Cumartesi, 29 Pazar, 30 Pazartesi.
final class ReminderPlannerTests: XCTestCase {
    private let cal = TestCalendar.utc
    /// Çarşamba 07:00: sabah özeti (08:00) henüz gelmedi.
    private let now = TestCalendar.date(2026, 11, 25, 7)

    private func task(
        _ title: String = "Teklif hazırla",
        due: Date,
        customer: String? = "Örnek Makina A.Ş."
    ) -> TaskSnapshot {
        TaskSnapshot(id: UUID(), title: title, customerName: customer, customerID: nil, dueDate: due)
    }

    private func plan(
        _ tasks: [TaskSnapshot],
        unexported: Int = 0,
        settings: ReminderSettingsSnapshot = ReminderSettingsSnapshot(),
        now: Date? = nil,
        limit: Int = ReminderPlanner.maxPendingNotifications
    ) -> [PlannedNotification] {
        ReminderPlanner.plan(
            tasks: tasks,
            unexportedVisitsToday: unexported,
            settings: settings,
            now: now ?? self.now,
            calendar: cal,
            limit: limit
        )
    }

    private func tasksOnly(_ plan: [PlannedNotification]) -> [PlannedNotification] {
        plan.filter { $0.kind == .task }
    }

    private var quietSettings: ReminderSettingsSnapshot {
        var settings = ReminderSettingsSnapshot()
        settings.morningSummaryEnabled = false
        settings.endOfDayEnabled = false
        return settings
    }

    // MARK: - Görev bildirimleri

    func testTaskNotificationFiresAtDueTimeWithCustomerAndTitle() throws {
        let item = task("Hat 3 teklifi", due: TestCalendar.date(2026, 11, 26, 9))
        let result = try XCTUnwrap(tasksOnly(plan([item])).first)

        XCTAssertEqual(result.fireDate, TestCalendar.date(2026, 11, 26, 9))
        XCTAssertEqual(result.title, "Örnek Makina A.Ş.")
        XCTAssertEqual(result.body, "Hat 3 teklifi")
        XCTAssertEqual(result.id, "task.\(item.id.uuidString)")
        XCTAssertEqual(result.taskID, item.id)
    }

    func testTaskWithoutCustomerUsesGenericTitle() throws {
        let item = task("Vergi dairesini ara", due: TestCalendar.date(2026, 11, 26, 9), customer: nil)
        let result = try XCTUnwrap(tasksOnly(plan([item])).first)
        XCTAssertEqual(result.title, "Takip hatırlatması")
    }

    func testPastAndCurrentTasksAreNotScheduled() {
        let past = task(due: TestCalendar.date(2026, 11, 25, 6))
        let exactlyNow = task(due: now)
        XCTAssertTrue(tasksOnly(plan([past, exactlyNow])).isEmpty)
    }

    func testPlanIsSortedByFireDate() {
        let late = task("Geç", due: TestCalendar.date(2026, 11, 27, 15))
        let early = task("Erken", due: TestCalendar.date(2026, 11, 26, 9))
        let middle = task("Orta", due: TestCalendar.date(2026, 11, 26, 14))
        let result = plan([late, early, middle], settings: quietSettings)
        XCTAssertEqual(result.map(\.body), ["Erken", "Orta", "Geç"])
    }

    // MARK: - Hafta sonu kaydırma

    func testWeekendTasksShiftToMondayKeepingTime() {
        var settings = quietSettings
        settings.weekendNotifications = false
        let saturday = task("Cumartesi", due: TestCalendar.date(2026, 11, 28, 10))
        let sunday = task("Pazar", due: TestCalendar.date(2026, 11, 29, 15))
        let result = plan([saturday, sunday], settings: settings)

        XCTAssertEqual(result.map(\.fireDate), [
            TestCalendar.date(2026, 11, 30, 10),
            TestCalendar.date(2026, 11, 30, 15)
        ])
    }

    func testWeekdayTasksAreNotShifted() {
        let friday = task(due: TestCalendar.date(2026, 11, 27, 17))
        XCTAssertEqual(
            tasksOnly(plan([friday], settings: quietSettings)).first?.fireDate,
            TestCalendar.date(2026, 11, 27, 17)
        )
    }

    func testWeekendTasksStayWhenWeekendNotificationsAreOn() {
        var settings = quietSettings
        settings.weekendNotifications = true
        let saturday = task(due: TestCalendar.date(2026, 11, 28, 10))
        let sunday = task(due: TestCalendar.date(2026, 11, 29, 15))
        let result = plan([saturday, sunday], settings: settings)

        XCTAssertEqual(result.map(\.fireDate), [
            TestCalendar.date(2026, 11, 28, 10),
            TestCalendar.date(2026, 11, 29, 15)
        ])
    }

    func testNotificationDateHelper() {
        let saturday = TestCalendar.date(2026, 11, 28, 9)
        XCTAssertEqual(
            ReminderPlanner.notificationDate(for: saturday, weekendNotifications: false, calendar: cal),
            TestCalendar.date(2026, 11, 30, 9)
        )
        XCTAssertEqual(
            ReminderPlanner.notificationDate(for: saturday, weekendNotifications: true, calendar: cal),
            saturday
        )
        XCTAssertTrue(ReminderPlanner.isWeekend(saturday, calendar: cal))
        XCTAssertFalse(ReminderPlanner.isWeekend(TestCalendar.date(2026, 11, 30), calendar: cal))
    }

    // MARK: - 64 sınırı

    func testNeverMoreThan64AndTheNearestAreKept() {
        var settings = quietSettings
        settings.weekendNotifications = true
        let start = TestCalendar.date(2026, 11, 26, 0)
        let tasks = (0..<100).map { index in
            task("T\(index)", due: cal.date(byAdding: .hour, value: index, to: start)!)
        }
        let result = plan(tasks.shuffled(), settings: settings)

        XCTAssertEqual(result.count, 64)
        XCTAssertEqual(result.map(\.body), (0..<64).map { "T\($0)" }, "En yakın 64, zamana göre sıralı")
    }

    func testLimitCountsSummariesAndEndOfDayToo() throws {
        var settings = ReminderSettingsSnapshot()
        settings.weekendNotifications = true
        let start = TestCalendar.date(2026, 11, 26, 9)
        let tasks = (0..<70).map { index in
            task("T\(index)", due: cal.date(byAdding: .hour, value: index, to: start)!)
        }
        let result = plan(tasks, unexported: 3, settings: settings)

        XCTAssertEqual(result.count, 64)
        XCTAssertEqual(result.map(\.fireDate), result.map(\.fireDate).sorted())
        XCTAssertEqual(
            result.prefix(2).map(\.kind),
            [.endOfDay, .morningSummary],
            "Bugün 18:00 gün sonu, sonra 26 Kas 08:00 özeti; ikisi de ilk görevden (09:00) önce"
        )
    }

    func testCustomLimit() {
        let tasks = (0..<5).map { task("T\($0)", due: TestCalendar.date(2026, 11, 26, 9 + $0)) }
        XCTAssertEqual(plan(tasks, settings: quietSettings, limit: 3).count, 3)
        XCTAssertTrue(plan(tasks, settings: quietSettings, limit: 0).isEmpty)
    }

    // MARK: - Sabah özeti

    func testMorningSummaryCountsTodayAndOverdue() throws {
        let overdue = task(due: TestCalendar.date(2026, 11, 24, 9))
        let todayA = task(due: TestCalendar.date(2026, 11, 25, 9))
        let todayB = task(due: TestCalendar.date(2026, 11, 25, 13))
        let summary = try XCTUnwrap(plan([overdue, todayA, todayB]).first { $0.kind == .morningSummary })

        XCTAssertEqual(summary.fireDate, TestCalendar.date(2026, 11, 25, 8))
        XCTAssertEqual(summary.body, "Bugün 2 takip, 1 gecikmiş")
        XCTAssertEqual(summary.id, "summary.2026-11-25")
    }

    func testMorningSummaryOnlyForDaysWithSomethingToReport() {
        let result = plan([task(due: TestCalendar.date(2026, 11, 26, 9))])
        let summaries = result.filter { $0.kind == .morningSummary }
        // 26 Kas'ta bugün 1 takip var; 27 Kas'ta 26'daki görev gecikmiş sayılır (hâlâ açık).
        XCTAssertEqual(summaries.first?.id, "summary.2026-11-26")
        XCTAssertEqual(summaries.first?.body, "Bugün 1 takibiniz var")
        XCTAssertFalse(summaries.contains { $0.id == "summary.2026-11-25" }, "25 Kas'ta bildirilecek bir şey yok")
    }

    func testNoSummaryWithoutTasks() {
        XCTAssertTrue(plan([]).isEmpty)
    }

    func testMorningSummaryCanBeDisabled() {
        var settings = ReminderSettingsSnapshot()
        settings.morningSummaryEnabled = false
        let result = plan([task(due: TestCalendar.date(2026, 11, 25, 9))], settings: settings)
        XCTAssertFalse(result.contains { $0.kind == .morningSummary })
    }

    func testMorningSummaryUsesConfiguredTime() throws {
        var settings = ReminderSettingsSnapshot()
        settings.morningSummaryTime = TimeOfDay(hour: 7, minute: 30)
        let item = task(due: TestCalendar.date(2026, 11, 25, 12))
        let summary = try XCTUnwrap(
            plan([item], settings: settings, now: TestCalendar.date(2026, 11, 25, 6)).first { $0.kind == .morningSummary }
        )
        XCTAssertEqual(summary.fireDate, TestCalendar.date(2026, 11, 25, 7, 30))
    }

    func testSummaryWhoseTimeHasPassedIsSkipped() {
        let item = task(due: TestCalendar.date(2026, 11, 25, 12))
        let result = plan([item], now: TestCalendar.date(2026, 11, 25, 9))
        XCTAssertFalse(result.contains { $0.id == "summary.2026-11-25" }, "25 Kas 08:00 geçti")
        XCTAssertEqual(tasksOnly(result).count, 1)
    }

    func testSummarySkipsWeekendDaysWhenWeekendOff() {
        let friday = TestCalendar.date(2026, 11, 27, 7)
        let saturdayTask = task(due: TestCalendar.date(2026, 11, 28, 10))
        let result = plan([saturdayTask], now: friday)

        // Cumartesi/Pazar özeti yok; Pazartesi'de Cumartesi görevi gecikmiş sayılır.
        let summaries = result.filter { $0.kind == .morningSummary }
        XCTAssertEqual(summaries.first?.id, "summary.2026-11-30")
        XCTAssertEqual(summaries.first?.body, "1 gecikmiş takibiniz var")
        XCTAssertFalse(summaries.contains { $0.id == "summary.2026-11-28" || $0.id == "summary.2026-11-29" })
        XCTAssertEqual(tasksOnly(result).first?.fireDate, TestCalendar.date(2026, 11, 30, 10))
    }

    func testSummaryOnWeekendWhenWeekendOn() {
        var settings = ReminderSettingsSnapshot()
        settings.weekendNotifications = true
        let friday = TestCalendar.date(2026, 11, 27, 7)
        let result = plan([task(due: TestCalendar.date(2026, 11, 28, 10))], settings: settings, now: friday)

        XCTAssertEqual(result.first { $0.kind == .morningSummary }?.id, "summary.2026-11-28")
        XCTAssertEqual(result.first { $0.kind == .morningSummary }?.body, "Bugün 1 takibiniz var")
    }

    func testSummaryBodies() {
        XCTAssertNil(ReminderPlanner.summaryBody(dueToday: 0, overdue: 0))
        XCTAssertEqual(ReminderPlanner.summaryBody(dueToday: 3, overdue: 0), "Bugün 3 takibiniz var")
        XCTAssertEqual(ReminderPlanner.summaryBody(dueToday: 0, overdue: 2), "2 gecikmiş takibiniz var")
        XCTAssertEqual(ReminderPlanner.summaryBody(dueToday: 3, overdue: 2), "Bugün 3 takip, 2 gecikmiş")
    }

    // MARK: - Gün sonu hatırlatması

    func testEndOfDayReminderWhenThereAreUnexportedVisits() throws {
        let result = try XCTUnwrap(plan([], unexported: 2, now: TestCalendar.date(2026, 11, 25, 10)).first)
        XCTAssertEqual(result.kind, .endOfDay)
        XCTAssertEqual(result.fireDate, TestCalendar.date(2026, 11, 25, 18))
        XCTAssertEqual(result.body, "2 ziyaret CRM'e aktarılmadı")
        XCTAssertEqual(result.id, "endofday.2026-11-25")
    }

    func testNoEndOfDayReminderWithoutUnexportedVisits() {
        XCTAssertTrue(plan([], unexported: 0).isEmpty)
    }

    func testEndOfDayReminderCanBeDisabledAndTimeChanged() throws {
        var settings = ReminderSettingsSnapshot()
        settings.endOfDayEnabled = false
        XCTAssertTrue(plan([], unexported: 2, settings: settings).isEmpty)

        settings.endOfDayEnabled = true
        settings.endOfDayTime = TimeOfDay(hour: 17, minute: 45)
        let result = try XCTUnwrap(plan([], unexported: 2, settings: settings).first)
        XCTAssertEqual(result.fireDate, TestCalendar.date(2026, 11, 25, 17, 45))
    }

    func testEndOfDayReminderAlreadyPassedIsSkipped() {
        XCTAssertTrue(plan([], unexported: 2, now: TestCalendar.date(2026, 11, 25, 19)).isEmpty)
    }

    func testEndOfDayReminderRespectsWeekendSetting() {
        let saturday = TestCalendar.date(2026, 11, 28, 10)
        XCTAssertTrue(plan([], unexported: 2, now: saturday).isEmpty)

        var settings = ReminderSettingsSnapshot()
        settings.weekendNotifications = true
        XCTAssertEqual(plan([], unexported: 2, settings: settings, now: saturday).count, 1)
    }
}
