import XCTest
@testable import SahaSatis

/// Takip görevi üretimi ve iptali, durum kuralları, takip günleri, hatırlatma motoru ve widget ile bağlantı.
/// Takvim: 25 Kas 2026 Çarşamba 12:00; varsayılan takip 3 ve 7 gün, geçerlilik uyarısı 3 gün önce, saat 09:00.
@MainActor
final class QuoteServiceTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 12)
    private var rules: QuoteReminderRules {
        QuoteReminderRules(defaultFollowUpDays: [3, 7], expiryEnabled: true, expiryDaysBefore: 3, reminderTime: TimeOfDay(hour: 9))
    }

    private func days(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now))! }

    private func service(_ env: TestEnv, rules: QuoteReminderRules? = nil) -> QuoteService {
        QuoteService(repositories: env.repos, reminderRules: rules ?? self.rules, calendar: cal)
    }

    private func reminderService(_ env: TestEnv, rules: QuoteReminderRules? = nil) -> QuoteReminderService {
        QuoteReminderService(repositories: env.repos, rules: rules ?? self.rules, calendar: cal)
    }

    @discardableResult
    private func addQuote(
        _ env: TestEnv,
        number: String = "T-2026-001",
        status: QuoteStatus = .draft,
        validDays: Int? = 20,
        followUpDays: [Int] = [],
        opportunity: Opportunity? = nil,
        customer: Customer? = nil
    ) throws -> Quote {
        let quote = Quote(
            quoteNumber: number, date: now, validUntil: validDays.map(days), status: status, followUpDays: followUpDays
        )
        try env.repos.quotes.add(quote, customer: try customer ?? env.makeCustomer(), opportunity: opportunity)
        return quote
    }

    private func tasks(_ env: TestEnv, _ source: TaskSource, for quote: Quote? = nil) throws -> [FollowUpTask] {
        try env.repos.tasks.fetchAll().filter { $0.source == source && (quote == nil || $0.quote?.id == quote?.id) }
    }

    private func dueDates(_ env: TestEnv, _ source: TaskSource, for quote: Quote? = nil) throws -> [Date] {
        try tasks(env, source, for: quote).map(\.dueDate).sorted()
    }

    // MARK: Gönderilince takip görevleri

    func testSendingCreatesDefaultFollowUpsAndExpiryWarning() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, validDays: 20)

        try service(env).setStatus(quote, to: .sent, now: now)

        XCTAssertEqual(quote.status, .sent)
        XCTAssertEqual(quote.sentAt, now)
        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [TestCalendar.date(2026, 11, 28, 9), TestCalendar.date(2026, 12, 2, 9)], "Gönderimden 3 ve 7 gün sonra")
        XCTAssertEqual(try dueDates(env, .quoteExpiry), [TestCalendar.date(2026, 12, 12, 9)], "Geçerlilik bitişinden (15 Ara) 3 gün önce")

        let follow = try XCTUnwrap(try tasks(env, .quoteFollowUp).first)
        XCTAssertEqual(follow.quote?.id, quote.id)
        XCTAssertEqual(follow.customer?.id, quote.customer?.id)
        XCTAssertTrue(follow.title.hasPrefix("Teklif takibi: T-2026-001"), follow.title)
        XCTAssertTrue(try tasks(env, .quoteExpiry).first?.title.hasPrefix("Teklif geçerliliği bitiyor: T-2026-001") == true)
    }

    func testQuoteSpecificDaysWinOverTheDefaults() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, followUpDays: [2, 5, 10])

        try service(env).setStatus(quote, to: .sent, now: now)

        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [
            TestCalendar.date(2026, 11, 27, 9), TestCalendar.date(2026, 11, 30, 9), TestCalendar.date(2026, 12, 5, 9)
        ])
    }

    func testSettingsDefaultDaysAreUsedWhenTheQuoteHasNone() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        var custom = rules
        custom.defaultFollowUpDays = [1, 14]

        try service(env, rules: custom).setStatus(quote, to: .sent, now: now)

        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [TestCalendar.date(2026, 11, 26, 9), TestCalendar.date(2026, 12, 9, 9)])
    }

    func testMovingStraightToFollowUpAlsoSchedulesIt() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)

        try service(env).setStatus(quote, to: .followUp, now: now)

        XCTAssertEqual(quote.sentAt, now)
        XCTAssertEqual(try tasks(env, .quoteFollowUp).count, 2)
    }

    func testExpiryWarningRules() throws {
        // Bitişe 3 günden az kaldı: bugüne çekilir.
        let env = try TestEnv()
        let soon = try addQuote(env, number: "A", validDays: 2)
        try service(env).setStatus(soon, to: .sent, now: now)
        XCTAssertEqual(try dueDates(env, .quoteExpiry, for: soon), [TestCalendar.date(2026, 11, 25, 9)])

        // Süresi geçmiş: uyarı yok.
        let expired = try addQuote(env, number: "B", validDays: -1)
        try service(env).setStatus(expired, to: .sent, now: now)
        XCTAssertTrue(try tasks(env, .quoteExpiry, for: expired).isEmpty)

        // Geçerlilik tarihi yok: uyarı yok.
        let open = try addQuote(env, number: "C", validDays: nil)
        try service(env).setStatus(open, to: .sent, now: now)
        XCTAssertTrue(try tasks(env, .quoteExpiry, for: open).isEmpty)

        // Ayar kapalı: uyarı yok.
        var off = rules
        off.expiryEnabled = false
        let quiet = try addQuote(env, number: "D", validDays: 20)
        try service(env, rules: off).setStatus(quiet, to: .sent, now: now)
        XCTAssertTrue(try tasks(env, .quoteExpiry, for: quiet).isEmpty)
        XCTAssertEqual(try tasks(env, .quoteFollowUp, for: quiet).count, 2, "Takip yine kurulur")
    }

    func testExpiryDaysBeforeFollowsTheSetting() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, validDays: 20)
        var custom = rules
        custom.expiryDaysBefore = 10

        try service(env, rules: custom).setStatus(quote, to: .sent, now: now)

        XCTAssertEqual(try dueDates(env, .quoteExpiry), [TestCalendar.date(2026, 12, 5, 9)])
    }

    // MARK: Kazanıldı / Kaybedildi / Taslak: iptal

    func testWinningOrLosingCancelsEveryPendingTask() throws {
        for status in [QuoteStatus.won, .lost, .draft] {
            let env = try TestEnv()
            let quote = try addQuote(env)
            try service(env).setStatus(quote, to: .sent, now: now)
            XCTAssertEqual(try env.repos.tasks.fetchAll().count, 3)

            try service(env).setStatus(quote, to: status, lostReason: status == .lost ? "Fiyat" : nil, now: now)

            XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty, status.title)
        }
    }

    func testCompletedFollowUpsSurviveCancellation() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)
        let first = try XCTUnwrap(try tasks(env, .quoteFollowUp).sorted { $0.dueDate < $1.dueDate }.first)
        try env.repos.tasks.complete(first, at: now)

        try service(env).setStatus(quote, to: .won, now: now)

        XCTAssertEqual(try env.repos.tasks.fetchAll().map(\.id), [first.id], "Tamamlanmış görev geçmişte kalır")
    }

    func testLostReasonIsStoredOnlyWhenLostAndClearedOnReopen() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, status: .sent)

        try service(env).setStatus(quote, to: .lost, lostReason: "  Fiyat\nyüksek ", now: now)
        XCTAssertEqual(quote.status, .lost)
        XCTAssertEqual(quote.lostReason, "Fiyat yüksek")

        try service(env).setStatus(quote, to: .sent, now: now)
        XCTAssertEqual(quote.lostReason, "")
        XCTAssertEqual(quote.sentAt, now, "Yeniden açılınca sayaç yeniden başlar")
        XCTAssertEqual(try tasks(env, .quoteFollowUp).count, 2, "Takipler yeniden kurulur")

        try service(env).setStatus(quote, to: .lost, lostReason: nil, now: now)
        XCTAssertEqual(quote.lostReason, "")
    }

    func testBackToDraftClearsSendDateSoResendingRestartsTheClock() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)

        try service(env).setStatus(quote, to: .draft, now: now)
        XCTAssertNil(quote.sentAt)

        let later = TestCalendar.date(2026, 11, 27, 12)
        try service(env).setStatus(quote, to: .sent, now: later)
        XCTAssertEqual(quote.sentAt, later)
        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [TestCalendar.date(2026, 11, 30, 9), TestCalendar.date(2026, 12, 4, 9)])
    }

    func testSentToFollowUpKeepsTheExistingTasksUntouched() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)
        let before = try tasks(env, .quoteFollowUp)
        let postponed = TestCalendar.date(2026, 12, 20, 9)
        try env.repos.tasks.postpone(before[0], to: postponed)
        let ids = Set(before.map(\.id))

        try service(env).setStatus(quote, to: .followUp, now: TestCalendar.date(2026, 11, 26, 12))

        let after = try tasks(env, .quoteFollowUp)
        XCTAssertEqual(Set(after.map(\.id)), ids)
        XCTAssertTrue(after.contains { $0.dueDate == postponed }, "Ertelenen görev olduğu gibi kalır")
        XCTAssertEqual(quote.sentAt, now, "Gönderim zamanı değişmez")
    }

    // MARK: Takip ayarları

    func testChangingFollowUpDaysRebuildsOpenTasks() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)

        try service(env).setFollowUpDays(quote, to: [10, 2, 2, 0, 400, -1], now: now)

        XCTAssertEqual(quote.followUpDays, [2, 10], "Geçersiz ve tekrarlayan günler atılır")
        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [TestCalendar.date(2026, 11, 27, 9), TestCalendar.date(2026, 12, 5, 9)])
        XCTAssertEqual(try tasks(env, .quoteExpiry).count, 1, "Geçerlilik uyarısına dokunulmaz")

        try service(env).setFollowUpDays(quote, to: [], now: now)
        XCTAssertTrue(quote.followUpDays.isEmpty)
        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [TestCalendar.date(2026, 11, 28, 9), TestCalendar.date(2026, 12, 2, 9)], "Boşsa Ayarlar'daki varsayılan")
    }

    func testCompletedFollowUpIsNotRecreatedWhenDaysChange() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)
        let done = try XCTUnwrap(try tasks(env, .quoteFollowUp).first { $0.dueDate == TestCalendar.date(2026, 11, 28, 9) })
        try env.repos.tasks.complete(done, at: now)

        try service(env).setFollowUpDays(quote, to: [3, 9], now: now)

        let open = try tasks(env, .quoteFollowUp).filter { !$0.isDone }
        XCTAssertEqual(open.map(\.dueDate), [TestCalendar.date(2026, 12, 4, 9)], "3. gün zaten tamamlandı, yalnız 9. gün kurulur")
    }

    func testFollowUpDaysInThePastAreSkipped() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, status: .sent)
        quote.sentAt = days(-5)

        try service(env).setFollowUpDays(quote, to: [3, 7, 10], now: now)

        XCTAssertEqual(try dueDates(env, .quoteFollowUp), [TestCalendar.date(2026, 11, 27, 9), TestCalendar.date(2026, 11, 30, 9)], "5. günden önceki 3. gün geçmişte kaldı")
    }

    func testChangingFollowUpDaysOfANonPendingQuoteCreatesNothing() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, status: .draft)
        try service(env).setFollowUpDays(quote, to: [2], now: now)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
        XCTAssertEqual(quote.followUpDays, [2], "Ayar kaydedilir, gönderilince kullanılır")
    }

    // MARK: Form kaydı ve sync

    func testEditingTheValidityDateMovesTheExpiryWarning() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, validDays: 20)
        try service(env).setStatus(quote, to: .sent, now: now)

        var draft = QuoteDraft()
        draft.number = "T-2026-001"
        draft.date = now
        draft.validUntil = days(30)
        draft.currency = .tl
        try service(env).save(draft, customer: try XCTUnwrap(quote.customer), existing: quote, now: now)

        XCTAssertEqual(try dueDates(env, .quoteExpiry), [TestCalendar.date(2026, 12, 22, 9)])
        XCTAssertEqual(try tasks(env, .quoteFollowUp).count, 2, "Takip görevleri form kaydıyla yeniden kurulmaz")
    }

    func testSyncCreatesMissingTasksForPendingQuotesAndIsIdempotent() throws {
        let env = try TestEnv()
        let quote = try addQuote(env, status: .sent)
        quote.sentAt = now

        try reminderService(env).sync(now: now)
        try reminderService(env).sync(now: now)

        XCTAssertEqual(try tasks(env, .quoteFollowUp).count, 2)
        XCTAssertEqual(try tasks(env, .quoteExpiry).count, 1)
    }

    func testSyncLeavesPostponedAndCompletedTasksAlone() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)
        let all = try tasks(env, .quoteFollowUp).sorted { $0.dueDate < $1.dueDate }
        let postponed = TestCalendar.date(2026, 12, 20, 9)
        try env.repos.tasks.postpone(all[0], to: postponed)
        try env.repos.tasks.complete(all[1], at: now)
        let expiry = try XCTUnwrap(try tasks(env, .quoteExpiry).first)
        try env.repos.tasks.postpone(expiry, to: postponed)

        try reminderService(env).sync(now: now)

        XCTAssertEqual(try tasks(env, .quoteFollowUp).count, 2, "Hiç görev kalmadıysa kurulurdu; var olanlar korunur")
        XCTAssertEqual(all[0].dueDate, postponed)
        XCTAssertTrue(all[1].isDone)
        XCTAssertEqual(expiry.dueDate, postponed)
    }

    func testSyncRemovesTasksOfQuotesThatAreNoLongerPending() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)
        quote.status = .won

        try reminderService(env).sync(now: now)

        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
    }

    func testDeletingAQuoteRemovesItsTasks() throws {
        let env = try TestEnv()
        let quote = try addQuote(env)
        try service(env).setStatus(quote, to: .sent, now: now)
        XCTAssertEqual(try env.repos.tasks.fetchAll().count, 3)

        try service(env).delete(quote)

        XCTAssertTrue(try env.repos.quotes.fetchAll().isEmpty)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty)
    }

    func testSettingsMapToReminderRules() {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.quoteReminderRules, rules)

        settings.quoteFollowUpDays = [2, 5, 10]
        settings.quoteExpiryWarningEnabled = false
        settings.quoteExpiryWarningDays = 5
        XCTAssertEqual(
            settings.quoteReminderRules,
            QuoteReminderRules(defaultFollowUpDays: [2, 5, 10], expiryEnabled: false, expiryDaysBefore: 5, reminderTime: TimeOfDay(hour: 9))
        )
    }

    // MARK: Fırsat

    func testWinningAQuoteOffersToWinTheLinkedOpportunity() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: "Hat 3", stage: .negotiation, expectedCloseDate: days(20))
        try env.repos.opportunities.add(opportunity, customer: customer)
        let quote = try addQuote(env, status: .sent, opportunity: opportunity, customer: customer)

        XCTAssertTrue(QuoteService.opportunityToWin(for: quote) === opportunity)
        try service(env).setStatus(quote, to: .won, now: now)
        XCTAssertEqual(opportunity.stage, .negotiation, "Soru onaylanana kadar fırsata dokunulmaz")

        // Kullanıcı "Evet" derse arayüz fırsat servisiyle Kazanıldı yapar.
        try OpportunityService(
            repositories: env.repos,
            reminderRules: OpportunityReminderRules(enabled: true, daysBefore: 7, reminderTime: TimeOfDay(hour: 9)),
            calendar: cal
        ).setStage(opportunity, to: .won, now: now)
        XCTAssertEqual(opportunity.stage, .won)
        XCTAssertNil(QuoteService.opportunityToWin(for: quote), "Zaten kazanılmış fırsat için sorulmaz")

        let unlinked = try addQuote(env, number: "T-2")
        XCTAssertNil(QuoteService.opportunityToWin(for: unlinked))
    }

    // MARK: Hatırlatma motoru ve widget

    func testSchedulerPlansQuoteRemindersAndDropsThemWhenLost() async throws {
        let env = try TestEnv()
        let quote = try addQuote(env, validDays: 20)
        quote.customer?.status = .passive
        try service(env).setStatus(quote, to: .sent, now: now)

        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.morningSummaryEnabled = false
        settings.endOfDayReminderEnabled = false
        settings.weekendNotificationsEnabled = true
        let mock = MockNotificationScheduler()
        let fixedNow = now
        let scheduler = ReminderScheduler(
            repositories: env.repos, settings: settings, scheduler: mock, calendar: cal, now: { fixedNow }
        )

        await scheduler.refresh()
        XCTAssertEqual(mock.lastPlan.map(\.fireDate), [
            TestCalendar.date(2026, 11, 28, 9), TestCalendar.date(2026, 12, 2, 9), TestCalendar.date(2026, 12, 12, 9)
        ])

        try service(env).setStatus(quote, to: .lost, lostReason: "Fiyat", now: now)
        await scheduler.refresh()
        XCTAssertTrue(mock.lastPlan.isEmpty)
    }

    func testWidgetPendingQuotesComeFromRealData() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()

        func quote(_ number: String, _ currency: Currency, _ price: Double, _ status: QuoteStatus) throws {
            let item = QuoteItem(quantity: 2, unitPrice: price)
            let created = Quote(quoteNumber: number, date: now, currency: currency, status: .draft)
            try env.repos.quotes.add(created, customer: customer, opportunity: nil)
            try env.repos.quoteItems.add(item, to: created)
            try service(env).setStatus(created, to: status, now: now)
        }
        try quote("A", .tl, 1_000, .sent)
        try quote("B", .tl, 500, .followUp)
        try quote("C", .usd, 100, .sent)
        try quote("D", .tl, 9_999, .draft)
        try quote("E", .tl, 9_999, .won)
        try quote("F", .eur, 9_999, .lost)

        var data = try WidgetDataLoader.load(repositories: env.repos)
        XCTAssertEqual(data.pendingQuoteCount, 3)
        XCTAssertEqual(data.pendingQuoteTotals, [WidgetMoney(currency: .tl, amount: 3_000), WidgetMoney(currency: .usd, amount: 200)])

        // Bekleyen bir teklif kazanılınca sayıdan düşer.
        let sent = try XCTUnwrap(try env.repos.quotes.fetchAll().first { $0.quoteNumber == "A" })
        try service(env).setStatus(sent, to: .won, now: now)
        data = try WidgetDataLoader.load(repositories: env.repos)
        XCTAssertEqual(data.pendingQuoteCount, 2)
        XCTAssertEqual(data.pendingQuoteTotals, [WidgetMoney(currency: .tl, amount: 1_000), WidgetMoney(currency: .usd, amount: 200)])
    }
}
