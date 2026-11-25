import XCTest
@testable import SahaSatis

/// Widget mantığı: anlık görüntü, zaman çizelgesi, bağlantılar, metinler (saf mantık; SwiftData yok).
/// Takvim: 25 Kas 2026 Çarşamba.
final class WidgetSnapshotTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 14)

    private func task(_ title: String, _ due: Date, customer: String? = "Örnek Makina A.Ş.") -> WidgetTask {
        WidgetTask(id: UUID(), title: title, customerName: customer, dueDate: due)
    }

    private func snapshot(_ tasks: [WidgetTask], at date: Date? = nil) -> WidgetSnapshot {
        WidgetSnapshot.make(data: WidgetData(tasks: tasks), at: date ?? now, calendar: cal)
    }

    func testGroupsOverdueAndToday() {
        let old = task("Evvelsi", TestCalendar.date(2026, 11, 23, 9))
        let yesterday = task("Dün", TestCalendar.date(2026, 11, 24, 17))
        let morning = task("Sabah (saati geçti)", TestCalendar.date(2026, 11, 25, 8))
        let evening = task("Akşam", TestCalendar.date(2026, 11, 25, 20))
        let tomorrow = task("Yarın", TestCalendar.date(2026, 11, 26, 9))
        let result = snapshot([tomorrow, evening, yesterday, morning, old])

        XCTAssertEqual(result.overdue.map(\.title), ["Evvelsi", "Dün"])
        XCTAssertEqual(result.today.map(\.title), ["Sabah (saati geçti)", "Akşam"])
        XCTAssertEqual(result.pendingCount, 4)
        XCTAssertFalse(result.isEmptyToday)
    }

    func testWeekCoversTodayPlusSixDaysAndSkipsEmptyDays() {
        let today = task("Bugün", TestCalendar.date(2026, 11, 25, 16))
        let tomorrow = task("Yarın", TestCalendar.date(2026, 11, 26, 9))
        let lastDay = task("Son gün", TestCalendar.date(2026, 12, 1, 9))
        let tooFar = task("Çok ileri", TestCalendar.date(2026, 12, 2, 9))
        let overdue = task("Gecikmiş", TestCalendar.date(2026, 11, 20, 9))
        let result = snapshot([today, tomorrow, lastDay, tooFar, overdue])

        XCTAssertEqual(result.week.map(\.day), [
            cal.startOfDay(for: TestCalendar.date(2026, 11, 25)),
            cal.startOfDay(for: TestCalendar.date(2026, 11, 26)),
            cal.startOfDay(for: TestCalendar.date(2026, 12, 1))
        ])
        XCTAssertEqual(result.week.flatMap(\.tasks).map(\.title), ["Bugün", "Yarın", "Son gün"])
        XCTAssertEqual(result.overdue.map(\.title), ["Gecikmiş"])
    }

    func testEmptyState() {
        let result = snapshot([])
        XCTAssertTrue(result.isEmptyToday)
        XCTAssertEqual(result.pendingCount, 0)
        XCTAssertNil(result.next)
        XCTAssertFalse(result.nextIsOverdue)
        XCTAssertTrue(result.week.isEmpty)
        XCTAssertEqual(WidgetFormat.emptyTodayText, "Bugün için takip yok")
    }

    func testFutureOnlyTasksAreStillEmptyToday() {
        let result = snapshot([task("Yarın", TestCalendar.date(2026, 11, 26, 9))])
        XCTAssertTrue(result.isEmptyToday)
        XCTAssertEqual(result.next?.title, "Yarın", "Sıradaki iş yine de en yakın görev")
        XCTAssertFalse(result.nextIsOverdue)
    }

    func testNextTaskIsEarliestAndFlagsOverdue() {
        let late = task("Geç", TestCalendar.date(2026, 11, 27, 9))
        let overdue = task("Gecikmiş", TestCalendar.date(2026, 11, 24, 9))
        let result = snapshot([late, overdue])
        XCTAssertEqual(result.next?.title, "Gecikmiş")
        XCTAssertTrue(result.nextIsOverdue)

        let calm = snapshot([late])
        XCTAssertEqual(calm.next?.title, "Geç")
        XCTAssertFalse(calm.nextIsOverdue)
    }

    func testSnapshotMovesTasksToOverdueAfterMidnight() {
        let item = task("Bugünkü", TestCalendar.date(2026, 11, 25, 16))
        XCTAssertEqual(snapshot([item]).today.count, 1)
        let nextDay = snapshot([item], at: TestCalendar.date(2026, 11, 26, 0))
        XCTAssertTrue(nextDay.today.isEmpty)
        XCTAssertEqual(nextDay.overdue.count, 1)
    }

    func testQuoteAndVisitCountsPassThrough() {
        let data = WidgetData(
            tasks: [],
            pendingQuoteCount: 3,
            pendingQuoteTotals: [WidgetMoney(currency: .tl, amount: 1000)],
            unexportedVisitCount: 5
        )
        let result = WidgetSnapshot.make(data: data, at: now, calendar: cal)
        XCTAssertEqual(result.pendingQuoteCount, 3)
        XCTAssertEqual(result.pendingQuoteTotals, [WidgetMoney(currency: .tl, amount: 1000)])
        XCTAssertEqual(result.unexportedVisitCount, 5)
    }

    // MARK: - Zaman çizelgesi

    func testEntryDatesAreNowTaskTimesAndMidnight() {
        let data = WidgetData(tasks: [
            task("A", TestCalendar.date(2026, 11, 25, 16)),
            task("A2", TestCalendar.date(2026, 11, 25, 16)),
            task("Geçmiş", TestCalendar.date(2026, 11, 25, 10)),
            task("B", TestCalendar.date(2026, 11, 25, 18, 30)),
            task("Yarın", TestCalendar.date(2026, 11, 26, 13))
        ])
        let dates = WidgetSnapshot.entryDates(data: data, now: now, calendar: cal)

        XCTAssertEqual(dates, [
            now,
            TestCalendar.date(2026, 11, 25, 16),
            TestCalendar.date(2026, 11, 25, 18, 30),
            TestCalendar.date(2026, 11, 26, 0)
        ])
    }

    func testEntryDatesNeverExceed24HoursAndAreCapped() {
        let tasks = (0..<40).map { task("T\($0)", TestCalendar.date(2026, 11, 25, 14).addingTimeInterval(Double($0 + 1) * 60)) }
        let dates = WidgetSnapshot.entryDates(data: WidgetData(tasks: tasks), now: now, calendar: cal, maxTaskEntries: 20)
        XCTAssertEqual(dates.count, 22)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertLessThanOrEqual(dates.last!.timeIntervalSince(now), 24 * 3600)
        XCTAssertEqual(dates.last, TestCalendar.date(2026, 11, 26, 0))
    }

    func testNextMidnight() {
        XCTAssertEqual(
            WidgetSnapshot.nextMidnight(after: TestCalendar.date(2026, 11, 25, 23), calendar: cal),
            TestCalendar.date(2026, 11, 26, 0)
        )
    }

    func testSampleDataFillsEveryWidget() {
        let result = WidgetSnapshot.make(data: .sample(now: now, calendar: cal), at: now, calendar: cal)
        XCTAssertEqual(result.overdue.count, 2)
        XCTAssertEqual(result.today.count, 3)
        XCTAssertFalse(result.week.isEmpty)
        XCTAssertNotNil(result.next)
        XCTAssertTrue(result.nextIsOverdue)
        XCTAssertEqual(result.pendingQuoteCount, 3)
        XCTAssertEqual(result.unexportedVisitCount, 2)
    }
}

