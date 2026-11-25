import XCTest
@testable import SahaSatis

/// Ziyaret "Konu" alanı: başlık kuralı, kaydetme, öneriler.
final class VisitTitleTests: XCTestCase {
    func testTopicIsTheTitle() {
        let visit = Visit(summary: "Uzun bir görüşme notu", topic: "Hat 3 PLC yenileme")
        XCTAssertEqual(visit.displayTitle, "Hat 3 PLC yenileme")
        XCTAssertEqual(visit.noteBelowTitle, "Uzun bir görüşme notu", "Konu varsa not olduğu gibi altta")
    }

    func testTopicIsTrimmedAndCollapsedToOneLine() {
        XCTAssertEqual(Visit(topic: "  Hat 3\n PLC   yenileme ").displayTitle, "Hat 3 PLC yenileme")
    }

    func testBlankTopicFallsBackToTheFirstNoteLine() {
        let visit = Visit(summary: "\n  İlk satır burada  \nİkinci satır\n\nÜçüncü satır", topic: "   ")
        XCTAssertEqual(visit.displayTitle, "İlk satır burada")
        XCTAssertEqual(visit.noteBelowTitle, "İkinci satır\n\nÜçüncü satır", "Başlık olan satır tekrarlanmaz")
    }

    func testSingleLineNoteUsedAsTitleLeavesNothingBelow() {
        let visit = Visit(summary: "Tek satırlık not")
        XCTAssertEqual(visit.displayTitle, "Tek satırlık not")
        XCTAssertEqual(visit.noteBelowTitle, "")
    }

    func testNoTopicAndNoNoteMeansNoTitle() {
        let visit = Visit(summary: " \n ")
        XCTAssertEqual(visit.displayTitle, "")
        XCTAssertEqual(visit.noteBelowTitle, "")
        XCTAssertEqual(Visit().topic, "")
    }

    func testTurkishCharactersInTitles() {
        XCTAssertEqual(Visit(topic: "İşletme güvenlik röleleri ığüşöç").displayTitle, "İşletme güvenlik röleleri ığüşöç")
    }
}

@MainActor
final class VisitTopicFormTests: XCTestCase {
    private let cal = TestCalendar.utc

    private func makeModel(
        _ env: TestEnv,
        customer: Customer?,
        visit: Visit? = nil,
        seed: VisitFormSeed = VisitFormSeed()
    ) -> VisitFormModel {
        VisitFormModel(
            repositories: env.repos,
            reminderMinutes: 9 * 60,
            engine: MockSpeechEngine(),
            customer: customer,
            visit: visit,
            seed: seed
        )
    }

    @discardableResult
    private func addVisit(_ env: TestEnv, _ customer: Customer, day: Int, topic: String) throws -> Visit {
        let visit = Visit(date: TestCalendar.date(2026, 10, day, 10), topic: topic)
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: nil)
        return visit
    }

    func testTopicIsSavedTrimmedToOneLineAndOptional() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()

        let model = makeModel(env, customer: customer)
        model.topic = "  Hat 3\nPLC   yenileme "
        XCTAssertTrue(model.save())
        XCTAssertEqual(try env.repos.visits.fetchAll().first?.topic, "Hat 3 PLC yenileme")

        let empty = makeModel(env, customer: customer)
        XCTAssertTrue(empty.canSave, "Konu zorunlu değil")
        XCTAssertTrue(empty.save())
        XCTAssertEqual(try env.repos.visits.fetchAll().filter { $0.topic.isEmpty }.count, 1)
    }

    func testEditingLoadsAndUpdatesTheTopic() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let visit = try addVisit(env, customer, day: 5, topic: "Eski konu")

        let model = makeModel(env, customer: customer, visit: visit)
        XCTAssertEqual(model.topic, "Eski konu")
        model.topic = "Yeni konu"
        XCTAssertTrue(model.save())
        XCTAssertEqual(visit.topic, "Yeni konu")
    }

    func testSeedTopicPrefillsNewVisit() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = makeModel(env, customer: customer, seed: VisitFormSeed(topic: "Tohum konu"))
        XCTAssertEqual(model.topic, "Tohum konu")
    }

    func testServiceStoresTheDraftTopic() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        var draft = VisitDraft()
        draft.topic = "Bakım sözleşmesi"
        let visit = try VisitService(repositories: env.repos, reminderMinutes: 540, calendar: cal)
            .save(draft, customer: customer, contacts: [], existing: nil)
        XCTAssertEqual(visit.topic, "Bakım sözleşmesi")
    }

    // MARK: - Öneriler

    func testSuggestsTheLastFiveDistinctTopicsNewestFirst() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let other = try env.makeCustomer("Başka Firma")
        for (day, topic) in [(1, "Bir"), (2, "İki"), (3, "Üç"), (4, "Dört"), (5, "Beş"), (6, "Altı"), (7, "Yedi")] {
            try addVisit(env, customer, day: day, topic: topic)
        }
        try addVisit(env, customer, day: 8, topic: "")
        try addVisit(env, customer, day: 9, topic: "  ")
        try addVisit(env, customer, day: 10, topic: "yedi")
        try addVisit(env, other, day: 11, topic: "Başka müşterinin konusu")

        let model = makeModel(env, customer: customer)

        XCTAssertEqual(model.topicSuggestions, ["yedi", "Altı", "Beş", "Dört", "Üç"], "Boşlar ve büyük/küçük harf tekrarları atlanır, en çok 5")
        XCTAssertEqual(VisitFormModel.maxTopicSuggestions, 5)
    }

    func testSuggestionsFollowTheSelectedCustomer() throws {
        let env = try TestEnv()
        let first = try env.makeCustomer("Birinci")
        let second = try env.makeCustomer("İkinci")
        try addVisit(env, first, day: 1, topic: "Birincinin konusu")
        try addVisit(env, second, day: 2, topic: "İkincinin konusu")

        let model = makeModel(env, customer: nil)
        XCTAssertEqual(model.topicSuggestions, [])

        model.customer = first
        XCTAssertEqual(model.topicSuggestions, ["Birincinin konusu"])
        model.customer = second
        model.customerChanged()
        XCTAssertEqual(model.topicSuggestions, ["İkincinin konusu"])
    }

    func testSuggestionsHideTheTextAlreadyTypedAndTheEditedVisitsOwnTopic() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try addVisit(env, customer, day: 1, topic: "Yedek parça")
        let edited = try addVisit(env, customer, day: 2, topic: "Hat 3")
        try addVisit(env, customer, day: 3, topic: "Bakım")

        let editing = makeModel(env, customer: customer, visit: edited)
        XCTAssertEqual(editing.topicSuggestions, ["Bakım", "Yedek parça"], "Düzenlenen ziyaretin konusu önerilmez")

        let fresh = makeModel(env, customer: customer)
        fresh.topic = "bakım"
        XCTAssertEqual(fresh.topicSuggestions, ["Hat 3", "Yedek parça"], "Formda yazılı olan konu önerilmez")
    }

    func testTappingASuggestionFillsTheField() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try addVisit(env, customer, day: 1, topic: "Yedek parça")
        let model = makeModel(env, customer: customer)

        model.topic = try XCTUnwrap(model.topicSuggestions.first)

        XCTAssertEqual(model.topic, "Yedek parça")
        XCTAssertTrue(model.topicSuggestions.isEmpty, "Seçilen öneri listeden kalkar")
    }
}
