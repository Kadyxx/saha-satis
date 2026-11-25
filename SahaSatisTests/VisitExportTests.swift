import XCTest
@testable import SahaSatis

/// CRM rapor metni: şablon, boş alanlar, çoklu kişi, Türkçe karakterler, tarih biçimi.
final class VisitReportFormatterTests: XCTestCase {
    private let cal = TestCalendar.utc

    private func item(
        customer: String = "Örnek Makina A.Ş.",
        city: String = "Bursa",
        district: String = "Nilüfer",
        contacts: [VisitExportItem.Person] = [],
        topic: String = "",
        note: String = "",
        nextStep: String = "",
        nextStepDate: Date? = nil,
        date: Date = TestCalendar.date(2026, 11, 24, 10)
    ) -> VisitExportItem {
        VisitExportItem(
            date: date, customerName: customer, city: city, district: district, contacts: contacts,
            typeTitle: "Yüz yüze", topic: topic, note: note, nextStep: nextStep, nextStepDate: nextStepDate
        )
    }

    func testBlockMatchesSpecTemplate() {
        let full = item(
            contacts: [
                VisitExportItem.Person(name: "Ahmet Yılmaz", title: "Bakım Müdürü"),
                VisitExportItem.Person(name: "Ayşe Demir")
            ],
            topic: "Hat 3 PLC yenileme",
            note: "Bakım müdürü eski denetleyicilerin yedek parça sorununu anlattı.\nTeklif istediler.",
            nextStep: "Teklif hazırlanacak",
            nextStepDate: TestCalendar.date(2026, 11, 28)
        )
        let expected = """
        === ZIYARET 1 ===
        Tarih: 24.11.2026
        Firma: Örnek Makina A.Ş.
        Şehir / İlçe: Bursa / Nilüfer
        Görüşülen: Ahmet Yılmaz (Bakım Müdürü), Ayşe Demir
        Ziyaret tipi: Yüz yüze
        Konu: Hat 3 PLC yenileme
        Görüşme notu:
        Bakım müdürü eski denetleyicilerin yedek parça sorununu anlattı.
        Teklif istediler.
        Sonraki adım: Teklif hazırlanacak
        Takip tarihi: 28.11.2026
        """
        XCTAssertEqual(VisitReportFormatter.block(full, number: 1, calendar: cal), expected)
    }

    func testEmptyFieldsKeepTheirLinesWithADash() {
        let empty = VisitExportItem(date: TestCalendar.date(2026, 11, 24), customerName: "", typeTitle: "")
        let expected = """
        === ZIYARET 3 ===
        Tarih: 24.11.2026
        Firma: -
        Şehir / İlçe: -
        Görüşülen: -
        Ziyaret tipi: -
        Konu: -
        Görüşme notu:
        -
        Sonraki adım: -
        Takip tarihi: -
        """
        XCTAssertEqual(VisitReportFormatter.block(empty, number: 3, calendar: cal), expected)
    }

    func testCityAndDistrictCombinations() {
        func line(_ city: String, _ district: String) -> String {
            let text = VisitReportFormatter.block(item(city: city, district: district), number: 1, calendar: cal)
            return text.split(separator: "\n").first { $0.hasPrefix("Şehir") }.map(String.init) ?? ""
        }
        XCTAssertEqual(line("Bursa", "Nilüfer"), "Şehir / İlçe: Bursa / Nilüfer")
        XCTAssertEqual(line("Bursa", ""), "Şehir / İlçe: Bursa")
        XCTAssertEqual(line("", "Nilüfer"), "Şehir / İlçe: Nilüfer")
        XCTAssertEqual(line("  ", ""), "Şehir / İlçe: -")
    }

    func testMultipleContactsWithAndWithoutTitles() {
        let contacts = [
            VisitExportItem.Person(name: "Ahmet Yılmaz", title: "Bakım Müdürü"),
            VisitExportItem.Person(name: "  ", title: "Adsız"),
            VisitExportItem.Person(name: "Ayşe Demir", title: ""),
            VisitExportItem.Person(name: "Mehmet Kaya", title: "Fabrika\nMüdürü")
        ]
        let text = VisitReportFormatter.block(item(contacts: contacts), number: 1, calendar: cal)
        XCTAssertTrue(
            text.contains("Görüşülen: Ahmet Yılmaz (Bakım Müdürü), Ayşe Demir, Mehmet Kaya (Fabrika Müdürü)\n"),
            text
        )
    }

