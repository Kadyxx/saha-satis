import XCTest
@testable import SahaSatis

final class ProductFamilyTests: XCTestCase {
    func testDefaultsHavePLC5AndSLC500WithVerifyNote() {
        let names = ProductFamily.defaults.map(\.name)
        XCTAssertEqual(names, ["PLC-5", "SLC 500"])
        XCTAssertTrue(ProductFamily.defaults.allSatisfy { $0.note == "Rockwell yaşam döngüsü sayfasından doğrulayın" })
        XCTAssertTrue(ProductFamily.defaults.allSatisfy { $0.lifecycle.isMigrationCandidate })
        XCTAssertEqual(Set(ProductFamily.defaults.map(\.id)).count, 2)
    }

    func testFindIgnoresCaseAndSpacing() {
        XCTAssertEqual(ProductFamily.find("plc-5", in: ProductFamily.defaults)?.name, "PLC-5")
        XCTAssertEqual(ProductFamily.find("  SLC 500 ", in: ProductFamily.defaults)?.name, "SLC 500")
        XCTAssertNil(ProductFamily.find("ControlLogix", in: ProductFamily.defaults))
        XCTAssertNil(ProductFamily.find("", in: ProductFamily.defaults))
    }

    func testLifecycleTitles() {
        XCTAssertEqual(LifecycleStatus.allCases.map(\.title), ["Aktif", "Aktif (olgun)", "Üretim sonu", "Üretimden kalktı"])
    }

    func testSettingsPersistFamiliesAndFallBackToDefaults() throws {
        let suite = "test-families-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = AppSettings(defaults: defaults)
        XCTAssertEqual(first.productFamilies, ProductFamily.defaults)

        first.productFamilies.append(ProductFamily(name: "ControlLogix", lifecycle: .activeMature))
        first.productFamilies[0].lifecycle = .endOfLife

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.productFamilies.map(\.name), ["PLC-5", "SLC 500", "ControlLogix"])
        XCTAssertEqual(second.productFamilies[0].lifecycle, .endOfLife)

        second.productFamilies = []
        XCTAssertTrue(AppSettings(defaults: defaults).productFamilies.isEmpty, "Boş liste bilinçli seçimdir")
    }
}

final class InstalledProductDraftTests: XCTestCase {
    private let families = ProductFamily.defaults + [ProductFamily(name: "ControlLogix", lifecycle: .active)]

    func testSelectingFamilyTakesItsLifecycleAndCanBeOverridden() {
        var draft = InstalledProductDraft()
        draft.selectFamily("PLC-5", families: families)
        XCTAssertEqual(draft.family, "PLC-5")
        XCTAssertEqual(draft.lifecycle, .discontinued)

        draft.lifecycle = .activeMature
        XCTAssertEqual(draft.lifecycle, .activeMature, "Elle değiştirilebilir")

        draft.selectFamily("ControlLogix", families: families)
        XCTAssertEqual(draft.lifecycle, .active)
    }

    func testFreeTextFamilyKeepsLifecycle() {
        var draft = InstalledProductDraft()
        draft.lifecycle = .endOfLife
        draft.selectFamily("Bilinmeyen Seri", families: families)
        XCTAssertEqual(draft.family, "Bilinmeyen Seri")
        XCTAssertEqual(draft.lifecycle, .endOfLife)
    }

    func testCanSaveNeedsCatalogNumberAndPositiveQuantity() {
        var draft = InstalledProductDraft()
        XCTAssertFalse(draft.canSave)
        draft.catalogNumber = "  "
        XCTAssertFalse(draft.canSave)
        draft.catalogNumber = "1756-L71"
        XCTAssertTrue(draft.canSave)
        draft.quantity = 0
        XCTAssertFalse(draft.canSave)
    }

    @MainActor
    func testAddEditDeleteThroughRepository() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        var draft = InstalledProductDraft()
        draft.catalogNumber = " 1747-L542 "
        draft.selectFamily("SLC 500", families: families)
        draft.quantity = 3
        draft.notes = " Hat 2 "
        try env.repos.installedProducts.add(draft.makeProduct(), to: customer)

        let saved = try XCTUnwrap(try env.repos.installedProducts.products(for: customer).first)
        XCTAssertEqual(saved.catalogNumber, "1747-L542")
        XCTAssertEqual(saved.productFamily, "SLC 500")
        XCTAssertEqual(saved.quantity, 3)
        XCTAssertEqual(saved.lifecycleStatus, .endOfLife)
        XCTAssertEqual(saved.notes, "Hat 2")

