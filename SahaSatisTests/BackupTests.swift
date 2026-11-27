import SwiftData
import XCTest
@testable import SahaSatis

/// Yedekleme: tek JSON dosyası, geri yükleme, ayarlar ve "yedek eski" uyarısı.
@MainActor
final class BackupTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_800_000_000.123)

    private func makeSettings() -> SahaSatis.AppSettings {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return SahaSatis.AppSettings(defaults: defaults)
    }

    private func repository(_ env: TestEnv) -> SwiftDataBackupRepository {
        SwiftDataBackupRepository(context: env.context)
    }

    /// Her modelden en az bir kayıt ve tüm ilişkiler.
    private func fill(_ env: TestEnv) throws {
        let customer = try env.makeCustomer("Örnek Makina A.Ş.")
        customer.district = "Nilüfer"
        customer.latitude = 40.21
        customer.ratingNote = "Türkçe: ğüşıöç İ"
        try env.repos.customers.update(customer)

        let contact = Contact(fullName: "Ahmet Yılmaz", title: "Bakım Müdürü", phone: "0532 000 00 00")
        try env.repos.contacts.add(contact, to: customer)

        let opportunity = Opportunity(title: "Hat 3", estimatedValue: 1234.56, currency: .usd, expectedCloseDate: day)
        try env.repos.opportunities.add(opportunity, customer: customer)

        let quote = Quote(quoteNumber: "T-1", date: day, validUntil: day, currency: .eur, status: .sent, followUpDays: [2, 5])
        try env.repos.quotes.add(quote, customer: customer, opportunity: opportunity)
        try env.repos.quoteItems.add(
            QuoteItem(catalogNumber: "1756-L71", quantity: 2, unitPrice: 99.9, discountPercent: 12.5), to: quote
        )

        let visit = Visit(date: day, type: .online, transcript: "ham", summary: "özet", topic: "konu",
                          topics: ["a", "b"], nextStep: "ara", nextStepDate: day)
        visit.exportedToCRM = true
        visit.exportedAt = day
        try env.repos.visits.add(visit, customer: customer, contacts: [contact], opportunity: opportunity)

        try env.repos.installedProducts.add(
            InstalledProduct(catalogNumber: "1747-L551", productFamily: "SLC 500", quantity: 3,
                             lifecycleStatus: .endOfLife),
            to: customer
        )
        try env.repos.tasks.add(
            FollowUpTask(title: "Takip", dueDate: day, source: .quoteFollowUp),
            customer: customer, quote: quote, visit: visit, opportunity: opportunity
        )
    }

    private func file(_ data: BackupData, settings: BackupSettings? = nil) -> BackupFile {
        BackupFile(createdAt: day, appVersion: "0.1.0 (1)", data: data, settings: settings)
    }

    func testSnapshotContainsEveryModel() throws {
        let env = try TestEnv()
        try fill(env)
        let data = try repository(env).snapshot()
        XCTAssertEqual(data.customers.count, 1)
        XCTAssertEqual(data.contacts.count, 1)
        XCTAssertEqual(data.visits.count, 1)
        XCTAssertEqual(data.opportunities.count, 1)
        XCTAssertEqual(data.quotes.count, 1)
        XCTAssertEqual(data.quoteItems.count, 1)
        XCTAssertEqual(data.installedProducts.count, 1)
        XCTAssertEqual(data.tasks.count, 1)
    }

    /// Model sayısı artarsa yedek de güncellenmeli.
    func testSchemaModelCountMatchesBackup() {
        XCTAssertEqual(Persistence.schema.entities.count, Mirror(reflecting: BackupData()).children.count)
    }

    /// Modele yeni alan eklenip yedeğe eklenmezse burada yakalanır.
    func testEveryStoredAttributeIsBackedUp() throws {
        let env = try TestEnv()
        try fill(env)
        let data = try repository(env).snapshot()
        let records: [String: Any] = [
            "Customer": data.customers[0], "Contact": data.contacts[0], "Visit": data.visits[0],
            "Opportunity": data.opportunities[0], "Quote": data.quotes[0], "QuoteItem": data.quoteItems[0],
            "InstalledProduct": data.installedProducts[0], "FollowUpTask": data.tasks[0]
        ]
        for entity in Persistence.schema.entities {
            let record = try XCTUnwrap(records[entity.name], "yedekte yok: \(entity.name)")
            let fields = Set(Mirror(reflecting: record).children.compactMap(\.label))
            for attribute in entity.attributes {
                XCTAssertTrue(fields.contains(attribute.name), "\(entity.name).\(attribute.name) yedekte yok")
            }
        }
    }

    func testFileRoundTripIsLossless() throws {
        let env = try TestEnv()
        try fill(env)
        let original = file(try repository(env).snapshot(), settings: BackupSettings(makeSettings()))
        let decoded = try BackupCodec.decode(try BackupCodec.encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testRestoreIntoEmptyStoreRebuildsDataAndRelationships() throws {
        let source = try TestEnv()
        try fill(source)
        let data = try repository(source).snapshot()
        let decoded = try BackupCodec.decode(try BackupCodec.encode(file(data)))

        let target = try TestEnv()
        try repository(target).replaceAll(with: decoded.data)

        XCTAssertEqual(try repository(target).snapshot(), data)
        let customer = try XCTUnwrap(try target.repos.customers.fetchAll().first)
        XCTAssertEqual(customer.contacts?.count, 1)
        XCTAssertEqual(customer.visits?.count, 1)
        XCTAssertEqual(customer.tasks?.count, 1)
        XCTAssertTrue(customer.hasMigrationOpportunity)
        let quote = try XCTUnwrap(try target.repos.quotes.fetchAll().first)
        XCTAssertEqual(quote.items?.count, 1)
        XCTAssertEqual(quote.opportunity?.title, "Hat 3")
        let visit = try XCTUnwrap(try target.repos.visits.fetchAll().first)
        XCTAssertEqual(visit.contacts?.map(\.fullName), ["Ahmet Yılmaz"])
    }

    func testRestoreReplacesExistingData() throws {
        let source = try TestEnv()
        try fill(source)
        let data = try repository(source).snapshot()

        let target = try TestEnv()
        try fill(target)
        try target.makeCustomer("Silinecek Müşteri")
        try repository(target).replaceAll(with: data)

        XCTAssertEqual(try repository(target).snapshot(), data)
        XCTAssertEqual(try target.repos.customers.fetchAll().map(\.name), ["Örnek Makina A.Ş."])
    }

    /// Aynı cihazda alınan yedek aynı kimliklerle geri yüklenebilmeli.
    func testRestoreOfOwnBackupKeepsData() throws {
        let env = try TestEnv()
        try fill(env)
        let data = try repository(env).snapshot()
        try repository(env).replaceAll(with: data)
        XCTAssertEqual(try repository(env).snapshot(), data)
    }

    func testRestoreEmptyBackupClearsStore() throws {
        let env = try TestEnv()
        try fill(env)
        try repository(env).replaceAll(with: BackupData())
        XCTAssertEqual(try repository(env).snapshot(), BackupData())
    }

    func testUnknownReferenceIsLeftEmpty() throws {
        let env = try TestEnv()
        try fill(env)
        var data = try repository(env).snapshot()
        data.contacts[0].customerID = UUID()
        data.visits[0].contactIDs = [UUID()]
        try repository(env).replaceAll(with: data)
        XCTAssertNil(try repository(env).snapshot().contacts[0].customerID)
        XCTAssertEqual(try repository(env).snapshot().visits[0].contactIDs, [])
    }

    func testDecodeRejectsForeignDamagedAndNewerFiles() throws {
        func decodeError(_ text: String) -> BackupError? {
            do {
                _ = try BackupCodec.decode(Data(text.utf8))
                return nil
            } catch {
                return error as? BackupError
            }
        }
        XCTAssertEqual(decodeError("merhaba"), .notABackup)
        XCTAssertEqual(decodeError("{\"name\":\"x\"}"), .notABackup)
        XCTAssertEqual(decodeError("{\"format\":\"baska\",\"version\":1}"), .notABackup)
        XCTAssertEqual(decodeError("{\"format\":\"sahasatis-backup\",\"version\":99}"), .newerVersion)
        XCTAssertEqual(decodeError("{\"format\":\"sahasatis-backup\",\"version\":1}"), .damaged)
    }

    func testSettingsRoundTrip() {
        let source = makeSettings()
        source.fullName = "Örnek Kişi"
        source.responsibleCities = ["Bursa"]
        source.defaultReminderTime = TimeOfDay(hour: 7, minute: 45)
        source.weekendNotificationsEnabled = true
        source.quoteFollowUpDays = [2, 9]
        source.defaultCurrency = .eur
        source.cityPlan = ["2026-11-30": ["Bursa"]]
        source.productFamilies = []
        source.claudeInstruction = "Kendi talimatım"
        let backup = BackupSettings(source)

        let target = makeSettings()
        backup.apply(to: target)
        XCTAssertEqual(BackupSettings(target), backup)
        XCTAssertEqual(target.claudeInstruction, "Kendi talimatım")
        XCTAssertEqual(target.productFamilies, [])
    }

    func testMissingSettingsFieldsKeepCurrentValues() {
        let target = makeSettings()
        target.fullName = "Mevcut"
        target.claudeInstruction = "eski özel talimat"
        BackupSettings().apply(to: target)
        XCTAssertEqual(target.fullName, "Mevcut")
        XCTAssertEqual(target.claudeInstruction, SahaSatis.AppSettings.defaultClaudeInstruction,
                       "yedekte talimat yoksa varsayılan kullanılıyordu")
    }

    func testLastBackupDateIsPersisted() {
        let name = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let settings = SahaSatis.AppSettings(defaults: defaults)
        XCTAssertNil(settings.lastBackupAt)
        settings.lastBackupAt = day
        XCTAssertEqual(SahaSatis.AppSettings(defaults: defaults).lastBackupAt, day)
        defaults.removePersistentDomain(forName: name)
    }

    func testContextRestoreAppliesDataSettingsAndClearsDraft() async throws {
        let source = try TestEnv()
        try fill(source)
        let sourceSettings = makeSettings()
        sourceSettings.fullName = "Yedekteki Kişi"
        let backup = file(try repository(source).snapshot(), settings: BackupSettings(sourceSettings))

        let target = try TestEnv()
        var draft = VisitFormDraft()
        draft.note = "eski veriye ait"
        let drafts = InMemoryVisitDraftStore(draft: draft)
        let context = AppContext(
            repositories: target.repos,
            settings: makeSettings(),
            makeSpeechEngine: { MockSpeechEngine() },
            notificationScheduler: MockNotificationScheduler(),
            draftStore: drafts,
            backups: repository(target)
        )
        await context.restore(backup, pause: .zero)

        XCTAssertEqual(try target.repos.customers.fetchAll().count, 1)
        XCTAssertEqual(context.settings.fullName, "Yedekteki Kişi")
        XCTAssertNil(drafts.draft)
        XCTAssertNil(context.pendingDraft)
        XCTAssertFalse(context.isRestoring)
        XCTAssertEqual(context.requestedTab, .settings)
        XCTAssertEqual(context.restoreResult, "Yedek geri yüklendi: 1 müşteri, 1 ziyaret.")
        XCTAssertEqual(try context.makeBackup(now: day).data, backup.data)
    }

    func testFileName() {
        XCTAssertEqual(
            BackupCodec.fileName(for: TestCalendar.date(2026, 11, 7, 9, 5), calendar: TestCalendar.utc),
            "SahaSatis-Yedek-2026-11-07-0905.json"
        )
    }

    func testReminder() {
        let now = TestCalendar.date(2026, 11, 27, 12)
        func evaluate(_ last: Date?, hasData: Bool = true) -> BackupReminder? {
            BackupReminder.evaluate(lastBackup: last, hasData: hasData, now: now, calendar: TestCalendar.utc)
        }
        XCTAssertEqual(evaluate(nil), .never)
        XCTAssertNil(evaluate(nil, hasData: false))
        XCTAssertNil(evaluate(now))
        XCTAssertNil(evaluate(TestCalendar.date(2026, 11, 20, 12)), "tam 7 gün henüz eski değil")
        XCTAssertEqual(evaluate(TestCalendar.date(2026, 11, 20, 11)), .stale(days: 7))
        XCTAssertEqual(evaluate(TestCalendar.date(2026, 11, 18, 23)), .stale(days: 9))
    }

    func testWidgetShowsEmptyStateWithoutAppGroup() {
        XCTAssertEqual(WidgetDataLoader.loadFromStore(isGroupAvailable: false), WidgetData())
    }
}