final class WidgetLinkTests: XCTestCase {
    func testRoundTrip() {
        let id = UUID()
        for link in [WidgetLink.task(id), .today, .newVisit] {
            XCTAssertEqual(WidgetLink(url: link.url), link)
        }
        XCTAssertEqual(WidgetLink.task(id).url.absoluteString, "sahasatis://task/\(id.uuidString)")
        XCTAssertEqual(WidgetLink.today.url.absoluteString, "sahasatis://today")
        XCTAssertEqual(WidgetLink.newVisit.url.absoluteString, "sahasatis://visit/new")
    }

    func testInvalidLinksAreRejected() {
        XCTAssertNil(WidgetLink(url: URL(string: "https://example.com/task/abc")!))
        XCTAssertNil(WidgetLink(url: URL(string: "sahasatis://task/not-a-uuid")!))
        XCTAssertNil(WidgetLink(url: URL(string: "sahasatis://visit/edit")!))
        XCTAssertNil(WidgetLink(url: URL(string: "sahasatis://unknown")!))
    }
}

final class WidgetFormatTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 14)

    private func task(_ due: Date) -> WidgetTask {
        WidgetTask(id: UUID(), title: "T", customerName: nil, dueDate: due)
    }

    func testDueText() {
        let today = task(TestCalendar.date(2026, 11, 25, 16))
        XCTAssertEqual(WidgetFormat.dueText(for: today, now: now, calendar: cal), "Bugün \(AppFormat.time(today.dueDate))")

        let tomorrow = task(TestCalendar.date(2026, 11, 26, 9))
        XCTAssertEqual(WidgetFormat.dueText(for: tomorrow, now: now, calendar: cal), "Yarın \(AppFormat.time(tomorrow.dueDate))")

        let later = task(TestCalendar.date(2026, 11, 28, 9))
        XCTAssertTrue(WidgetFormat.dueText(for: later, now: now, calendar: cal).hasSuffix(AppFormat.time(later.dueDate)))

        let overdue = task(TestCalendar.date(2026, 11, 23, 9))
        let text = WidgetFormat.dueText(for: overdue, now: now, calendar: cal)
        XCTAssertTrue(text.hasPrefix("Gecikmiş · "), text)
        XCTAssertTrue(text.contains("Kas"), text)
    }

    func testDayTitle() {
        XCTAssertEqual(WidgetFormat.dayTitle(TestCalendar.date(2026, 11, 25, 0), now: now, calendar: cal), "Bugün")
        XCTAssertEqual(WidgetFormat.dayTitle(TestCalendar.date(2026, 11, 26, 0), now: now, calendar: cal), "Yarın")
        XCTAssertTrue(WidgetFormat.dayTitle(TestCalendar.date(2026, 11, 28, 0), now: now, calendar: cal).contains("Kas"))
    }

    func testQuoteAndVisitSummaries() {
        XCTAssertEqual(WidgetFormat.quoteSummary(count: 0, totals: []), "Bekleyen teklif yok")
        XCTAssertEqual(WidgetFormat.quoteSummary(count: 2, totals: []), "2 teklif bekliyor")
        XCTAssertEqual(
            WidgetFormat.quoteSummary(count: 3, totals: [WidgetMoney(currency: .tl, amount: 480_000)]),
            "3 teklif bekliyor · 480.000 ₺"
        )
        XCTAssertEqual(WidgetFormat.unexportedText(0), "Tüm ziyaretler aktarıldı")
        XCTAssertEqual(WidgetFormat.unexportedText(2), "2 ziyaret CRM'e aktarılmadı")
    }
}

