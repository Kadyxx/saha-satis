import XCTest
@testable import SahaSatis

/// Claude cevabının şablona göre ayrıştırılması.
final class ClaudeReplyParserTests: XCTestCase {
    private let calendar = TestCalendar.utc

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private var today: Date { day(2026, 11, 26) }

    private func parse(_ text: String) -> NoteSuggestion {
        ClaudeReplyParser.parse(text, today: today, calendar: calendar)
    }

    private func parseDate(_ text: String) -> Date? {
        ClaudeReplyParser.parseDate(text, today: today, calendar: calendar)
    }

    func testFullTemplate() {
        let result = parse("""
        Konu: Hat 3 PLC yenileme
        Özet: 1756-L61 için yedek parça sorunu iletilmiştir.
        Sonraki adım: Teklif gönderilecek
        Takip tarihi: 04.12.2026
        """)
        XCTAssertTrue(result.followsTemplate)
        XCTAssertEqual(result.topic, "Hat 3 PLC yenileme")
        XCTAssertEqual(result.summary, "1756-L61 için yedek parça sorunu iletilmiştir.")
        XCTAssertEqual(result.nextStep, "Teklif gönderilecek")
        XCTAssertEqual(result.followUpDate, day(2026, 12, 4))
        XCTAssertEqual(result.warnings, [])
    }

    func testMissingFields() {
        let result = parse("""
        Konu:
        Özet: Genel görüşme yapılmıştır.
        Sonraki adım:
        Takip tarihi:
        """)
        XCTAssertTrue(result.followsTemplate)
        XCTAssertEqual(result.topic, "")
        XCTAssertEqual(result.summary, "Genel görüşme yapılmıştır.")
        XCTAssertEqual(result.nextStep, "")
        XCTAssertNil(result.followUpDate)
        XCTAssertEqual(result.warnings, [])
    }

    func testOnlySummary() {
        let result = parse("Özet: Kısa not.")
        XCTAssertTrue(result.followsTemplate)
        XCTAssertEqual(result.summary, "Kısa not.")
        XCTAssertEqual(result.topic, "")
    }

    func testPlaceholdersAreEmpty() {
        let result = parse("""
        Özet: Not.
        Sonraki adım: Yok.
        Takip tarihi: (yoksa boş)
        """)
        XCTAssertEqual(result.nextStep, "")
        XCTAssertNil(result.followUpDate)
        XCTAssertEqual(result.warnings, [])
    }

    func testExtraTextAndMarkdownAreTolerated() {
        let result = parse("""
        Tabii, işte düzenlenmiş hali:

        ```
        **Konu:** Servo arızası
        **ÖZET:**
        2198-H008 sürücüsünde arıza bildirilmiştir.

        Yerinde inceleme talep edilmiştir.
        - Sonraki Adım: Servis planlanacak
        TAKİP TARİHİ: 01.12.2026
        ```

        Başka bir isteğiniz var mı? 2 gün içinde bakabilirim.
        """)
        XCTAssertTrue(result.followsTemplate)
        XCTAssertEqual(result.topic, "Servo arızası")
        XCTAssertEqual(
            result.summary,
            "2198-H008 sürücüsünde arıza bildirilmiştir.\n\nYerinde inceleme talep edilmiştir."
        )
        XCTAssertEqual(result.nextStep, "Servis planlanacak")
        XCTAssertEqual(result.followUpDate, day(2026, 12, 1))
    }

    func testClosingTextAfterEmptyDateIsIgnored() {
        let result = parse("""
        Özet: Not.
        Takip tarihi:

        Umarım yardımcı olur.
        """)
        XCTAssertNil(result.followUpDate)
        XCTAssertEqual(result.summary, "Not.")
        XCTAssertEqual(result.warnings, [])
    }

    func testClosingTextAfterNextStepIsIgnored() {
        let result = parse("""
        Özet: Not.
        Sonraki adım: Aranacak

        İyi çalışmalar.
        """)
        XCTAssertEqual(result.nextStep, "Aranacak")
    }

    func testDateFormats() {
        let expected = day(2026, 12, 4)
        for text in ["04.12.2026", "4.12.2026", "04/12/2026", "4-12-2026", "04.12.26", "2026-12-04",
                     "4 Aralık 2026", "4 ARALIK", "04.12", "04.12.2026 (Cuma)", "04.12.2026."] {
            XCTAssertEqual(parseDate(text), expected, text)
        }
    }

    func testYearlessPastDateMeansNextYear() {
        XCTAssertEqual(parseDate("5 Ocak"), day(2027, 1, 5))
        XCTAssertEqual(parseDate("05.01"), day(2027, 1, 5))
        XCTAssertEqual(parseDate("26 Kasım"), day(2026, 11, 26), "Bugün gelecek yıla atılmaz")
    }

    func testInvalidDateWarns() {
        XCTAssertNil(parseDate("31.02.2026"))
        XCTAssertNil(parseDate("12.2026"))
        let result = parse("Özet: Not.\nTakip tarihi: haftaya 2 gün içinde")
        XCTAssertNil(result.followUpDate)
        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertTrue(result.followsTemplate)
    }

    func testBrokenTemplatePutsWholeTextIntoNote() {
        let text = "Tabii, notu düzenledim: teklif istendi.\nTakip: 04.12.2026"
        let result = parse("  \(text)\n")
        XCTAssertFalse(result.followsTemplate)
        XCTAssertEqual(result.summary, text)
        XCTAssertEqual(result.topic, "")
        XCTAssertNil(result.followUpDate)
        XCTAssertEqual(result.warnings, [ClaudeReplyParser.brokenTemplateWarning])
    }

    func testEmptySummaryIsBrokenTemplate() {
        XCTAssertFalse(parse("Konu: Deneme\nÖzet:\nSonraki adım:").followsTemplate)
    }
}