    func testTurkishCharactersSurviveUnchanged() {
        let tricky = item(
            customer: "ÇİĞDEM Şişecam İnşaat Ğ.Ş.",
            city: "Eskişehir",
            district: "Odunpazarı",
            contacts: [VisitExportItem.Person(name: "İsmail Öztürk", title: "Üretim Müdürü")],
            topic: "ığüşöç İĞÜŞÖÇ",
            note: "Çıkış hattı için öneri: şalter, ışık perdesi.",
            nextStep: "Güvenlik rölesi önerisi"
        )
        let text = VisitReportFormatter.block(tricky, number: 1, calendar: cal)
        for expected in [
            "Firma: ÇİĞDEM Şişecam İnşaat Ğ.Ş.", "Eskişehir / Odunpazarı", "İsmail Öztürk (Üretim Müdürü)",
            "Konu: ığüşöç İĞÜŞÖÇ", "Çıkış hattı için öneri: şalter, ışık perdesi.", "Sonraki adım: Güvenlik rölesi önerisi"
        ] {
            XCTAssertTrue(text.contains(expected), expected)
        }
    }

    func testNoteKeepsLinesButTrimsWhitespace() {
        let note = "\n\n  Birinci satır   \r\n\r\nİkinci satır\t\n\n   \n"
        let text = VisitReportFormatter.block(item(note: note), number: 1, calendar: cal)
        XCTAssertTrue(text.contains("Görüşme notu:\n  Birinci satır\n\nİkinci satır\nSonraki adım"), text)
        XCTAssertFalse(text.contains("\r"))
    }

    func testWhitespaceOnlyNoteBecomesDash() {
        let text = VisitReportFormatter.block(item(note: " \n \t\n"), number: 1, calendar: cal)
        XCTAssertTrue(text.contains("Görüşme notu:\n-\n"), text)
    }

    func testSingleLineFieldsCollapseLineBreaks() {
        let text = VisitReportFormatter.block(
            item(topic: "Hat 3\nPLC   yenileme", nextStep: "  Teklif\nhazırla  "),
            number: 1, calendar: cal
        )
        XCTAssertTrue(text.contains("Konu: Hat 3 PLC yenileme\n"), text)
        XCTAssertTrue(text.contains("Sonraki adım: Teklif hazırla\n"), text)
    }

    func testReportNumbersBlocksAndSeparatesThemWithABlankLine() {
        let first = item(customer: "Birinci")
        let second = item(customer: "İkinci")
        let blocks = VisitReportFormatter.blocks([first, second], calendar: cal)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertTrue(blocks[0].hasPrefix("=== ZIYARET 1 ==="))
        XCTAssertTrue(blocks[1].hasPrefix("=== ZIYARET 2 ==="))
        XCTAssertEqual(VisitReportFormatter.report([first, second], calendar: cal), blocks[0] + "\n\n" + blocks[1])
        XCTAssertEqual(VisitReportFormatter.report([], calendar: cal), "")
    }

    func testSubjectUsesEnDashAndNumericDate() {
        XCTAssertEqual(
            VisitReportFormatter.subject(day: TestCalendar.date(2026, 11, 24), calendar: cal),
            "Ziyaret Raporu \u{2013} 24.11.2026"
        )
    }

    func testDatesAreZeroPaddedAndFollowTheCalendarTimeZone() {
        XCTAssertEqual(AppFormat.numericDate(TestCalendar.date(2026, 3, 5), calendar: cal), "05.03.2026")

        var istanbul = Calendar(identifier: .gregorian)
        istanbul.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        // 24 Kas 22:30 UTC = 25 Kas 01:30 İstanbul
        XCTAssertEqual(AppFormat.numericDate(TestCalendar.date(2026, 11, 24, 22, 30), calendar: istanbul), "25.11.2026")
        XCTAssertEqual(AppFormat.numericDate(TestCalendar.date(2026, 11, 24, 22, 30), calendar: cal), "24.11.2026")
    }
}