        var edit = InstalledProductDraft(product: saved)
        edit.quantity = 5
        edit.lifecycle = .active
        edit.apply(to: saved)
        try env.repos.installedProducts.update(saved)
        XCTAssertEqual(try env.repos.installedProducts.products(for: customer).first?.quantity, 5)
        XCTAssertEqual(try env.repos.installedProducts.products(for: customer).first?.lifecycleStatus, .active)

        try env.repos.installedProducts.delete(saved)
        XCTAssertTrue(try env.repos.installedProducts.products(for: customer).isEmpty)
    }
}

@MainActor
final class MigrationOpportunityTests: XCTestCase {
    func testPrefillUsesFamilyAndFillsProductAndQuantity() {
        let product = InstalledProduct(
            catalogNumber: "PLC-5/40", productFamily: "PLC-5", quantity: 2, lifecycleStatus: .discontinued, notes: "Hat 3"
        )
        let prefill = MigrationOpportunityPrefill(product: product)
        XCTAssertEqual(prefill.title, "PLC-5 migrasyonu")
        XCTAssertEqual(prefill.details, "Ürün: PLC-5/40 (PLC-5)\nAdet: 2\nYaşam döngüsü: Üretimden kalktı\nNot: Hat 3")
    }

    func testPrefillFallsBackToCatalogNumberWithoutFamily() {
        let product = InstalledProduct(catalogNumber: "1756-L61", quantity: 1, lifecycleStatus: .endOfLife)
        let prefill = MigrationOpportunityPrefill(product: product)
        XCTAssertEqual(prefill.title, "1756-L61 migrasyonu")
        XCTAssertEqual(prefill.details, "Ürün: 1756-L61\nAdet: 1\nYaşam döngüsü: Üretim sonu")
    }

    func testOpportunityFormStartsWithPrefillAndSavesForSelectedCustomer() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let product = InstalledProduct(catalogNumber: "PLC-5/40", productFamily: "PLC-5", quantity: 2, lifecycleStatus: .discontinued)
        let prefill = MigrationOpportunityPrefill(product: product)
        let model = OpportunityFormModel(
            repositories: env.repos, reminderRules: OpportunityReminderRules(), defaultCurrency: .tl,
            customer: customer, prefillTitle: prefill.title, prefillDetails: prefill.details
        )
        XCTAssertEqual(model.customer?.id, customer.id)
        XCTAssertEqual(model.title, "PLC-5 migrasyonu")
        XCTAssertTrue(model.details.contains("PLC-5/40"))
        XCTAssertTrue(model.details.contains("Adet: 2"))
        XCTAssertTrue(model.canSave)
        XCTAssertTrue(model.save())
        XCTAssertEqual(try env.repos.opportunities.opportunities(for: customer).first?.title, "PLC-5 migrasyonu")
    }

    func testMigrationTagFollowsLifecycleOfProducts() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        XCTAssertFalse(customer.hasMigrationOpportunity)

        let active = InstalledProduct(catalogNumber: "A", lifecycleStatus: .activeMature)
        try env.repos.installedProducts.add(active, to: customer)
        XCTAssertFalse(customer.hasMigrationOpportunity, "Aktif-olgun migrasyon sayılmaz")

        let eol = InstalledProduct(catalogNumber: "B", lifecycleStatus: .endOfLife)
        try env.repos.installedProducts.add(eol, to: customer)
        XCTAssertTrue(customer.hasMigrationOpportunity)

        try env.repos.installedProducts.delete(eol)
        XCTAssertFalse(customer.hasMigrationOpportunity)

        let discontinued = InstalledProduct(catalogNumber: "C", lifecycleStatus: .discontinued)
        try env.repos.installedProducts.add(discontinued, to: customer)
        XCTAssertTrue(customer.hasMigrationOpportunity)
    }

    func testCustomerListMigrationFilter() throws {
        let env = try TestEnv()
        let with = try env.makeCustomer("Migrasyonlu A.Ş.", city: "Bursa")
        let without = try env.makeCustomer("Aktif Ltd.", city: "Bursa")
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "X", lifecycleStatus: .discontinued), to: with)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "Y", lifecycleStatus: .active), to: without)

        var filter = CustomerFilter()
        XCTAssertEqual(try env.repos.customers.search(filter).count, 2)
        filter.migration = true
        XCTAssertEqual(try env.repos.customers.search(filter).map(\.name), ["Migrasyonlu A.Ş."])
        filter.city = "Balıkesir"
        XCTAssertTrue(try env.repos.customers.search(filter).isEmpty, "Diğer filtrelerle birlikte (VE)")
    }
}
