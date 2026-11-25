import XCTest
@testable import SahaSatis

final class AmountParserTests: XCTestCase {
    func testParsesTurkishAndDotNotations() {
        let cases: [(String, Double)] = [
            ("1250", 1250), ("1250.5", 1250.5), ("1250,5", 1250.5), ("1.250,50", 1250.5), ("1,250.50", 1250.5),
            ("1.250", 1250), ("1.250.000", 1_250_000), ("12.5", 12.5), ("1.50", 1.5), ("0.500", 0.5), ("0,5", 0.5),
            ("  125 000 ", 125_000), ("12.345,6", 12_345.6), ("1,2,3", 123), ("0", 0)
        ]
        for (text, expected) in cases {
            XCTAssertEqual(AmountParser.parse(text) ?? -1, expected, accuracy: 0.0001, text)
        }
    }

    func testRejectsInvalidInput() {
        for text in ["", "   ", "abc", "-5", ".", ",", "12a", "1e5", "₺100"] {
            XCTAssertNil(AmountParser.parse(text), text)
        }
    }

    func testEditingText() {
        XCTAssertEqual(AmountParser.editingText(0), "")
        XCTAssertEqual(AmountParser.editingText(1250), "1250")
        XCTAssertEqual(AmountParser.editingText(480_000), "480000")
        XCTAssertEqual(AmountParser.editingText(1250.5), "1250,5")
        XCTAssertEqual(AmountParser.parse(AmountParser.editingText(1250.5)), 1250.5, "Gidiş dönüş")
    }
}

final class PipelineGroupingTests: XCTestCase {
    private let cal = TestCalendar.utc

    private func opp(
        _ title: String,
        _ stage: OpportunityStage,
        value: Double = 0,
        currency: Currency = .tl,
        close: Date? = nil
    ) -> Opportunity {
        Opportunity(title: title, estimatedValue: value, currency: currency, stage: stage, expectedCloseDate: close)
    }

    func testGroupsFollowStageOrderAndSkipEmptyOnes() {
        let groups = PipelineGrouping.groups(from: [
            opp("K", .lost), opp("Y", .lead), opp("P", .negotiation), opp("W", .won), opp("T", .quoted), opp("N", .qualified)
        ])
        XCTAssertEqual(groups.map(\.stage), [.lead, .qualified, .quoted, .negotiation, .won, .lost])

        let sparse = PipelineGrouping.groups(from: [opp("A", .quoted), opp("B", .quoted)])
        XCTAssertEqual(sparse.map(\.stage), [.quoted])
        XCTAssertEqual(sparse.first?.count, 2)
        XCTAssertTrue(PipelineGrouping.groups(from: []).isEmpty)
    }

    func testTotalsAreSeparatePerCurrencyInFixedOrder() {
        let group = PipelineGrouping.groups(from: [
            opp("A", .quoted, value: 100_000, currency: .tl),
            opp("B", .quoted, value: 5_000, currency: .eur),
            opp("C", .quoted, value: 380_000, currency: .tl),
            opp("D", .quoted, value: 12_500, currency: .usd),
            opp("E", .quoted, value: 0, currency: .usd)
        ])[0]

        XCTAssertEqual(group.totals, [
            CurrencyTotal(currency: .tl, amount: 480_000),
            CurrencyTotal(currency: .usd, amount: 12_500),
            CurrencyTotal(currency: .eur, amount: 5_000)
        ])
        XCTAssertEqual(PipelineGrouping.summary(group.totals), "480.000 ₺ · 12.500 $ · 5.000 €")
        XCTAssertEqual(group.count, 5)
    }

    func testZeroValueGroupHasNoTotals() {
        let group = PipelineGrouping.groups(from: [opp("A", .lead), opp("B", .lead)])[0]
        XCTAssertTrue(group.totals.isEmpty)
        XCTAssertEqual(PipelineGrouping.summary(group.totals), "")
    }

