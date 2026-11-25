import XCTest
@testable import SahaSatis

@MainActor
final class VisitServiceTests: XCTestCase {
    private let reminderMinutes = 9 * 60

    private func makeService(_ env: TestEnv) -> VisitService {
        VisitService(repositories: env.repos, reminderMinutes: reminderMinutes, calendar: TestCalendar.utc)
    }

    func testNewVisitStartsNotExportedAndLinksCustomerAndContacts() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet Yılmaz")
        try env.repos.contacts.add(contact, to: customer)

        var draft = VisitDraft()
        draft.date = TestCalendar.date(2026, 11, 24, 14)
        draft.type = .phone
        draft.summary = "Telefonda görüşüldü"
        draft.transcript = "ham metin"

        let visit = try makeService(env).save(draft, customer: customer, contacts: [contact], existing: nil)

        XCTAssertFalse(visit.exportedToCRM)
        XCTAssertNil(visit.exportedAt)
        XCTAssertEqual(visit.type, .phone)
        XCTAssertEqual(visit.summary, "Telefonda görüşüldü")
        XCTAssertEqual(visit.transcript, "ham metin")
        XCTAssertEqual(visit.customer?.id, customer.id)
        XCTAssertEqual(visit.contacts?.map(\.id), [contact.id])
        XCTAssertEqual(visit.ownerUserID, "test-user")
    }

    func testSavingUpdatesCustomersLastVisitDate() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        XCTAssertNil(customer.lastVisitDate)
        let service = makeService(env)

        var older = VisitDraft()
        older.date = TestCalendar.date(2026, 10, 1)
        try service.save(older, customer: customer, contacts: [], existing: nil)
        XCTAssertEqual(customer.lastVisitDate, TestCalendar.date(2026, 10, 1))

        var newer = VisitDraft()
        newer.date = TestCalendar.date(2026, 11, 20)
        try service.save(newer, customer: customer, contacts: [], existing: nil)
        XCTAssertEqual(customer.lastVisitDate, TestCalendar.date(2026, 11, 20))

        XCTAssertEqual(
            try env.repos.visits.visits(for: customer).map(\.date),
            [TestCalendar.date(2026, 11, 20), TestCalendar.date(2026, 10, 1)],
            "Ziyaret geçmişi yeniden eskiye sıralı"
        )
    }

    func testNextStepDateCreatesLinkedFollowUpTask() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()

        var draft = VisitDraft()
        draft.nextStep = "Teklif hazırlanacak"
        draft.nextStepDate = TestCalendar.date(2026, 11, 28)
        let visit = try makeService(env).save(draft, customer: customer, contacts: [], existing: nil)

        let tasks = try env.repos.tasks.fetchAll()
        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.source, .visitNextStep)
        XCTAssertEqual(task.title, "Teklif hazırlanacak")
        XCTAssertEqual(task.dueDate, TestCalendar.date(2026, 11, 28, 9), "Hatırlatma saatinde (09:00)")
        XCTAssertEqual(task.customer?.id, customer.id)
        XCTAssertEqual(task.visit?.id, visit.id)
        XCTAssertFalse(task.isDone)
    }

    func testNoNextStepDateMeansNoTask() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()

        var draft = VisitDraft()
        draft.nextStep = "Sadece not"
        try makeService(env).save(draft, customer: customer, contacts: [], existing: nil)

        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
    }

    func testEmptyNextStepTextFallsBackToDefaultTitle() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()

        var draft = VisitDraft()
        draft.nextStepDate = TestCalendar.date(2026, 12, 1)
        try makeService(env).save(draft, customer: customer, contacts: [], existing: nil)

        XCTAssertEqual(try env.repos.tasks.fetchAll().first?.title, "Sonraki adım")
    }

    func testEditingUpdatesExistingTaskInsteadOfDuplicating() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let service = makeService(env)

        var draft = VisitDraft()
        draft.nextStep = "İlk"
        draft.nextStepDate = TestCalendar.date(2026, 11, 28)
        let visit = try service.save(draft, customer: customer, contacts: [], existing: nil)

        draft.nextStep = "Değişti"
        draft.nextStepDate = TestCalendar.date(2026, 12, 5)
        draft.summary = "düzenlendi"
        try service.save(draft, customer: customer, contacts: [], existing: visit)

        let tasks = try env.repos.tasks.fetchAll()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.title, "Değişti")
        XCTAssertEqual(tasks.first?.dueDate, TestCalendar.date(2026, 12, 5, 9))
        XCTAssertEqual(try env.repos.visits.fetchAll().count, 1)
        XCTAssertEqual(visit.summary, "düzenlendi")
    }

    func testClearingNextStepDateRemovesOpenTaskButKeepsCompletedOne() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let service = makeService(env)

        var draft = VisitDraft()
        draft.nextStepDate = TestCalendar.date(2026, 11, 28)
        let visit = try service.save(draft, customer: customer, contacts: [], existing: nil)

        draft.nextStepDate = nil
        try service.save(draft, customer: customer, contacts: [], existing: visit)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)

        // Tamamlanmış görev silinmez ve yeniden oluşturulmaz.
        draft.nextStepDate = TestCalendar.date(2026, 11, 30)
        try service.save(draft, customer: customer, contacts: [], existing: visit)
        let task = try XCTUnwrap(try env.repos.tasks.fetchAll().first)
        try env.repos.tasks.complete(task, at: Date())
        try service.save(draft, customer: customer, contacts: [], existing: visit)
        XCTAssertEqual(try env.repos.tasks.fetchAll().count, 1)
        XCTAssertTrue(try XCTUnwrap(try env.repos.tasks.fetchAll().first).isDone)
    }

    func testNewVisitClosesOpenVisitFrequencyTasksOfThatCustomerOnly() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("A")
        let other = try env.makeCustomer("B")
        let mine = FollowUpTask(title: "A'yı ziyaret et", source: .visitFrequency)
        let theirs = FollowUpTask(title: "B'yi ziyaret et", source: .visitFrequency)
        let manual = FollowUpTask(title: "Elle", source: .manual)
        try env.repos.tasks.add(mine, customer: customer, quote: nil, visit: nil)
        try env.repos.tasks.add(theirs, customer: other, quote: nil, visit: nil)
        try env.repos.tasks.add(manual, customer: customer, quote: nil, visit: nil)

        try makeService(env).save(VisitDraft(), customer: customer, contacts: [], existing: nil)

        XCTAssertTrue(mine.isDone)
        XCTAssertFalse(theirs.isDone)
        XCTAssertFalse(manual.isDone)
    }

    func testEditingChangesFieldsAndContactsButNotExportFlag() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let a = Contact(fullName: "A")
        let b = Contact(fullName: "B")
        try env.repos.contacts.add(a, to: customer)
        try env.repos.contacts.add(b, to: customer)
        let service = makeService(env)

        var draft = VisitDraft()
        let visit = try service.save(draft, customer: customer, contacts: [a], existing: nil)

        draft.type = .online
        draft.date = TestCalendar.date(2026, 9, 9)
        try service.save(draft, customer: customer, contacts: [b], existing: visit)

        XCTAssertEqual(visit.type, .online)
        XCTAssertEqual(visit.date, TestCalendar.date(2026, 9, 9))
        XCTAssertEqual(visit.contacts?.map(\.id), [b.id])
        XCTAssertFalse(visit.exportedToCRM)
    }

    func testDeleteRemovesOpenNextStepTaskAndVisit() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let service = makeService(env)

        var draft = VisitDraft()
        draft.nextStepDate = TestCalendar.date(2026, 11, 28)
        let visit = try service.save(draft, customer: customer, contacts: [], existing: nil)

        try service.delete(visit)

        XCTAssertTrue(try env.repos.visits.fetchAll().isEmpty)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
        XCTAssertNotNil(try env.repos.customers.customer(id: customer.id))
    }
}
