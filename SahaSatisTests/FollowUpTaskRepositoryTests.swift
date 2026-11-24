import XCTest
@testable import SahaSatis

@MainActor
final class FollowUpTaskRepositoryTests: XCTestCase {
    private let cal = TestCalendar.utc

    func testAddLinksRelationshipsAndSource() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let visit = Visit()
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)

        let task = FollowUpTask(title: "Teklif hazırla", dueDate: TestCalendar.date(2026, 11, 28), source: .visitNextStep)
        try env.repos.tasks.add(task, customer: customer, quote: nil, visit: visit)

        let stored = try XCTUnwrap(try env.repos.tasks.task(id: task.id))
        XCTAssertEqual(stored.customer?.id, customer.id)
        XCTAssertEqual(stored.visit?.id, visit.id)
        XCTAssertEqual(stored.source, .visitNextStep)
        XCTAssertFalse(stored.isDone)
        XCTAssertEqual(try env.repos.tasks.tasks(for: customer).count, 1)
    }

    func testOpenOverdueAndDayQueries() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let now = TestCalendar.date(2026, 11, 24, 10)

        let overdue = FollowUpTask(title: "gecikmiş", dueDate: TestCalendar.date(2026, 11, 20, 9))
        let today = FollowUpTask(title: "bugün", dueDate: TestCalendar.date(2026, 11, 24, 9))
        let tomorrow = FollowUpTask(title: "yarın", dueDate: TestCalendar.date(2026, 11, 25, 9))
        let done = FollowUpTask(title: "bitti", dueDate: TestCalendar.date(2026, 11, 19, 9))
        for task in [tomorrow, today, overdue, done] {
            try env.repos.tasks.add(task, customer: customer, quote: nil, visit: nil)
        }
        try env.repos.tasks.complete(done, at: now)

        XCTAssertEqual(try env.repos.tasks.openTasks().map(\.title), ["gecikmiş", "bugün", "yarın"])
        XCTAssertEqual(try env.repos.tasks.overdueTasks(asOf: now, calendar: cal).map(\.title), ["gecikmiş"])
        XCTAssertEqual(try env.repos.tasks.openTasks(on: now, calendar: cal).map(\.title), ["bugün"])
    }

    func testCompleteSetsDoneAndTimestamp() throws {
        let env = try TestEnv()
        let task = FollowUpTask(title: "ara")
        try env.repos.tasks.add(task, customer: nil, quote: nil, visit: nil)
        let when = TestCalendar.date(2026, 11, 24, 15)

        try env.repos.tasks.complete(task, at: when)

        XCTAssertTrue(task.isDone)
        XCTAssertEqual(task.doneAt, when)
        XCTAssertTrue(try env.repos.tasks.openTasks().isEmpty)
    }

    func testPostponeMovesDueDate() throws {
        let env = try TestEnv()
        let task = FollowUpTask(title: "ara", dueDate: TestCalendar.date(2026, 11, 24))
        try env.repos.tasks.add(task, customer: nil, quote: nil, visit: nil)

        try env.repos.tasks.postpone(task, to: TestCalendar.date(2026, 11, 27))

        XCTAssertEqual(task.dueDate, TestCalendar.date(2026, 11, 27))
        XCTAssertFalse(task.isDone)
    }

    func testNextOpenTasksRespectsLimitAndOrder() throws {
        let env = try TestEnv()
        for day in 1...5 {
            let task = FollowUpTask(title: "g\(day)", dueDate: TestCalendar.date(2026, 12, 6 - day))
            try env.repos.tasks.add(task, customer: nil, quote: nil, visit: nil)
        }

        XCTAssertEqual(try env.repos.tasks.nextOpenTasks(limit: 3).map(\.title), ["g5", "g4", "g3"])
        XCTAssertTrue(try env.repos.tasks.nextOpenTasks(limit: 0).isEmpty)
    }

    func testCancelOpenTasksForQuoteKeepsDoneAndOthers() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let quote = Quote(quoteNumber: "T-1")
        let otherQuote = Quote(quoteNumber: "T-2")
        try env.repos.quotes.add(quote, customer: customer, opportunity: nil)
        try env.repos.quotes.add(otherQuote, customer: customer, opportunity: nil)

        let open = FollowUpTask(title: "3. gün takibi", source: .quoteFollowUp)
        let finished = FollowUpTask(title: "yapıldı", source: .quoteFollowUp)
        let other = FollowUpTask(title: "başka teklif", source: .quoteFollowUp)
        try env.repos.tasks.add(open, customer: customer, quote: quote, visit: nil)
        try env.repos.tasks.add(finished, customer: customer, quote: quote, visit: nil)
        try env.repos.tasks.add(other, customer: customer, quote: otherQuote, visit: nil)
        try env.repos.tasks.complete(finished, at: Date())

        try env.repos.tasks.cancelOpenTasks(for: quote)

        XCTAssertEqual(Set(try env.repos.tasks.fetchAll().map(\.title)), ["yapıldı", "başka teklif"])
    }

    func testDeleteTask() throws {
        let env = try TestEnv()
        let task = FollowUpTask(title: "sil")
        try env.repos.tasks.add(task, customer: nil, quote: nil, visit: nil)
        try env.repos.tasks.delete(task)
        XCTAssertNil(try env.repos.tasks.task(id: task.id))
    }
}