final class ShareToClaudeAssistantTests: XCTestCase {
    private let assistant = ShareToClaudeAssistant(calendar: TestCalendar.utc)

    private func input(contacts: [String] = ["Ahmet Yılmaz (Bakım Müdürü)"], instruction: String = "TALİMAT") -> NoteAssistantInput {
        NoteAssistantInput(
            rawNote: "  ham not metni 1756-L71 \n",
            customerName: "Örnek Makina A.Ş.",
            contacts: contacts,
            today: TestCalendar.utc.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12))!,
            instruction: instruction
        )
    }

    func testHandoffContainsEverything() async throws {
        let response = try await assistant.request(input())
        XCTAssertEqual(response, .handoff(text: """
        TALİMAT

        Bugünün tarihi: 06.11.2026
        Müşteri: Örnek Makina A.Ş.
        Görüşülen kişiler: Ahmet Yılmaz (Bakım Müdürü)

        Ham not:
        ham not metni 1756-L71
        """))
    }

    func testEmptyInstructionAndNoContacts() {
        let text = assistant.prompt(for: input(contacts: [], instruction: "  "))
        XCTAssertTrue(text.hasPrefix(AppSettings.defaultClaudeInstruction))
        XCTAssertTrue(text.contains("Görüşülen kişiler: -"))
    }

    func testDefaultInstructionAsksForTemplate() {
        for line in ["Konu: ...", "Özet: ...", "Sonraki adım: ...", "Takip tarihi: GG.AA.YYYY (yoksa boş)"] {
            XCTAssertTrue(AppSettings.defaultClaudeInstruction.contains(line), line)
        }
    }

    /// Panoda gönderilen metin dururken "yapıştır" denirse cevap sanılmaz.
    func testOwnPromptIsRecognized() {
        XCTAssertTrue(ShareToClaudeAssistant.isOwnPrompt(assistant.prompt(for: input())))
        XCTAssertFalse(ShareToClaudeAssistant.isOwnPrompt("Konu: A\nÖzet: B"))
    }

    func testInstructionSettingPersistsAndResets() throws {
        let suite = "claude-instruction-tests"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.claudeInstruction, AppSettings.defaultClaudeInstruction)
        settings.claudeInstruction = "Benim talimatım"
        XCTAssertEqual(AppSettings(defaults: defaults).claudeInstruction, "Benim talimatım")
        settings.claudeInstruction = AppSettings.defaultClaudeInstruction
        XCTAssertEqual(AppSettings(defaults: defaults).claudeInstruction, AppSettings.defaultClaudeInstruction)
    }
}

/// Onaylanan önerinin forma yazılması ve ham notun saklanması.
@MainActor
final class VisitFormAssistantTests: XCTestCase {
    private func makeModel(_ env: TestEnv, customer: Customer, visit: Visit? = nil) -> VisitFormModel {
        VisitFormModel(
            repositories: env.repos, reminderMinutes: 540, engine: MockSpeechEngine(), customer: customer, visit: visit
        )
    }

    func testApplyFillsFieldsAndKeepsRawNote() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = makeModel(env, customer: customer)
        XCTAssertFalse(model.canAskAssistant)
        model.note = "ham not"
        XCTAssertTrue(model.canAskAssistant)

        let followUp = Date(timeIntervalSince1970: 1_800_000_000)
        model.apply(NoteSuggestion(topic: "Konu A", summary: "Düzenli özet.", nextStep: "Ara", followUpDate: followUp))

        XCTAssertEqual(model.topic, "Konu A")
        XCTAssertEqual(model.note, "Düzenli özet.")
        XCTAssertEqual(model.nextStep, "Ara")
        XCTAssertTrue(model.hasNextStepDate)
        XCTAssertEqual(model.nextStepDate, followUp)
        XCTAssertEqual(model.rawTranscript, "ham not")

        XCTAssertTrue(model.save())
        let saved = try XCTUnwrap(try env.repos.visits.visits(for: customer).first)
        XCTAssertEqual(saved.summary, "Düzenli özet.")
        XCTAssertEqual(saved.transcript, "ham not")
    }

    func testEmptySuggestionFieldsDoNotErase() throws {
        let env = try TestEnv()
        let model = makeModel(env, customer: try env.makeCustomer())
        model.topic = "Eski konu"
        model.nextStep = "Eski adım"
        model.note = "ham"
        model.apply(NoteSuggestion(summary: "Yeni özet"))
        XCTAssertEqual(model.topic, "Eski konu")
        XCTAssertEqual(model.nextStep, "Eski adım")
        XCTAssertFalse(model.hasNextStepDate)
    }

    func testBrokenReplyChangesOnlyNote() throws {
        let env = try TestEnv()
        let model = makeModel(env, customer: try env.makeCustomer())
        model.topic = "Konu"
        model.note = "ham"
        model.apply(NoteSuggestion(summary: "serbest metin", followsTemplate: false))
        XCTAssertEqual(model.note, "serbest metin")
        XCTAssertEqual(model.topic, "Konu")
        XCTAssertEqual(model.rawTranscript, "ham")
    }

    /// İkinci kez uygulanınca ilk öneri ham not sayılmaz; dikte metni korunur ve tekrarlanmaz.
    func testRawNoteIsNotPollutedBySecondApply() throws {
        let env = try TestEnv()
        let model = makeModel(env, customer: try env.makeCustomer())
        model.appendDictation("dikte edilen not")
        model.apply(NoteSuggestion(summary: "Özet 1"))
        model.apply(NoteSuggestion(summary: "Özet 2"))
        XCTAssertEqual(model.rawTranscript, "dikte edilen not")
        XCTAssertEqual(model.note, "Özet 2")
    }
}