    func testOrderWithinGroupIsByCloseDateThenTitle() {
        let soon = TestCalendar.date(2026, 12, 1)
        let later = TestCalendar.date(2026, 12, 20)
        let group = PipelineGrouping.groups(from: [
            opp("Tarihsiz Z", .lead), opp("Geç", .lead, close: later), opp("Tarihsiz Ç", .lead),
            opp("Yakın B", .lead, close: soon), opp("Yakın A", .lead, close: soon)
        ])[0]
        XCTAssertEqual(group.opportunities.map(\.title), ["Yakın A", "Yakın B", "Geç", "Tarihsiz Ç", "Tarihsiz Z"])
    }

    @MainActor
    func testWonAndLostGroupsStartCollapsed() throws {
        let env = try TestEnv()
        let model = PipelineModel(repositories: env.repos)
        XCTAssertFalse(model.isExpanded(.won))
        XCTAssertFalse(model.isExpanded(.lost))
        for stage in [OpportunityStage.lead, .qualified, .quoted, .negotiation] {
            XCTAssertTrue(model.isExpanded(stage), stage.title)
        }
        model.toggle(.won)
        XCTAssertTrue(model.isExpanded(.won))
        model.toggle(.lead)
        XCTAssertFalse(model.isExpanded(.lead))
    }

    @MainActor
    func testModelLoadsGroupsFromRepository() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try env.repos.opportunities.add(Opportunity(title: "A", estimatedValue: 10, stage: .quoted), customer: customer)
        try env.repos.opportunities.add(Opportunity(title: "B", stage: .won), customer: customer)

        let model = PipelineModel(repositories: env.repos)
        model.reload()

        XCTAssertEqual(model.groups.map(\.stage), [.quoted, .won])
    }
}

/// Kapanış tarihi hatırlatması: vade hesabı, kurma/silme/güncelleme kuralları.
@MainActor
final class OpportunityReminderTests: XCTestCase {
    private let cal = TestCalendar.utc
    /// Çarşamba 12:00.
    private let now = TestCalendar.date(2026, 11, 25, 12)

    private var rules: OpportunityReminderRules {
        OpportunityReminderRules(enabled: true, daysBefore: 7, reminderTime: TimeOfDay(hour: 9))
    }

