import XCTest
@testable import SahaSatis

/// Bugün ekranı: gruplama, ziyaret sayıları, kaydırma işlemleri.
@MainActor
final class TodayTests: XCTestCase {
    private let cal = TestCalendar.utc
    /// Çarşamba 14:00.
    private let now = TestCalendar.date(2026, 11, 25, 14)

    @discardableResult
    private func addTask(
        _ env: TestEnv,
        _ title: String,
        due: Date,
        customer: Customer? = nil,
        done: Bool = false
    ) throws -> FollowUpTask {
        let task = FollowUpTask(title: title, dueDate: due, source: .manual)
        try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
        if done { try env.repos.tasks.complete(task, at: now) }
        return task
    }

    func testSectionsGroupByDayAndSortByDueDate() throws {
        let env = try TestEnv()
        try addTask(env, "Evvelsi gün", due: TestCalendar.date(2026, 11, 23, 9))
        try addTask(env, "Dün", due: TestCalendar.date(2026, 11, 24, 17))
        try addTask(env, "Bugün akşam", due: TestCalendar.date(2026, 11, 25, 20))
        try addTask(env, "Bugün sabah (saati geçti)", due: TestCalendar.date(2026, 11, 25, 8))
        try addTask(env, "Yarın", due: TestCalendar.date(2026, 11, 26, 9))
        try addTask(env, "Öbür gün", due: TestCalendar.date(2026, 11, 27, 9))
        try addTask(env, "Tamamlanmış", due: TestCalendar.date(2026, 11, 25, 9), done: true)

        let sections = TodaySections.make(from: try env.repos.tasks.fetchAll(), now: now, calendar: cal)

        XCTAssertEqual(sections.overdue.map(\.title), ["Evvelsi gün", "Dün"])
        XCTAssertEqual(sections.today.map(\.title), ["Bugün sabah (saati geçti)", "Bugün akşam"])
        XCTAssertEqual(sections.tomorrow.map(\.title), ["Yarın"])
        XCTAssertFalse(sections.isEmpty)
    }

    func testEmptySections() throws {
        let env = try TestEnv()
        XCTAssertTrue(TodaySections.make(from: try env.repos.tasks.fetchAll(), now: now, calendar: cal).isEmpty)
    }

    func testModelLoadsTasksAndVisitsOfToday() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try addTask(env, "Bugün", due: TestCalendar.date(2026, 11, 25, 16), customer: customer)

        let exported = Visit(date: TestCalendar.date(2026, 11, 25, 9))
        let pending = Visit(date: TestCalendar.date(2026, 11, 25, 11))
        let yesterday = Visit(date: TestCalendar.date(2026, 11, 24, 11))
        for visit in [exported, pending, yesterday] {
            try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)
        }
        try env.repos.visits.markExported([exported], at: now)

        let model = TodayModel(repositories: env.repos, calendar: cal)
        model.reload(now: now)

        XCTAssertEqual(model.sections.today.count, 1)
        XCTAssertEqual(model.visitsToday.count, 2, "Dünkü ziyaret sayılmaz")
        XCTAssertEqual(model.unexportedCount, 1)
    }

    func testCompleteRemovesTaskFromList() throws {
        let env = try TestEnv()
        let task = try addTask(env, "Yap", due: TestCalendar.date(2026, 11, 25, 16))
        let model = TodayModel(repositories: env.repos, calendar: cal)
        model.reload(now: now)
        XCTAssertEqual(model.sections.today.count, 1)

        model.complete(task)

        XCTAssertTrue(task.isDone)
        XCTAssertNotNil(task.doneAt)
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testPostponeMovesTaskToAnotherGroup() throws {
        let env = try TestEnv()
        let task = try addTask(env, "Ertele", due: TestCalendar.date(2026, 11, 20, 9))
        let fixedNow = now
        let service = TaskActionService(repositories: env.repos, calendar: cal, now: { fixedNow })

        try service.postpone(task, .days(1))
        XCTAssertEqual(task.dueDate, TestCalendar.date(2026, 11, 26, 9))
        XCTAssertEqual(TodaySections.make(from: [task], now: now, calendar: cal).tomorrow.count, 1)

        try service.postpone(task, .days(3))
        XCTAssertEqual(task.dueDate, TestCalendar.date(2026, 11, 29, 9), "İleri tarihli görev kendi gününden (26 Kas) sayılır")
        XCTAssertTrue(TodaySections.make(from: [task], now: now, calendar: cal).isEmpty)
    }

    func testServiceCompleteStampsNow() throws {
        let env = try TestEnv()
        let task = try addTask(env, "Yap", due: TestCalendar.date(2026, 11, 25, 16))
        let fixedNow = now
        try TaskActionService(repositories: env.repos, calendar: cal, now: { fixedNow }).complete(task)
        XCTAssertEqual(task.doneAt, now)
    }

    func testOverdueTrailingText() {
        func text(dueDay: Int) -> String {
            TaskRow.trailingText(
                dueDate: TestCalendar.date(2026, 11, dueDay, 9), isOverdue: true, now: now, calendar: cal
            )
        }
        XCTAssertEqual(text(dueDay: 24), "Dün")
        XCTAssertEqual(text(dueDay: 23), "2 gün gecikti")
        XCTAssertEqual(text(dueDay: 15), "10 gün gecikti")
    }

    func testManualTaskDefaultsToNextReminderTime() {
        let nine = TimeOfDay(hour: 9)
        XCTAssertEqual(
            ManualTaskFormView.initialDueDate(now: TestCalendar.date(2026, 11, 25, 7), reminderTime: nine, calendar: cal),
            TestCalendar.date(2026, 11, 25, 9)
        )
        XCTAssertEqual(
            ManualTaskFormView.initialDueDate(now: TestCalendar.date(2026, 11, 25, 10), reminderTime: nine, calendar: cal),
            TestCalendar.date(2026, 11, 26, 9)
        )
    }

    func testEveryTaskSourceHasAnIcon() {
        for source in TaskSource.allCases {
            XCTAssertFalse(source.systemImage.isEmpty)
        }
    }
}

