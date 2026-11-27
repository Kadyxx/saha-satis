import XCTest
@testable import SahaSatis

/// Yarım kalan ziyaret notu: taslağın saklanması, geri yüklenmesi ve silinmesi.
@MainActor
final class VisitDraftTests: XCTestCase {
    private func makeModel(
        _ env: TestEnv,
        store: VisitDraftStore,
        customer: Customer?,
        visit: Visit? = nil,
        restoring: VisitFormDraft? = nil,
        engine: MockSpeechEngine = MockSpeechEngine(),
        delay: Duration = .milliseconds(20)
    ) -> VisitFormModel {
        VisitFormModel(
            repositories: env.repos, reminderMinutes: 9 * 60, engine: engine,
            customer: customer, visit: visit,
            draftStore: store, draftDelay: delay, restoring: restoring
        )
    }

    private func addVisit(_ env: TestEnv, to customer: Customer, summary: String) throws -> Visit {
        let visit = Visit(summary: summary)
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)
        return visit
    }

    func testUntouchedFormIsNotSaved() throws {
        let env = try TestEnv()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: try env.makeCustomer())
        XCTAssertFalse(model.hasUnsavedChanges)
        model.flushDraft()
        XCTAssertNil(store.draft)
        XCTAssertEqual(store.saveCount, 0)
    }

    func testChoosingOnlyCustomerIsNotADraft() throws {
        let env = try TestEnv()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: nil)
        model.customer = try env.makeCustomer()
        model.customerChanged()
        XCTAssertFalse(model.hasUnsavedChanges)
        model.flushDraft()
        XCTAssertNil(store.draft)
    }

    func testTypedNoteIsSaved() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: customer)
        model.note = "PLC arızası konuşuldu"
        let savedAt = Date(timeIntervalSince1970: 1_800_000_000)
        model.flushDraft(now: savedAt)

        XCTAssertTrue(model.hasUnsavedChanges)
        XCTAssertEqual(store.draft?.note, "PLC arızası konuşuldu")
        XCTAssertEqual(store.draft?.customerID, customer.id)
        XCTAssertEqual(store.draft?.customerName, customer.name)
        XCTAssertEqual(store.draft?.savedAt, savedAt)
        XCTAssertNil(store.draft?.nextStepDate)
    }

    func testRevertingChangesDeletesOwnDraft() throws {
        let env = try TestEnv()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: try env.makeCustomer())
        model.note = "x"
        model.flushDraft()
        XCTAssertNotNil(store.draft)
        model.note = ""
        model.flushDraft()
        XCTAssertNil(store.draft)
    }

    func testCleanFormDoesNotDeleteAnotherDraft() throws {
        let env = try TestEnv()
        var other = VisitFormDraft()
        other.note = "başka formun notu"
        let store = InMemoryVisitDraftStore(draft: other)
        let model = makeModel(env, store: store, customer: try env.makeCustomer())
        model.flushDraft()
        model.discardDraft()
        XCTAssertEqual(store.draft, other)
    }

    func testDebouncedSaveWritesOnce() async throws {
        let env = try TestEnv()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: try env.makeCustomer(), delay: .milliseconds(100))
        for text in ["a", "ab", "abc"] {
            model.note = text
            model.scheduleDraftSave()
        }
        XCTAssertNil(store.draft, "bekleme dolmadan yazılmamalı")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(store.saveCount, 1)
        XCTAssertEqual(store.draft?.note, "abc")
    }

    func testSaveDeletesDraftAndStopsWriting() async throws {
        let env = try TestEnv()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: try env.makeCustomer())
        model.note = "kaydedilecek not"
        model.flushDraft()
        model.scheduleDraftSave()

        XCTAssertTrue(model.save())
        XCTAssertNil(store.draft)
        model.note = "kayıttan sonra gelen değişiklik"
        model.scheduleDraftSave()
        model.flushDraft()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(store.draft)
        XCTAssertTrue(model.isFinished)
    }

    func testDiscardDeletesDraft() throws {
        let env = try TestEnv()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: try env.makeCustomer())
        model.note = "vazgeçilecek"
        model.flushDraft()
        model.discardDraft()
        XCTAssertNil(store.draft)
        XCTAssertFalse(model.hasUnsavedChanges)
    }

    func testRestoreFillsEveryField() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet Yılmaz")
        try env.repos.contacts.add(contact, to: customer)
        let opportunity = Opportunity(title: "Hat 3")
        try env.repos.opportunities.add(opportunity, customer: customer)

        let store = InMemoryVisitDraftStore()
        let first = makeModel(env, store: store, customer: customer)
        first.toggleContact(contact)
        first.type = .phone
        first.topic = "Konu"
        first.note = "Not"
        first.nextStep = "Teklif"
        first.hasNextStepDate = true
        first.nextStepDate = Date(timeIntervalSince1970: 1_800_000_000)
        first.opportunityLink = .existing(opportunity.id)
        first.flushDraft()
        let draft = try XCTUnwrap(store.load())

        let restored = makeModel(env, store: store, customer: nil, restoring: draft)
        XCTAssertEqual(restored.customer?.id, customer.id)
        XCTAssertEqual(restored.selectedContactIDs, [contact.id])
        XCTAssertEqual(restored.type, .phone)
        XCTAssertEqual(restored.topic, "Konu")
        XCTAssertEqual(restored.note, "Not")
        XCTAssertEqual(restored.nextStep, "Teklif")
        XCTAssertTrue(restored.hasNextStepDate)
        XCTAssertEqual(restored.nextStepDate, first.nextStepDate)
        XCTAssertEqual(restored.opportunityLink, .existing(opportunity.id))
        XCTAssertTrue(restored.hasUnsavedChanges)

        XCTAssertTrue(restored.save())
        XCTAssertNil(store.draft)
        XCTAssertEqual(try env.repos.visits.visits(for: customer).count, 1)
    }

    func testRestoreSkipsDeletedRecords() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        var draft = VisitFormDraft()
        draft.customerID = customer.id
        draft.contactIDs = [UUID()]
        draft.opportunityID = UUID()
        draft.note = "Not"

        let model = makeModel(env, store: InMemoryVisitDraftStore(draft: draft), customer: nil, restoring: draft)
        XCTAssertEqual(model.customer?.id, customer.id)
        XCTAssertTrue(model.selectedContactIDs.isEmpty)
        XCTAssertEqual(model.opportunityLink, .none)
        XCTAssertEqual(model.note, "Not")
    }

    func testDraftOfEditedVisitUpdatesSameVisit() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let visit = try addVisit(env, to: customer, summary: "eski not")
        let store = InMemoryVisitDraftStore()
        let editing = makeModel(env, store: store, customer: nil, visit: visit)
        XCTAssertFalse(editing.hasUnsavedChanges)
        editing.note = "yeni not"
        editing.flushDraft()
        let draft = try XCTUnwrap(store.draft)
        XCTAssertEqual(draft.existingVisitID, visit.id)
        XCTAssertEqual(visit.summary, "eski not", "taslak ziyareti değiştirmez")

        let restored = makeModel(env, store: store, customer: nil, visit: visit, restoring: draft)
        XCTAssertEqual(restored.note, "yeni not")
        XCTAssertTrue(restored.save())
        XCTAssertEqual(visit.summary, "yeni not")
        XCTAssertEqual(try env.repos.visits.fetchAll().count, 1)
    }

    func testClearingNoteOfEditedVisitIsAChange() throws {
        let env = try TestEnv()
        let visit = try addVisit(env, to: try env.makeCustomer(), summary: "eski not")
        let model = makeModel(env, store: InMemoryVisitDraftStore(), customer: nil, visit: visit)
        model.note = ""
        XCTAssertTrue(model.hasUnsavedChanges)
    }

    func testLiveSpeechTextIsIncludedBeforeCommit() async throws {
        let env = try TestEnv()
        let engine = MockSpeechEngine()
        let store = InMemoryVisitDraftStore()
        let model = makeModel(env, store: store, customer: try env.makeCustomer(), engine: engine)
        model.note = "Yazılı."
        await model.voice.start()
        engine.emit("konuşulan henüz teslim edilmedi")
        model.flushDraft()

        XCTAssertEqual(store.draft?.note, "Yazılı. konuşulan henüz teslim edilmedi")
        XCTAssertEqual(store.draft?.rawTranscript, "konuşulan henüz teslim edilmedi")
        XCTAssertEqual(model.note, "Yazılı.", "formdaki not değişmez")
        model.voice.stop()
    }

    func testFileStoreRoundTripAndDelete() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "draft-\(UUID().uuidString)/visit-draft.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = FileVisitDraftStore(url: url)
        XCTAssertNil(store.load())

        var draft = VisitFormDraft()
        draft.customerID = UUID()
        draft.note = "Türkçe: ğüşıöç İ"
        draft.nextStepDate = Date(timeIntervalSince1970: 1_800_000_000)
        draft.savedAt = Date(timeIntervalSince1970: 1_800_000_100)
        try store.save(draft)
        XCTAssertEqual(FileVisitDraftStore(url: url).load(), draft)

        store.delete()
        XCTAssertNil(store.load())
    }

    func testDamagedFileIsIgnored() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "draft-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("bozuk".utf8).write(to: url)
        XCTAssertNil(FileVisitDraftStore(url: url).load())
    }

    func testAppContextAsksResumesAndDiscards() throws {
        let env = try TestEnv()
        var draft = VisitFormDraft()
        draft.note = "yarım"
        func makeContext(_ store: VisitDraftStore) -> AppContext {
            let name = "test-\(UUID().uuidString)"
            return AppContext(
                repositories: env.repos,
                settings: SahaSatis.AppSettings(defaults: UserDefaults(suiteName: name)!),
                makeSpeechEngine: { MockSpeechEngine() },
                notificationScheduler: MockNotificationScheduler(),
                draftStore: store
            )
        }

        let store = InMemoryVisitDraftStore(draft: draft)
        let context = makeContext(store)
        XCTAssertEqual(context.pendingDraft, draft)
        // Soru yanıtlanmadan widget'tan yeni ziyaret açılmaz.
        context.handle(url: WidgetLink.newVisit.url)
        XCTAssertFalse(context.presentVisitForm)

        context.resumePendingDraft()
        XCTAssertNil(context.pendingDraft)
        XCTAssertEqual(context.resumingDraft, draft)
        XCTAssertEqual(store.draft, draft, "form kaydedilene kadar taslak durur")

        let discarding = makeContext(store)
        discarding.discardPendingDraft()
        XCTAssertNil(discarding.pendingDraft)
        XCTAssertNil(store.draft)
        XCTAssertNil(makeContext(store).pendingDraft)
    }
}