/// Seçim, rapor, "aktarıldı" işaretleme ve bunun Bugün ekranına / hatırlatmalara etkisi.
@MainActor
final class VisitExportModelTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let day = TestCalendar.date(2026, 11, 24, 12)

    private func makeModel(_ env: TestEnv, day: Date? = nil) -> VisitExportModel {
        VisitExportModel(repositories: env.repos, day: day ?? self.day, calendar: cal)
    }

    @discardableResult
    private func addVisit(
        _ env: TestEnv,
        _ customer: Customer,
        hour: Int,
        on date: Date? = nil,
        summary: String = "",
        contacts: [Contact] = [],
        exported: Bool = false
    ) throws -> Visit {
        let base = date ?? day
        let visit = Visit(
            date: cal.date(bySettingHour: hour, minute: 0, second: 0, of: base)!,
            type: .visit,
            summary: summary
        )
        try env.repos.visits.add(visit, customer: customer, contacts: contacts, opportunity: nil)
        if exported { try env.repos.visits.markExported([visit], at: base) }
        return visit
    }

    func testListsOnlyTheSelectedDaysUnexportedVisitsOldestFirst() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let late = try addVisit(env, customer, hour: 15)
        let early = try addVisit(env, customer, hour: 9)
        try addVisit(env, customer, hour: 11, exported: true)
        try addVisit(env, customer, hour: 10, on: TestCalendar.date(2026, 11, 23))

        let model = makeModel(env)
        model.reload(resetSelection: true)

        XCTAssertEqual(model.visits.map(\.id), [early.id, late.id])
        XCTAssertEqual(model.selectedIDs, [early.id, late.id], "Aktarılmamışlar baştan seçili")
    }

    func testShowExportedListsThemUnselectedAndAllowsResending() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let pending = try addVisit(env, customer, hour: 9)
        let sent = try addVisit(env, customer, hour: 11, exported: true)
        let model = makeModel(env)
        model.reload(resetSelection: true)

        model.showExported = true
        model.reload(resetSelection: false)
        XCTAssertEqual(model.visits.map(\.id), [pending.id, sent.id])
        XCTAssertEqual(model.selectedIDs, [pending.id], "Aktarılmış olan kendiliğinden seçilmez")

        model.toggle(sent)
        XCTAssertEqual(model.selectedVisits.map(\.id), [pending.id, sent.id])
        XCTAssertTrue(model.allSelected)

        model.showExported = false
        model.reload(resetSelection: false)
        XCTAssertEqual(model.selectedIDs, [pending.id], "Listeden çıkan seçimden de düşer")
    }

    func testSelectionHelpers() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let first = try addVisit(env, customer, hour: 9)
        let second = try addVisit(env, customer, hour: 10)
        let model = makeModel(env)
        model.reload(resetSelection: true)

        model.deselectAll()
        XCTAssertTrue(model.selectedVisits.isEmpty)
        XCTAssertFalse(model.allSelected)
        XCTAssertEqual(model.reportText, "")

        model.toggle(second)
        XCTAssertTrue(model.isSelected(second))
        XCTAssertFalse(model.isSelected(first))

        model.selectAll()
        XCTAssertTrue(model.allSelected)
        model.toggle(second)
        XCTAssertEqual(model.selectedVisits.map(\.id), [first.id])
    }

    func testChangingTheDayReselectsThatDaysVisits() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try addVisit(env, customer, hour: 9)
        let yesterday = try addVisit(env, customer, hour: 9, on: TestCalendar.date(2026, 11, 23))
        let model = makeModel(env)
        model.reload(resetSelection: true)

        model.day = TestCalendar.date(2026, 11, 23, 8)
        model.reload(resetSelection: true)

        XCTAssertEqual(model.visits.map(\.id), [yesterday.id])
        XCTAssertEqual(model.selectedIDs, [yesterday.id])
        XCTAssertEqual(model.subject, "Ziyaret Raporu \u{2013} 23.11.2026")
    }

    func testReportCoversOnlySelectedVisitsInChronologicalOrder() throws {
        let env = try TestEnv()
        let a = try env.makeCustomer("Ankara Makina", city: "Ankara")
        let b = try env.makeCustomer("Bursa Gıda", city: "Bursa")
        try addVisit(env, b, hour: 14, summary: "İkinci not")
        let skipped = try addVisit(env, a, hour: 12, summary: "Atlanacak")
        try addVisit(env, a, hour: 9, summary: "Birinci not")
        let model = makeModel(env)
        model.reload(resetSelection: true)
        model.toggle(skipped)

        let text = model.reportText
        XCTAssertEqual(model.blocks.count, 2)
        XCTAssertTrue(model.blocks[0].contains("Firma: Ankara Makina"))
        XCTAssertTrue(model.blocks[0].contains("Birinci not"))
        XCTAssertTrue(model.blocks[1].contains("Firma: Bursa Gıda"))
        XCTAssertTrue(text.contains("=== ZIYARET 2 ==="))
        XCTAssertFalse(text.contains("Atlanacak"))
    }

    func testItemMapsVisitFieldsContactsAndTopic() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Örnek Makina A.Ş.", city: "Bursa")
        customer.district = "Nilüfer"
        let ayse = Contact(fullName: "Ayşe Demir", title: "Satın Alma")
        let ahmet = Contact(fullName: "Ahmet Yılmaz", title: "Bakım Müdürü")
        let primary = Contact(fullName: "Zeynep Kaya", title: "Genel Müdür", isPrimary: true)
        for contact in [ayse, ahmet, primary] { try env.repos.contacts.add(contact, to: customer) }

        let opportunity = Opportunity(title: "Hat 3 PLC yenileme")
        try env.repos.opportunities.add(opportunity, customer: customer)
        let visit = Visit(date: day, type: .phone, summary: "Not", nextStep: "Teklif", nextStepDate: TestCalendar.date(2026, 11, 28))
        try env.repos.visits.add(visit, customer: customer, contacts: [ayse, ahmet, primary], opportunity: opportunity)

        var mapped = VisitExportItem(visit: visit)
        XCTAssertEqual(mapped.customerName, "Örnek Makina A.Ş.")
        XCTAssertEqual(mapped.district, "Nilüfer")
        XCTAssertEqual(mapped.typeTitle, "Telefon")
        XCTAssertEqual(mapped.contacts.map(\.name), ["Zeynep Kaya", "Ahmet Yılmaz", "Ayşe Demir"], "Önce birincil kişi, sonra ada göre")
        XCTAssertEqual(mapped.topic, "", "Konu alanı boşsa bağlı fırsatın başlığı kullanılmaz")

        visit.topic = "Hat 3 PLC yenileme"
        mapped = VisitExportItem(visit: visit)
        XCTAssertEqual(mapped.topic, "Hat 3 PLC yenileme")
        XCTAssertEqual(mapped.note, "Not")
        XCTAssertEqual(mapped.nextStep, "Teklif")
    }

    func testReportTopicLineComesFromTheTopicField() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let withTopic = Visit(date: TestCalendar.date(2026, 11, 24, 9), summary: "Not", topic: "Yedek parça stoğu")
        let withoutTopic = Visit(date: TestCalendar.date(2026, 11, 24, 10), summary: "Başka not")
        try env.repos.visits.add(withTopic, customer: customer, contacts: [], opportunity: nil)
        try env.repos.visits.add(withoutTopic, customer: customer, contacts: [], opportunity: nil)
        let model = makeModel(env)
        model.reload(resetSelection: true)

        XCTAssertTrue(model.blocks[0].contains("\nKonu: Yedek parça stoğu\n"), model.blocks[0])
        XCTAssertTrue(model.blocks[1].contains("\nKonu: -\n"), model.blocks[1])
    }

    func testRecipients() {
        XCTAssertEqual(VisitExportModel.recipients(from: ""), [])
        XCTAssertEqual(VisitExportModel.recipients(from: "  \n"), [])
        XCTAssertEqual(VisitExportModel.recipients(from: " crm@example.com "), ["crm@example.com"])
    }

    // MARK: - Aktarıldı işaretleme

    func testMarkingSetsFlagsOnlyForSelectedVisits() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let chosen = try addVisit(env, customer, hour: 9)
        let left = try addVisit(env, customer, hour: 10)
        let model = makeModel(env)
        model.reload(resetSelection: true)
        model.toggle(left)

        let stamp = TestCalendar.date(2026, 11, 24, 18)
        XCTAssertTrue(model.markSelectedExported(now: stamp))

        XCTAssertTrue(chosen.exportedToCRM)
        XCTAssertEqual(chosen.exportedAt, stamp)
        XCTAssertFalse(left.exportedToCRM)
        XCTAssertNil(left.exportedAt)
        XCTAssertEqual(model.visits.map(\.id), [left.id], "Aktarılan listeden düşer")
    }

    func testResendingAnExportedVisitRefreshesItsTimestamp() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let visit = try addVisit(env, customer, hour: 9, exported: true)
        let model = makeModel(env)
        model.showExported = true
        model.reload(resetSelection: true)
        model.toggle(visit)

        let later = TestCalendar.date(2026, 11, 25, 9)
        XCTAssertTrue(model.markSelectedExported(now: later))

        XCTAssertTrue(visit.exportedToCRM)
        XCTAssertEqual(visit.exportedAt, later)
    }

    func testMarkingUpdatesTodayCountAndEndOfDayReminder() async throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer(status: .passive)
        let morning = TestCalendar.date(2026, 11, 25, 7)
        let today = TestCalendar.date(2026, 11, 25, 12)
        try addVisit(env, customer, hour: 9, on: today)
        try addVisit(env, customer, hour: 10, on: today)

        let todayModel = TodayModel(repositories: env.repos, calendar: cal)
        todayModel.reload(now: morning)
        XCTAssertEqual(todayModel.unexportedCount, 2)

        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let mock = MockNotificationScheduler()
        let reminders = ReminderScheduler(
            repositories: env.repos, settings: SahaSatis.AppSettings(defaults: defaults),
            scheduler: mock, calendar: cal, now: { morning }
        )
        await reminders.refresh()
        let before = try XCTUnwrap(mock.lastPlan.first { $0.kind == .endOfDay })
        XCTAssertEqual(before.body, "2 ziyaret CRM'e aktarılmadı")

        let model = makeModel(env, day: today)
        model.reload(resetSelection: true)
        XCTAssertTrue(model.markSelectedExported(now: today))

        todayModel.reload(now: morning)
        XCTAssertEqual(todayModel.unexportedCount, 0)
        await reminders.refresh()
        XCTAssertFalse(mock.lastPlan.contains { $0.kind == .endOfDay }, "Hepsi aktarılınca gün sonu hatırlatması kalkar")
    }
}
