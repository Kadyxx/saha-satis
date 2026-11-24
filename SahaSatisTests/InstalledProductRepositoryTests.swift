import XCTest
@testable import SahaSatis

@MainActor
final class InstalledProductRepositoryTests: XCTestCase {
    func testAddAndListSortedByCatalogNumber() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "1756-L71", productFamily: "ControlLogix", quantity: 2), to: customer)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "1734-AENT"), to: customer)

        let products = try env.repos.installedProducts.products(for: customer)
        XCTAssertEqual(products.map(\.catalogNumber), ["1734-AENT", "1756-L71"])
        XCTAssertEqual(products.last?.quantity, 2)
        XCTAssertEqual(products.last?.ownerUserID, "test-user")
    }

    func testLifecycleRawStorageAndMigrationFlag() {
        let product = InstalledProduct(catalogNumber: "PLC-5", lifecycleStatus: .endOfLife)
        XCTAssertEqual(product.lifecycleStatusRaw, "endOfLife")
        XCTAssertTrue(product.lifecycleStatus.isMigrationCandidate)
        product.lifecycleStatus = .activeMature
        XCTAssertFalse(product.lifecycleStatus.isMigrationCandidate)
    }

    func testMigrationCandidatesAcrossCustomers() throws {
        let env = try TestEnv()
        let a = try env.makeCustomer("A")
        let b = try env.makeCustomer("B")
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "OK", lifecycleStatus: .active), to: a)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "EOL", lifecycleStatus: .endOfLife), to: a)
        try env.repos.installedProducts.add(InstalledProduct(catalogNumber: "DISC", lifecycleStatus: .discontinued), to: b)

        XCTAssertEqual(try env.repos.installedProducts.migrationCandidates().map(\.catalogNumber), ["DISC", "EOL"])
    }

    func testUpdateAndDelete() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let product = InstalledProduct(catalogNumber: "1756-L71")
        try env.repos.installedProducts.add(product, to: customer)

        product.notes = "Hat 3"
        try env.repos.installedProducts.update(product)
        XCTAssertEqual(try env.repos.installedProducts.product(id: product.id)?.notes, "Hat 3")

        try env.repos.installedProducts.delete(product)
        XCTAssertNil(try env.repos.installedProducts.product(id: product.id))
    }
}
