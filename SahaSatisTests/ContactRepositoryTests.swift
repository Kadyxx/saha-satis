import XCTest
@testable import SahaSatis

@MainActor
final class ContactRepositoryTests: XCTestCase {
    func testFirstContactBecomesPrimary() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()

        let first = Contact(fullName: "Ahmet Yılmaz", title: "Bakım Müdürü")
        let second = Contact(fullName: "Ayşe Demir")
        try env.repos.contacts.add(first, to: customer)
        try env.repos.contacts.add(second, to: customer)

        XCTAssertTrue(first.isPrimary)
        XCTAssertFalse(second.isPrimary)
        XCTAssertEqual(first.ownerUserID, "test-user")
    }

    func testAddingPrimaryDemotesOthersAndOrdersPrimaryFirst() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let first = Contact(fullName: "Ahmet Yılmaz")
        let second = Contact(fullName: "Zeynep Kaya", isPrimary: true)
        try env.repos.contacts.add(first, to: customer)
        try env.repos.contacts.add(second, to: customer)

        XCTAssertFalse(first.isPrimary)
        XCTAssertTrue(second.isPrimary)
        XCTAssertEqual(try env.repos.contacts.contacts(for: customer).map(\.fullName), ["Zeynep Kaya", "Ahmet Yılmaz"])
    }

    func testSetPrimarySwitchesPrimary() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let first = Contact(fullName: "Ahmet Yılmaz")
        let second = Contact(fullName: "Ayşe Demir")
        try env.repos.contacts.add(first, to: customer)
        try env.repos.contacts.add(second, to: customer)

        try env.repos.contacts.setPrimary(second)

        XCTAssertFalse(first.isPrimary)
        XCTAssertTrue(second.isPrimary)
    }

    func testContactsAreScopedToCustomer() throws {
        let env = try TestEnv()
        let a = try env.makeCustomer("A")
        let b = try env.makeCustomer("B")
        try env.repos.contacts.add(Contact(fullName: "Kişi A"), to: a)
        try env.repos.contacts.add(Contact(fullName: "Kişi B"), to: b)

        XCTAssertEqual(try env.repos.contacts.contacts(for: a).map(\.fullName), ["Kişi A"])
        XCTAssertEqual(try env.repos.contacts.contacts(for: b).map(\.fullName), ["Kişi B"])
    }

    func testUpdateAndDelete() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = Contact(fullName: "Ahmet Yılmaz")
        try env.repos.contacts.add(contact, to: customer)

        contact.phone = "0555 000 00 00"
        try env.repos.contacts.update(contact)
        XCTAssertEqual(try env.repos.contacts.contact(id: contact.id)?.phone, "0555 000 00 00")

        try env.repos.contacts.delete(contact)
        XCTAssertNil(try env.repos.contacts.contact(id: contact.id))
        XCTAssertNotNil(try env.repos.customers.customer(id: customer.id), "Kişiyi silmek müşteriyi silmez")
    }
}
