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

    /// Filtre menüsündeki ilçe seçenekleri: verideki ilçeler (şehir seçiliyse yalnızca o şehrinkiler), resmi yazımla,
    /// Türkçe alfabetik. Aynı ilçenin farklı yazımları tek seçenek olur.
    func districtOptions() -> [String] {
        guard let all = try? repository.fetchAll() else { return [] }
        var seen: [String: String] = [:]
        for customer in all {
            if let city = filter.city, DistrictCatalog.normalize(city) != DistrictCatalog.normalize(customer.city) { continue }
            let name = DistrictCatalog.displayName(customer.district, city: customer.city)
            guard !name.isEmpty else { continue }
            seen[DistrictCatalog.normalize(name)] = seen[DistrictCatalog.normalize(name)] ?? name
        }
        return seen.values.sorted { $0.compare($1, locale: AppFormat.locale) == .orderedAscending }
    }

    var hasActiveFilter: Bool {
        filter.city != nil || filter.district != nil || filter.status != nil || filter.rating != nil
    }
}
