import XCTest
@testable import SahaSatis

@MainActor
final class VoiceNoteControllerTests: XCTestCase {
    private func makeController(_ engine: MockSpeechEngine) -> (VoiceNoteController, Box) {
        let controller = VoiceNoteController(engine: engine)
        let box = Box()
        controller.onCommit = { box.segments.append($0) }
        return (controller, box)
    }

    final class Box {
        var segments: [String] = []
    }

    func testStartRecordsAndShowsLiveText() async {
        let engine = MockSpeechEngine()
        let (controller, _) = makeController(engine)

        await controller.start()
        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(engine.startCount, 1)

        engine.emit("merhaba")
        XCTAssertEqual(controller.partialText, "merhaba")
        engine.emit("merhaba dünya")
        XCTAssertEqual(controller.partialText, "merhaba dünya", "Motor oturumun tüm metnini gönderir")
    }

    func testPauseCommitsTextAndResumeStartsNewSession() async {
        let engine = MockSpeechEngine()
        let (controller, box) = makeController(engine)

        await controller.start()
        engine.emit("birinci parça")
        controller.pause()

        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(box.segments, ["birinci parça"])
        XCTAssertEqual(controller.partialText, "")
        XCTAssertEqual(engine.stopCount, 1)

        await controller.start()
        XCTAssertEqual(controller.state, .recording)
        XCTAssertEqual(engine.startCount, 2)
        engine.emit("ikinci parça")
        controller.stop()

        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(box.segments, ["birinci parça", "ikinci parça"])
    }

    func testStopWithoutSpeechCommitsNothing() async {
        let engine = MockSpeechEngine()
        let (controller, box) = makeController(engine)
        await controller.start()
        controller.stop()
        XCTAssertTrue(box.segments.isEmpty)
        XCTAssertEqual(controller.state, .idle)
    }

    func testPermissionDeniedLeavesKeyboardPathOpen() async {
        let engine = MockSpeechEngine(permissionGranted: false)
        let (controller, _) = makeController(engine)

        await controller.start()

        XCTAssertEqual(controller.state, .permissionDenied)
        XCTAssertEqual(engine.startCount, 0)
    }

    func testUnavailableRecognizer() async {
        let engine = MockSpeechEngine(isAvailable: false)
        let (controller, _) = makeController(engine)

        await controller.start()

        XCTAssertEqual(controller.state, .unavailable)
        XCTAssertEqual(engine.startCount, 0)
    }

    func testStartErrorBecomesFailedState() async {
        let engine = MockSpeechEngine()
        engine.startError = SpeechEngineError.unavailable
        let (controller, _) = makeController(engine)

        await controller.start()

        if case .failed = controller.state {} else {
            XCTFail("failed durumu bekleniyordu: \(controller.state)")
        }
    }

    func testEngineFinishingSessionRestartsAutomaticallyForLongRecordings() async {
        let engine = MockSpeechEngine()
        let (controller, box) = makeController(engine)

        await controller.start()
        engine.emit("ilk dakika")
        engine.finish(nil)

        XCTAssertEqual(box.segments, ["ilk dakika"])
        XCTAssertEqual(controller.state, .recording, "Kullanıcı durdurmadıkça kayıt sürer")
        XCTAssertEqual(engine.startCount, 2)

        engine.emit("ikinci dakika")
        controller.stop()
        XCTAssertEqual(box.segments, ["ilk dakika", "ikinci dakika"])
    }

    func testRepeatedInstantFailuresStopInsteadOfLooping() async {
        let engine = MockSpeechEngine()
        let (controller, _) = makeController(engine)

        await controller.start()
        for _ in 0..<3 {
            engine.finish(SpeechEngineError.unavailable)
        }

        if case .failed = controller.state {} else {
            XCTFail("failed durumu bekleniyordu: \(controller.state)")
        }
        XCTAssertLessThanOrEqual(engine.startCount, 3)
    }
}

@MainActor
final class VisitFormModelTests: XCTestCase {
    private func makeModel(
        _ env: TestEnv,
        engine: MockSpeechEngine = MockSpeechEngine(),
        customer: Customer?,
        visit: Visit? = nil,
        seed: VisitFormSeed = VisitFormSeed()
    ) -> VisitFormModel {
        VisitFormModel(
            repositories: env.repos,
            reminderMinutes: 9 * 60,
            engine: engine,
            customer: customer,
            visit: visit,
            seed: seed
        )
    }

    func testPreselectedCustomerLoadsContactsAndSeedSelection() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try env.repos.contacts.add(Contact(fullName: "Ahmet"), to: customer)
        try env.repos.contacts.add(Contact(fullName: "Ayşe"), to: customer)

        let model = makeModel(env, customer: customer, seed: VisitFormSeed(selectFirstContacts: 1))