/// Depodan okuma, onay kutusu, uygulama bağlantıları, widget yenileme.
@MainActor
final class WidgetIntegrationTests: XCTestCase {
    private let now = TestCalendar.date(2026, 11, 25, 14)

    func testLoaderReadsOpenTasksQuotesAndUnexportedVisits() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Örnek Makina A.Ş.")
        let open = FollowUpTask(title: "Açık", dueDate: now)
        let done = FollowUpTask(title: "Bitti", dueDate: now)
        try env.repos.tasks.add(open, customer: customer, quote: nil, visit: nil)
        try env.repos.tasks.add(done, customer: customer, quote: nil, visit: nil)
        try env.repos.tasks.complete(done, at: now)

        func quote(_ status: QuoteStatus, _ currency: Currency, price: Double) throws {
            let quote = Quote(currency: currency, status: status)
            try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
            try env.repos.quoteItems.add(QuoteItem(quantity: 2, unitPrice: price), to: quote)
        }
        try quote(.sent, .tl, price: 1000)
        try quote(.followUp, .tl, price: 500)
        try quote(.sent, .usd, price: 100)
        try quote(.draft, .tl, price: 9999)
        try quote(.won, .tl, price: 9999)

        let exported = Visit(date: now)
        try env.repos.visits.add(exported, customer: customer, contacts: [], opportunity: nil)
        try env.repos.visits.markExported([exported], at: now)
        try env.repos.visits.add(Visit(date: now.addingTimeInterval(-86_400 * 3)), customer: customer, contacts: [], opportunity: nil)

        let data = try WidgetDataLoader.load(repositories: env.repos)