/// Bildirim aksiyonları (Tamamlandı, Yarına ertele) ve bildirime dokunma.
@MainActor
final class NotificationActionTests: XCTestCase {
    private func makeContext(_ env: TestEnv) -> AppContext {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppContext(
            repositories: env.repos,
            settings: AppSettings(defaults: defaults),
            makeSpeechEngine: { MockSpeechEngine() },
            notificationScheduler: MockNotificationScheduler()
        )
    }

    private func makeTask(_ env: TestEnv, due: Date) throws -> (FollowUpTask, Customer) {
        let customer = try env.makeCustomer(status: .passive)
        let task = FollowUpTask(title: "Teklif takibi", dueDate: due, source: .manual)
        try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
        return (task, customer)
    }

    func testCompleteActionMarksTaskDone() async throws {
        let env = try TestEnv()
        let context = makeContext(env)
        let (task, customer) = try makeTask(env, due: Date().addingTimeInterval(3600))

        await context.handleNotification(NotificationResponse(
            actionID: NotificationIdentifiers.completeAction, taskID: task.id, customerID: customer.id
        ))

        XCTAssertTrue(task.isDone)
        XCTAssertNil(context.customerToOpen, "Aksiyon düğmesi uygulamayı açmaz")
    }

    func testPostponeActionMovesTaskToTomorrowKeepingTime() async throws {
        let env = try TestEnv()
        let context = makeContext(env)
        let due = Date().addingTimeInterval(3600)
        let (task, customer) = try makeTask(env, due: due)

        await context.handleNotification(NotificationResponse(
            actionID: NotificationIdentifiers.postponeAction, taskID: task.id, customerID: customer.id
        ))

        let shift = task.dueDate.timeIntervalSince(due)
        XCTAssertGreaterThan(shift, 23 * 3600)
        XCTAssertLessThan(shift, 25 * 3600)
        XCTAssertFalse(task.isDone)
    }

    func testTapOpensCustomerOrTodayTab() async throws {
        let env = try TestEnv()
        let context = makeContext(env)
        let (task, customer) = try makeTask(env, due: Date().addingTimeInterval(3600))

        await context.handleNotification(NotificationResponse(
            actionID: "com.apple.UNNotificationDefaultActionIdentifier", taskID: task.id, customerID: customer.id
        ))
        XCTAssertEqual(context.customerToOpen, customer.id)
        XCTAssertEqual(context.requestedTab, .customers)

        context.customerToOpen = nil
        context.requestedTab = nil
        await context.handleNotification(NotificationResponse(
            actionID: "com.apple.UNNotificationDefaultActionIdentifier", taskID: nil, customerID: nil
        ))
        XCTAssertNil(context.customerToOpen)
        XCTAssertEqual(context.requestedTab, .today)
    }

    func testUnknownTaskIsIgnored() async throws {
        let env = try TestEnv()
        let context = makeContext(env)
        await context.handleNotification(NotificationResponse(
            actionID: NotificationIdentifiers.completeAction, taskID: UUID(), customerID: nil
        ))
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
    }

    func testOpenCustomerRequestsCustomersTab() throws {
        let env = try TestEnv()
        let context = makeContext(env)
        let customer = try env.makeCustomer()
        context.open(customer: customer)
        XCTAssertEqual(context.customerToOpen, customer.id)
        XCTAssertEqual(context.requestedTab, .customers)
    }

    func testResponseFlags() {
        XCTAssertTrue(NotificationResponse(actionID: NotificationIdentifiers.completeAction, taskID: nil, customerID: nil).isComplete)
        XCTAssertTrue(NotificationResponse(actionID: NotificationIdentifiers.postponeAction, taskID: nil, customerID: nil).isPostpone)
    }
}
