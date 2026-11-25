import Foundation
import SwiftData
import XCTest
@testable import SahaSatis

/// Her test kendi bellek içi deposunu açar (iCloud kapalı, diske yazılmaz).
/// `container` yaşadığı sürece context geçerlidir; testte `let env = try TestEnv()` olarak tutun.
@MainActor
struct TestEnv {
    let container: ModelContainer
    let repos: Repositories

    var context: ModelContext { container.mainContext }

    init() throws {
        container = try Persistence.makeContainer(inMemory: true)
        repos = Repositories.swiftData(context: container.mainContext, ownerUserID: "test-user")
    }

    /// Önceden kayıtlı bir müşteri döndürür.
    @discardableResult
    func makeCustomer(
        _ name: String = "Örnek Makina A.Ş.",
        city: String = "Bursa",
        status: CustomerStatus = .current,
        rating: CustomerRating = .important
    ) throws -> Customer {
        let customer = Customer(name: name, city: city, status: status, rating: rating)
        try repos.customers.add(customer)
        return customer
    }
}

enum TestCalendar {
    /// Saat dilimi sabit (UTC) takvim: testler makinenin saat diliminden bağımsız olsun.
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