    private func days(_ n: Int) -> Date {
        cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: now))!
    }

    private func service(_ env: TestEnv, rules: OpportunityReminderRules? = nil) -> OpportunityReminderService {
        OpportunityReminderService(repositories: env.repos, rules: rules ?? self.rules, calendar: cal)
    }

    private func opportunityService(_ env: TestEnv, rules: OpportunityReminderRules? = nil) -> OpportunityService {
        OpportunityService(repositories: env.repos, reminderRules: rules ?? self.rules, calendar: cal)
    }

    private func reminders(_ env: TestEnv, for opportunity: Opportunity? = nil) throws -> [FollowUpTask] {
        try env.repos.tasks.fetchAll().filter {
            $0.source == .opportunityClose && (opportunity == nil || $0.opportunity?.id == opportunity?.id)
        }
    }

    @discardableResult
    private func addOpportunity(
        _ env: TestEnv,
        _ title: String = "Hat 3 PLC yenileme",
        stage: OpportunityStage = .quoted,
        close: Date?
    ) throws -> Opportunity {
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: title, stage: stage, expectedCloseDate: close)
        try env.repos.opportunities.add(opportunity, customer: customer)
        return opportunity
    }

    // MARK: Vade

    func testDueDateIsCloseDayMinusDaysAtReminderTime() {
        let due = OpportunityReminderService.dueDate(
            closeDate: days(20), daysBefore: 7, reminderTime: TimeOfDay(hour: 9, minute: 30), now: now, calendar: cal
        )
        XCTAssertEqual(due, TestCalendar.date(2026, 12, 8, 9, 30))
    }

    func testCloseDateInsideTheWindowIsClampedToToday() {
        let due = OpportunityReminderService.dueDate(
            closeDate: days(3), daysBefore: 7, reminderTime: TimeOfDay(hour: 9), now: now, calendar: cal
        )
        XCTAssertEqual(due, TestCalendar.date(2026, 11, 25, 9))
        XCTAssertEqual(
            OpportunityReminderService.dueDate(closeDate: days(0), daysBefore: 7, reminderTime: TimeOfDay(hour: 9), now: now, calendar: cal),
            TestCalendar.date(2026, 11, 25, 9),
            "Kapanış bugünse hatırlatma bugün"
        )
    }

    func testPastCloseDateGetsNoReminder() {
        XCTAssertNil(OpportunityReminderService.dueDate(
            closeDate: days(-1), daysBefore: 7, reminderTime: TimeOfDay(hour: 9), now: now, calendar: cal
        ))
    }

    func testNoReminderForDisabledClosedOrDatelessOpportunities() {
        let open = Opportunity(title: "A", stage: .qualified, expectedCloseDate: days(20))
        XCTAssertNotNil(OpportunityReminderService.dueDate(for: open, rules: rules, now: now, calendar: cal))

        var off = rules
        off.enabled = false
        XCTAssertNil(OpportunityReminderService.dueDate(for: open, rules: off, now: now, calendar: cal))
        for stage in [OpportunityStage.won, .lost] {
            let closed = Opportunity(title: "B", stage: stage, expectedCloseDate: days(20))
            XCTAssertNil(OpportunityReminderService.dueDate(for: closed, rules: rules, now: now, calendar: cal), stage.title)
        }
        XCTAssertNil(OpportunityReminderService.dueDate(
            for: Opportunity(title: "C", stage: .lead), rules: rules, now: now, calendar: cal
        ))
    }

    func testTitleMentionsOpportunityAndCloseDate() {
        let opportunity = Opportunity(title: "Hat 3 PLC yenileme", expectedCloseDate: TestCalendar.date(2026, 12, 15))
        let title = OpportunityReminderService.title(for: opportunity)
        XCTAssertTrue(title.hasPrefix("Fırsat kapanışı yaklaşıyor: Hat 3 PLC yenileme ("), title)
        XCTAssertTrue(title.contains("Ara 2026"), title)
    }

    // MARK: sync / refresh

    func testSyncCreatesOneLinkedReminderAndIsIdempotent() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))

        try service(env).sync(now: now)
        try service(env).sync(now: now)

        let tasks = try reminders(env)
        XCTAssertEqual(tasks.count, 1)
        let task = try XCTUnwrap(tasks.first)
        XCTAssertEqual(task.dueDate, TestCalendar.date(2026, 12, 8, 9))
        XCTAssertEqual(task.opportunity?.id, opportunity.id)
        XCTAssertEqual(task.customer?.id, opportunity.customer?.id)
        XCTAssertFalse(task.isDone)
    }

    func testSyncSkipsClosedAndDatelessOpportunities() throws {
        let env = try TestEnv()
        try addOpportunity(env, "Kazanıldı", stage: .won, close: days(20))
        try addOpportunity(env, "Kaybedildi", stage: .lost, close: days(20))
        try addOpportunity(env, "Tarihsiz", stage: .lead, close: nil)
        try addOpportunity(env, "Geçmiş", stage: .quoted, close: days(-3))

        try service(env).sync(now: now)

        XCTAssertTrue(try reminders(env).isEmpty)
    }

    func testSyncRemovesRemindersOfOpportunitiesThatAreNoLongerEligible() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))
        try service(env).sync(now: now)
        XCTAssertEqual(try reminders(env).count, 1)

        opportunity.stage = .won
        try service(env).sync(now: now)

        XCTAssertTrue(try reminders(env).isEmpty)
    }

    func testSyncLeavesAnExistingReminderAloneEvenIfPostponed() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))
        try service(env).sync(now: now)
        let task = try XCTUnwrap(try reminders(env, for: opportunity).first)
        let postponed = TestCalendar.date(2026, 12, 12, 9)
        try env.repos.tasks.postpone(task, to: postponed)

        try service(env).sync(now: now)

        XCTAssertEqual(try reminders(env).count, 1)
        XCTAssertEqual(task.dueDate, postponed)
    }

    func testCompletedReminderIsNotRecreatedForTheSameDueDate() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))
        try service(env).sync(now: now)
        let task = try XCTUnwrap(try reminders(env, for: opportunity).first)
        try env.repos.tasks.complete(task, at: now)

        try service(env).sync(now: now)

        XCTAssertEqual(try reminders(env).count, 1, "Tamamlanan hatırlatma yeniden açılmaz")
    }

    func testRefreshMovesTheReminderWhenTheCloseDateChanges() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))
        try service(env).sync(now: now)

        opportunity.expectedCloseDate = days(30)
        try service(env).refresh(opportunity, now: now)

        let task = try XCTUnwrap(try reminders(env).first)
        XCTAssertEqual(try reminders(env).count, 1)
        XCTAssertEqual(task.dueDate, TestCalendar.date(2026, 12, 18, 9))
    }

    func testDisablingTheSettingCancelsOpenReminders() throws {
        let env = try TestEnv()
        try addOpportunity(env, close: days(20))
        try service(env).sync(now: now)
        var off = rules
        off.enabled = false

        try service(env, rules: off).sync(now: now)

        XCTAssertTrue(try reminders(env).isEmpty)
    }

    func testDaysBeforeSettingIsUsed() throws {
        let env = try TestEnv()
        try addOpportunity(env, close: days(20))
        var custom = rules
        custom.daysBefore = 2

        try service(env, rules: custom).sync(now: now)

        XCTAssertEqual(try reminders(env).first?.dueDate, TestCalendar.date(2026, 12, 13, 9))
    }

    // MARK: Aşama değişince

    func testWinningOrLosingCancelsThePendingReminder() throws {
        for stage in [OpportunityStage.won, .lost] {
            let env = try TestEnv()
            let opportunity = try addOpportunity(env, close: days(20))
            try service(env).sync(now: now)
            XCTAssertEqual(try reminders(env).count, 1)

            try opportunityService(env).setStage(opportunity, to: stage, lostReason: stage == .lost ? "Fiyat" : nil, now: now)

            XCTAssertTrue(try reminders(env).isEmpty, stage.title)
        }
    }

    func testReopeningRestoresTheReminder() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))
        let opportunities = opportunityService(env)
        try opportunities.setStage(opportunity, to: .won, now: now)
        XCTAssertTrue(try reminders(env).isEmpty)

        try opportunities.setStage(opportunity, to: .negotiation, now: now)

        XCTAssertEqual(try reminders(env).count, 1)
    }

    func testRepositoryCancelOpenTasksForOpportunityKeepsOthers() throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, close: days(20))
        let other = try addOpportunity(env, "Diğer", close: days(25))
        try service(env).sync(now: now)
        let done = FollowUpTask(title: "Bitti", dueDate: now, source: .manual)
        try env.repos.tasks.add(done, customer: nil, quote: nil, visit: nil, opportunity: opportunity)
        try env.repos.tasks.complete(done, at: now)

        try env.repos.tasks.cancelOpenTasks(for: opportunity)

        XCTAssertTrue(try reminders(env, for: opportunity).isEmpty)
        XCTAssertEqual(try reminders(env, for: other).count, 1)
        XCTAssertTrue(try env.repos.tasks.fetchAll().contains { $0.id == done.id }, "Tamamlanmış görev korunur")
    }

    // MARK: Hatırlatma motoru

    func testSchedulerPlansTheReminderAndDropsItWhenWon() async throws {
        let env = try TestEnv()
        let opportunity = try addOpportunity(env, "Hat 3 PLC yenileme", close: days(20))
        opportunity.customer?.status = .passive
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.morningSummaryEnabled = false
        settings.endOfDayReminderEnabled = false
        let mock = MockNotificationScheduler()
        let fixedNow = now
        let scheduler = ReminderScheduler(
            repositories: env.repos, settings: settings, scheduler: mock, calendar: cal, now: { fixedNow }
        )

        await scheduler.refresh()

        let planned = try XCTUnwrap(mock.lastPlan.first)
        XCTAssertEqual(mock.lastPlan.count, 1)
        XCTAssertEqual(planned.fireDate, TestCalendar.date(2026, 12, 8, 9))
        XCTAssertTrue(planned.body.hasPrefix("Fırsat kapanışı yaklaşıyor: Hat 3 PLC yenileme"), planned.body)

        try opportunityService(env).setStage(opportunity, to: .won, now: now)
        await scheduler.refresh()

        XCTAssertTrue(mock.lastPlan.isEmpty, "Kazanılan fırsatın hatırlatması planlanmaz")
    }

    func testSettingsDefaultsAndRules() {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.defaultCurrency, .tl)
        XCTAssertTrue(settings.opportunityCloseReminderEnabled)
        XCTAssertEqual(settings.opportunityCloseReminderDays, 7)
        XCTAssertEqual(settings.opportunityReminderRules, OpportunityReminderRules(enabled: true, daysBefore: 7, reminderTime: TimeOfDay(hour: 9)))

        settings.defaultCurrency = .eur
        settings.opportunityCloseReminderDays = 10
        settings.opportunityCloseReminderEnabled = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.defaultCurrency, .eur)
        XCTAssertEqual(reloaded.opportunityCloseReminderDays, 10)
        XCTAssertFalse(reloaded.opportunityCloseReminderEnabled)
        XCTAssertEqual(reloaded.opportunityReminderRules.daysBefore, 10)
    }
}

