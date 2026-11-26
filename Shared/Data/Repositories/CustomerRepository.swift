import Foundation
import SwiftData

struct CustomerFilter: Equatable, Sendable {
    var searchText: String = ""
    var city: String?
    /// İlçe (resmi yazımla veya yazıldığı gibi; büyük/küçük harf ve Türkçe karakter duyarsız karşılaştırılır).
    var district: String?
    var status: CustomerStatus?
    var rating: CustomerRating?
    /// Kurulu bazda ömrünü tamamlayan / üretimi duran ürünü olan müşteriler ("Migrasyon fırsatı").
    var migration = false
    var sort: CustomerSort = .name
}

enum CustomerSort: Hashable, Sendable {
    /// Ada göre (Türkçe sıralama).
    case name
    /// En son ziyaret edilen en üstte; hiç ziyaret edilmeyenler en altta.
    case lastVisitNewestFirst
    /// En uzun süredir ziyaret edilmeyen en üstte; hiç ziyaret edilmeyenler en üstte.
    case lastVisitOldestFirst
}

@MainActor
protocol CustomerRepository {
    func fetchAll() throws -> [Customer]
    func search(_ filter: CustomerFilter) throws -> [Customer]
    func customer(id: UUID) throws -> Customer?
    func add(_ customer: Customer) throws
    func update(_ customer: Customer) throws
    func delete(_ customer: Customer) throws
}

@MainActor
final class SwiftDataCustomerRepository: CustomerRepository {
    private let context: ModelContext
    private let ownerUserID: String

    init(context: ModelContext, ownerUserID: String = "") {
        self.context = context
        self.ownerUserID = ownerUserID
    }

    func fetchAll() throws -> [Customer] {
        try search(CustomerFilter())
    }

    func search(_ filter: CustomerFilter) throws -> [Customer] {
        var result = try context.fetchAll(Customer.self)

        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { customer in
                [customer.name, customer.city, customer.district, customer.industrialZone, customer.sector]
                    .contains { Self.matches($0, query: query) }
            }
        }
        if let city = filter.city {
            result = result.filter { $0.city == city }
        }
        if let district = filter.district {
            let key = DistrictCatalog.normalize(district)
            result = result.filter { DistrictCatalog.normalize(DistrictCatalog.displayName($0.district, city: $0.city)) == key }
        }
        if let status = filter.status {
            result = result.filter { $0.status == status }
        }
        if filter.migration {
            result = result.filter(.hasMigrationOpportunity)
        }
        if let rating = filter.rating {
            result = result.filter { $0.rating == rating }
        }

        switch filter.sort {
        case .name:
            result.sort { Self.nameOrder($0, $1) }
        case .lastVisitNewestFirst:
            result.sort { lhs, rhs in
                switch (lhs.lastVisitDate, rhs.lastVisitDate) {
                case let (l?, r?): return l == r ? Self.nameOrder(lhs, rhs) : l > r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return Self.nameOrder(lhs, rhs)
                }
            }
        case .lastVisitOldestFirst:
            result.sort { lhs, rhs in
                switch (lhs.lastVisitDate, rhs.lastVisitDate) {
                case let (l?, r?): return l == r ? Self.nameOrder(lhs, rhs) : l < r
                case (nil, _?): return true
                case (_?, nil): return false
                case (nil, nil): return Self.nameOrder(lhs, rhs)
                }
            }
        }
        return result
    }

    func customer(id: UUID) throws -> Customer? {
        try context.fetchAll(Customer.self).first { $0.id == id }
    }

    func add(_ customer: Customer) throws {
        if customer.ownerUserID.isEmpty { customer.ownerUserID = ownerUserID }
        context.insert(customer)
        try context.saveAndNotify()
    }

    func update(_ customer: Customer) throws {
        customer.updatedAt = Date()
        try context.saveAndNotify()
    }

    func delete(_ customer: Customer) throws {
        context.delete(customer)
        try context.saveAndNotify()
    }

    // MARK: - Yardımcılar

    private static let turkish = Locale(identifier: "tr_TR")

    private static func matches(_ text: String, query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: turkish) != nil
    }

    private static func nameOrder(_ lhs: Customer, _ rhs: Customer) -> Bool {
        lhs.name.compare(rhs.name, options: [.caseInsensitive], range: nil, locale: turkish) == .orderedAscending
    }
}