        XCTAssertEqual(model.customer?.id, customer.id)
        XCTAssertEqual(model.contacts.count, 2)
        XCTAssertEqual(model.selectedContactIDs.count, 1)
        XCTAssertEqual(model.type, .visit)
        XCTAssertTrue(model.canSave)
    }

    func testCannotSaveWithoutCustomer() throws {
        let env = try TestEnv()
        let model = makeModel(env, customer: nil)
        XCTAssertFalse(model.canSave)
        XCTAssertFalse(model.save())
        XCTAssertTrue(try env.repos.visits.fetchAll().isEmpty)
    }

    func testChangingCustomerResetsContactSelection() throws {
        let env = try TestEnv()
        let first = try env.makeCustomer("Birinci")
        let second = try env.makeCustomer("İkinci")
        let contact = Contact(fullName: "Ahmet")
        try env.repos.contacts.add(contact, to: first)
        try env.repos.contacts.add(Contact(fullName: "Mehmet"), to: second)

        let model = makeModel(env, customer: first)
        model.toggleContact(contact)
        XCTAssertEqual(model.selectedContactIDs, [contact.id])

        model.customer = second
        model.customerChanged()

        XCTAssertEqual(model.contacts.map(\.fullName), ["Mehmet"])
        XCTAssertTrue(model.selectedContactIDs.isEmpty)
    }

    func testDictationAppendsToNoteAndKeepsRawTranscriptSeparate() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = makeModel(env, customer: customer)

        model.appendDictation("birinci cümle")
        model.appendDictation("ikinci cümle")
        XCTAssertEqual(model.note, "birinci cümle ikinci cümle")
        XCTAssertEqual(model.rawTranscript, "birinci cümle ikinci cümle")

        model.note = "elle düzenlenmiş not"
        XCTAssertEqual(model.rawTranscript, "birinci cümle ikinci cümle", "Ham metin düzenlemeden etkilenmez")
    }

    func testVoiceFlowFeedsNoteAndSaveStoresBothTexts() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let engine = MockSpeechEngine()
        let model = makeModel(env, engine: engine, customer: customer)

        await model.voice.start()
        engine.emit("PLC yenileme teklifi istendi")
        model.voice.pause()
        XCTAssertEqual(model.note, "PLC yenileme teklifi istendi")

        model.note += " (düzeltildi)"
        XCTAssertTrue(model.save())

        let visit = try XCTUnwrap(try env.repos.visits.visits(for: customer).first)
        XCTAssertEqual(visit.summary, "PLC yenileme teklifi istendi (düzeltildi)")
        XCTAssertEqual(visit.transcript, "PLC yenileme teklifi istendi")
        XCTAssertFalse(visit.exportedToCRM)
    }

    func testSaveCreatesVisitWithContactsTypeAndFollowUpTask() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet")
        try env.repos.contacts.add(contact, to: customer)
        let model = makeModel(env, customer: customer)

        model.type = .online
        model.toggleContact(contact)
        model.note = "  Görüşme özeti  "
        model.nextStep = "Teklif gönder"
        model.hasNextStepDate = true
        model.nextStepDate = TestCalendar.date(2026, 12, 3)

        XCTAssertTrue(model.save())

        let visit = try XCTUnwrap(try env.repos.visits.visits(for: customer).first)
        XCTAssertEqual(visit.type, .online)
        XCTAssertEqual(visit.summary, "Görüşme özeti")
        XCTAssertEqual(visit.contacts?.map(\.id), [contact.id])
        XCTAssertEqual(visit.nextStep, "Teklif gönder")
        let task = try XCTUnwrap(try env.repos.tasks.fetchAll().first)
        XCTAssertEqual(task.source, .visitNextStep)
        XCTAssertEqual(task.visit?.id, visit.id)
    }

    func testToggleNextStepOffCreatesNoTask() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = makeModel(env, customer: customer)
        model.nextStep = "Sadece not"
        model.hasNextStepDate = false

        XCTAssertTrue(model.save())
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
    }

    func testEditModeLoadsExistingVisitAndKeepsItsCustomer() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet")
        try env.repos.contacts.add(contact, to: customer)
        var draft = VisitDraft()
        draft.type = .phone
        draft.summary = "eski not"
        draft.transcript = "ham"
        draft.nextStep = "ara"
        draft.nextStepDate = TestCalendar.date(2026, 12, 1)
        let visit = try VisitService(repositories: env.repos, reminderMinutes: 540)
            .save(draft, customer: customer, contacts: [contact], existing: nil)

        let other = try env.makeCustomer("Başka")
        let model = makeModel(env, customer: other, visit: visit)

        XCTAssertTrue(model.isEditing)
        XCTAssertEqual(model.customer?.id, customer.id, "Düzenlemede müşteri ziyaretinki kalır")
        XCTAssertEqual(model.type, .phone)
        XCTAssertEqual(model.note, "eski not")
        XCTAssertEqual(model.rawTranscript, "ham")
        XCTAssertTrue(model.hasNextStepDate)
        XCTAssertEqual(model.selectedContactIDs, [contact.id])

        model.note = "yeni not"
        XCTAssertTrue(model.save())
        XCTAssertEqual(visit.summary, "yeni not")
        XCTAssertEqual(try env.repos.visits.fetchAll().count, 1)
    }
}

@MainActor
final class SampleVisitDataTests: XCTestCase {
    #if DEBUG
    func testSampleDataHasVisitHistoryWithTaskAndContacts() throws {
        let env = try TestEnv()
        try SampleData.load(into: env.repos)

        let showcase = try XCTUnwrap(try env.repos.customers.fetchAll().first { $0.name == SampleData.showcaseName })
        let visits = try env.repos.visits.visits(for: showcase)
        XCTAssertEqual(visits.count, 3)
        XCTAssertEqual(visits.map(\.date), visits.map(\.date).sorted(by: >), "En yeni üstte")
        XCTAssertTrue(visits.allSatisfy { !$0.exportedToCRM })
        XCTAssertEqual(try env.repos.tasks.fetchAll().filter { $0.source == .visitNextStep }.count, 1, "Yalnızca takip tarihi olan ziyaret görev üretir")
    }
    #endif
}