/// Fırsat servisi ve formu.
@MainActor
final class OpportunityServiceTests: XCTestCase {
    private let cal = TestCalendar.utc
    private let now = TestCalendar.date(2026, 11, 25, 12)

    private func service(_ env: TestEnv) -> OpportunityService {
        OpportunityService(
            repositories: env.repos,
            reminderRules: OpportunityReminderRules(enabled: true, daysBefore: 7, reminderTime: TimeOfDay(hour: 9)),
            calendar: cal
        )
    }

    private func formModel(
        _ env: TestEnv,
        defaultCurrency: Currency = .tl,
        opportunity: Opportunity? = nil,
        customer: Customer? = nil
    ) -> OpportunityFormModel {
        OpportunityFormModel(
            repositories: env.repos,
            reminderRules: OpportunityReminderRules(enabled: true, daysBefore: 7, reminderTime: TimeOfDay(hour: 9)),
            defaultCurrency: defaultCurrency,
            opportunity: opportunity,
            customer: customer,
            calendar: cal,
            now: now
        )
    }

    func testSaveCreatesTrimmedOpportunityLinkedToTheCustomer() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        var draft = OpportunityDraft()
        draft.title = "  Hat 3\nPLC  yenileme "
        draft.details = "  Ayrıntı \n"
        draft.estimatedValue = 125_000
        draft.currency = .usd
        draft.stage = .qualified
        draft.expectedCloseDate = TestCalendar.date(2026, 12, 20)
        draft.lostReason = "Görmezden gelinir"

