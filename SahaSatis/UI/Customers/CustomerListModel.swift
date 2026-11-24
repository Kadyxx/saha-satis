import Foundation
import Observation

/// Müşteri listesinin durumu. Veriye yalnızca `CustomerRepository` üzerinden erişir.
@MainActor
@Observable
final class CustomerListModel {
    private let repository: CustomerRepository

    var filter = CustomerFilter()
    private(set) var customers: [Customer] = []
    var errorMessage: String?

    init(repository: CustomerRepository) {
        self.repository = repository
    }

    func reload() {
        do {
            customers = try repository.search(filter)
        } catch {
            errorMessage = "Müşteriler yüklenemedi: \(error.localizedDescription)"
        }
    }

    /// Filtre menüsündeki şehir seçenekleri: bölge şehirleri + verideki diğer şehirler.
    func cityOptions(regionCities: [String]) -> [String] {
        var options = regionCities
        if let all = try? repository.fetchAll() {
            for city in all.map(\.city) where !city.isEmpty && !options.contains(city) {
                options.append(city)
            }
        }
        return options
    }

    var hasActiveFilter: Bool {
        filter.city != nil || filter.status != nil || filter.rating != nil
    }
}