        XCTAssertEqual(data.tasks.map(\.title), ["Açık"])
        XCTAssertEqual(data.tasks.first?.customerName, "Örnek Makina A.Ş.")
        XCTAssertEqual(data.pendingQuoteCount, 3)
        XCTAssertEqual(data.pendingQuoteTotals, [
            WidgetMoney(currency: .tl, amount: 3000),
            WidgetMoney(currency: .usd, amount: 200)
        ])
        XCTAssertEqual(data.unexportedVisitCount, 1, "Önceki günlerin aktarılmamış ziyareti de sayılır")
    }

    func testCompleterMarksTaskDoneOnce() throws {
        let env = try TestEnv()
        let task = FollowUpTask(title: "Yap", dueDate: now)
        try env.repos.tasks.add(task, customer: nil, quote: nil, visit: nil)

        XCTAssertTrue(try WidgetTaskCompleter.complete(taskID: task.id, repositories: env.repos, now: now))
        XCTAssertTrue(task.isDone)
        XCTAssertEqual(task.doneAt, now)
        XCTAssertFalse(try WidgetTaskCompleter.complete(taskID: task.id, repositories: env.repos, now: now), "Zaten tamam")
        XCTAssertFalse(try WidgetTaskCompleter.complete(taskID: UUID(), repositories: env.repos, now: now), "Bilinmeyen görev")
    }

    func testIntentCarriesTaskID() {
        let id = UUID()
        XCTAssertEqual(CompleteTaskIntent(taskID: id).taskID, id.uuidString)
        XCTAssertEqual(TaskNotificationID.make(for: id), "task.\(id.uuidString)")
    }

    private func makeContext(_ env: TestEnv) -> AppContext {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppContext(
            repositories: env.repos,
            settings: SahaSatis.AppSettings(defaults: defaults),
            makeSpeechEngine: { MockSpeechEngine() },
            notificationScheduler: MockNotificationScheduler()
        )
    }

    func testTaskLinkOpensCustomerOrToday() throws {
        let env = try TestEnv()
        let context = makeContext(env)
        let customer = try env.makeCustomer()
        let task = FollowUpTask(title: "Yap", dueDate: now)
        try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
        let orphan = FollowUpTask(title: "Müşterisiz", dueDate: now)
        try env.repos.tasks.add(orphan, customer: nil, quote: nil, visit: nil)

        context.handle(url: WidgetLink.task(task.id).url)
        XCTAssertEqual(context.customerToOpen, customer.id)
        XCTAssertEqual(context.requestedTab, .customers)

        context.customerToOpen = nil
        context.handle(url: WidgetLink.task(orphan.id).url)
        XCTAssertNil(context.customerToOpen)
        XCTAssertEqual(context.requestedTab, .today)

        context.requestedTab = nil
        context.handle(url: WidgetLink.task(UUID()).url)
        XCTAssertEqual(context.requestedTab, .today)
    }

    func testVisitAndTodayLinks() throws {
        let env = try TestEnv()
        let context = makeContext(env)
        XCTAssertFalse(context.presentVisitForm)

        context.handle(url: WidgetLink.newVisit.url)
        XCTAssertTrue(context.presentVisitForm)

        context.handle(url: WidgetLink.today.url)
        XCTAssertEqual(context.requestedTab, .today)

        context.requestedTab = nil
        context.handle(url: URL(string: "https://example.com")!)
        XCTAssertNil(context.requestedTab)
    }

    func testReloaderCoalescesDataChanges() async throws {
        var reloads = 0
        let reloader = WidgetReloader(delay: .milliseconds(50)) { reloads += 1 }
        reloader.start()

        for _ in 0..<3 {
            NotificationCenter.default.post(name: .appDataDidChange, object: nil)
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(reloads, 1, "Art arda değişiklikler tek yenileme")

        NotificationCenter.default.post(name: .appDataDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(reloads, 2)

        reloader.reloadNow()
        XCTAssertEqual(reloads, 3)
    }

    func testRepositorySaveTriggersReload() async throws {
        let env = try TestEnv()
        var reloads = 0
        let reloader = WidgetReloader(delay: .milliseconds(50)) { reloads += 1 }
        reloader.start()

        try env.repos.tasks.add(FollowUpTask(title: "Yeni", dueDate: now), customer: nil, quote: nil, visit: nil)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertGreaterThanOrEqual(reloads, 1)
    }
}