        let saved = try service(env).save(draft, customer: customer, existing: nil, now: now)

        XCTAssertEqual(saved.title, "Hat 3 PLC yenileme")
        XCTAssertEqual(saved.details, "Ayrıntı")
        XCTAssertEqual(saved.estimatedValue, 125_000)
        XCTAssertEqual(saved.currency, .usd)
        XCTAssertEqual(saved.stage, .qualified)
        XCTAssertEqual(saved.lostReason, "", "Kayıp sebebi yalnızca Kaybedildi iken saklanır")
        XCTAssertEqual(saved.customer?.id, customer.id)
        XCTAssertEqual(saved.ownerUserID, "test-user")
        XCTAssertEqual(try env.repos.opportunities.opportunities(for: customer).count, 1)
    }

    func testSaveEditsInPlaceAndKeepsLostReasonOnlyWhenLost() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let existing = Opportunity(title: "Eski", estimatedValue: 10, stage: .lead)
        try env.repos.opportunities.add(existing, customer: customer)

        var draft = OpportunityDraft()
        draft.title = "Yeni başlık"
        draft.stage = .lost
        draft.lostReason = "  Rakip\nfiyatı "
        let saved = try service(env).save(draft, customer: customer, existing: existing, now: now)

        XCTAssertTrue(saved === existing)
        XCTAssertEqual(existing.title, "Yeni başlık")
        XCTAssertEqual(existing.lostReason, "Rakip fiyatı")
        XCTAssertEqual(try env.repos.opportunities.fetchAll().count, 1)
    }

    func testSetStageLostStoresReasonAndReopeningClearsIt() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: "A", stage: .negotiation)
        try env.repos.opportunities.add(opportunity, customer: customer)

        try service(env).setStage(opportunity, to: .lost, lostReason: "  Bütçe\nyok ", now: now)
        XCTAssertEqual(opportunity.stage, .lost)
        XCTAssertEqual(opportunity.lostReason, "Bütçe yok")

        try service(env).setStage(opportunity, to: .qualified, now: now)
        XCTAssertEqual(opportunity.stage, .qualified)
        XCTAssertEqual(opportunity.lostReason, "")
    }

    func testDeletingAnOpportunityRemovesItsReminderButKeepsVisits() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let opportunity = Opportunity(title: "A", stage: .quoted, expectedCloseDate: TestCalendar.date(2026, 12, 20))
        try env.repos.opportunities.add(opportunity, customer: customer)
        let visit = Visit(date: now)
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: opportunity)
        try OpportunityReminderService(
            repositories: env.repos,
            rules: OpportunityReminderRules(enabled: true, daysBefore: 7, reminderTime: TimeOfDay(hour: 9)),
            calendar: cal
        ).sync(now: now)
        XCTAssertEqual(try env.repos.tasks.fetchAll().count, 1)

        try service(env).delete(opportunity)

        XCTAssertTrue(try env.repos.opportunities.fetchAll().isEmpty)
        XCTAssertTrue(try env.repos.tasks.fetchAll().isEmpty, "Fırsatın hatırlatma görevi de silinir")
        XCTAssertNil(visit.opportunity)
        XCTAssertEqual(try env.repos.visits.fetchAll().count, 1, "Ziyaret kalır")
    }

    // MARK: Form modeli

    func testNewFormUsesTheDefaultCurrencyAndRequiresCustomerAndTitle() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = formModel(env, defaultCurrency: .eur)

        XCTAssertEqual(model.currency, .eur)
        XCTAssertEqual(model.stage, .lead)
        XCTAssertFalse(model.hasCloseDate)
        XCTAssertFalse(model.canSave)

        model.title = "  "
        model.customer = customer
        XCTAssertFalse(model.canSave)
        model.title = "Fırsat"
        XCTAssertTrue(model.canSave)
    }

    func testAmountValidation() throws {
        let env = try TestEnv()
        let model = formModel(env, customer: try env.makeCustomer())
        model.title = "Fırsat"

        XCTAssertEqual(model.amountValue, 0, "Boş tutar 0")
        model.amountText = "1.250,50"
        XCTAssertEqual(model.amountValue, 1250.5)
        model.amountText = "abc"
        XCTAssertNil(model.amountValue)
        XCTAssertFalse(model.canSave)
    }

    func testFormSavesAllFields() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = formModel(env, customer: customer)
        model.title = "Dolum hattı"
        model.details = "Yeni hat"
        model.amountText = "12.500"
        model.currency = .usd
        model.stage = .qualified
        model.hasCloseDate = true
        model.closeDate = TestCalendar.date(2026, 12, 30, 15)

        XCTAssertTrue(model.save())

        let saved = try XCTUnwrap(model.savedOpportunity)
        XCTAssertEqual(saved.estimatedValue, 12_500)
        XCTAssertEqual(saved.currency, .usd)
        XCTAssertEqual(saved.expectedCloseDate, TestCalendar.date(2026, 12, 30, 0), "Gün başına yuvarlanır")
        XCTAssertEqual(saved.customer?.id, customer.id)
    }

    func testEditFormLoadsValuesAndAsksForLostReason() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let existing = Opportunity(
            title: "Kayıp", details: "d", estimatedValue: 54_000, currency: .eur, stage: .lost,
            expectedCloseDate: TestCalendar.date(2026, 10, 1)
        )
        existing.lostReason = "Fiyat"
        try env.repos.opportunities.add(existing, customer: customer)

        let model = formModel(env, defaultCurrency: .tl, opportunity: existing)

        XCTAssertTrue(model.isEditing)
        XCTAssertEqual(model.customer?.id, customer.id)
        XCTAssertEqual(model.currency, .eur, "Düzenlemede kayıtlı para birimi, varsayılan değil")
        XCTAssertEqual(model.amountText, "54000")
        XCTAssertEqual(model.stage, .lost)
        XCTAssertTrue(model.asksLostReason)
        XCTAssertEqual(model.lostReason, "Fiyat")
        XCTAssertTrue(model.hasCloseDate)

        model.stage = .negotiation
        XCTAssertFalse(model.asksLostReason)
        XCTAssertTrue(model.save())
        XCTAssertEqual(existing.lostReason, "")
    }

    // MARK: Ziyaret ↔ fırsat

    private func visitModel(_ env: TestEnv, customer: Customer?, visit: Visit? = nil, currency: Currency = .tl) -> VisitFormModel {
        VisitFormModel(
            repositories: env.repos, reminderMinutes: 540, defaultCurrency: currency,
            engine: MockSpeechEngine(), customer: customer, visit: visit
        )
    }

    func testVisitCanLinkToAnExistingOpportunity() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let open = Opportunity(title: "Açık", stage: .quoted)
        let closed = Opportunity(title: "Kapalı", stage: .won)
        let otherCustomer = try env.makeCustomer("Başka")
        let foreign = Opportunity(title: "Başkasının", stage: .lead)
        try env.repos.opportunities.add(open, customer: customer)
        try env.repos.opportunities.add(closed, customer: customer)
        try env.repos.opportunities.add(foreign, customer: otherCustomer)

        let model = visitModel(env, customer: customer)
        XCTAssertEqual(model.availableOpportunities.map(\.title), ["Açık"], "Yalnızca müşterinin açık fırsatları")

        model.opportunityLink = .existing(open.id)
        XCTAssertTrue(model.save())

        let visit = try XCTUnwrap(try env.repos.visits.fetchAll().first)
        XCTAssertEqual(visit.opportunity?.id, open.id)
        XCTAssertEqual(open.visits?.count, 1)
    }

    func testVisitCanOpenANewOpportunityWithTheDefaultCurrency() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let model = visitModel(env, customer: customer, currency: .eur)

        model.opportunityLink = .new
        XCTAssertFalse(model.canSave, "Yeni fırsat başlığı boşken kaydedilemez")
        model.newOpportunityTitle = "  Yeni\nfırsat "
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.save())

        let created = try XCTUnwrap(try env.repos.opportunities.opportunities(for: customer).first)
        XCTAssertEqual(created.title, "Yeni fırsat")
        XCTAssertEqual(created.stage, .lead)
        XCTAssertEqual(created.currency, .eur)
        XCTAssertEqual(try env.repos.visits.fetchAll().first?.opportunity?.id, created.id)
    }

    func testEditingAVisitCanUnlinkOrKeepAClosedOpportunity() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let won = Opportunity(title: "Kazanılan", stage: .won)
        try env.repos.opportunities.add(won, customer: customer)
        let visit = Visit(date: now)
        try env.repos.visits.add(visit, customer: customer, contacts: [], opportunity: won)

        let model = visitModel(env, customer: customer, visit: visit)
        XCTAssertEqual(model.opportunityLink, .existing(won.id))
        XCTAssertEqual(model.availableOpportunities.map(\.title), ["Kazanılan"], "Bağlı olan kapalı olsa da listelenir")

        model.opportunityLink = .none
        XCTAssertTrue(model.save())
        XCTAssertNil(visit.opportunity)
    }

    func testChangingCustomerResetsTheOpportunityChoice() throws {
        let env = try TestEnv()
        let first = try env.makeCustomer("Birinci")
        let second = try env.makeCustomer("İkinci")
        let opportunity = Opportunity(title: "A", stage: .lead)
        try env.repos.opportunities.add(opportunity, customer: first)
        let model = visitModel(env, customer: first)
        model.opportunityLink = .existing(opportunity.id)
        model.newOpportunityTitle = "x"

        model.customer = second
        model.customerChanged()

        XCTAssertEqual(model.opportunityLink, .none)
        XCTAssertEqual(model.newOpportunityTitle, "")
        XCTAssertTrue(model.availableOpportunities.isEmpty)
    }

    func testRowTitleFallbacks() {
        XCTAssertEqual(TaskSource.opportunityClose.title, "Fırsat kapanış tarihi")
        XCTAssertEqual(TaskSource.opportunityClose.systemImage, "flag")
        XCTAssertEqual(Currency.allCases.map(\.displayName), ["TL", "USD", "EUR"])
    }
}
