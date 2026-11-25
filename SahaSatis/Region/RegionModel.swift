import Foundation
import Observation

/// Bölge ekranındaki filtreler (her seviyede aynı filtre geçerlidir). Boş filtre = hepsi.
struct RegionFilter: Equatable, Sendable {
    var status: CustomerStatus?
    var rating: CustomerRating?
    /// Bekleyen (Gönderildi / Takipte) teklifi olan müşteriler.
    var pendingQuote = false
    /// Ziyaret sıklığı eşiğine ulaşan/aşan müşteriler (pasifler hariç).
    var visitOverdue = false
    /// Kurulu bazında ömrünü tamamlayan / üretimi duran ürünü olan müşteriler.
    var migration = false

    var isActive: Bool {
        status != nil || rating != nil || pendingQuote || visitOverdue || migration
    }

    /// Kaç filtre açık (rozet için).
    var activeCount: Int {
        [status != nil, rating != nil, pendingQuote, visitOverdue, migration].filter { $0 }.count
    }
}

/// Filtre değerlendirmesi için ortak bağlam (ziyaret sıklığı eşikleri ve "şimdi").
struct RegionContext {
    var rules: VisitFrequencyRules
    var now: Date = Date()
    var calendar: Calendar = .current

    /// Son ziyaretten (hiç yoksa eklenme tarihinden) bu yana geçen gün sayısı, değerlendirmenin eşiğine ulaştıysa true.
    /// `VisitFrequencyService` ile aynı referans: pasif müşteriler uyarı almaz.
    func visitFrequencyExceeded(_ customer: Customer) -> Bool {
        guard customer.status != .passive else { return false }
        let reference = customer.lastVisitDate ?? customer.createdAt
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days >= rules.days(for: customer.rating)
    }

    func pendingQuoteCount(_ customer: Customer) -> Int {
        (customer.quotes ?? []).filter { $0.status.isPending }.count
    }

    /// Bugünden önce vadesi gelmiş, tamamlanmamış takipler.
    func overdueTaskCount(_ customer: Customer) -> Int {
        let today = calendar.startOfDay(for: now)
        return (customer.tasks ?? []).filter { !$0.isDone && $0.dueDate < today }.count
    }
}

extension RegionFilter {
    func matches(_ customer: Customer, context: RegionContext) -> Bool {
        if let status, customer.status != status { return false }
        if let rating, customer.rating != rating { return false }
        if pendingQuote, context.pendingQuoteCount(customer) == 0 { return false }
        if visitOverdue, !context.visitFrequencyExceeded(customer) { return false }
        if migration, !customer.hasMigrationOpportunity { return false }
        return true
    }
}

/// Bir kapsamdaki (şehir/ilçe) özet sayıları.
struct RegionStats: Equatable {
    var customers = 0
    var pendingQuotes = 0
    var overdueTasks = 0
}

struct CitySummary: Identifiable, Equatable {
    /// Şehir adı; boş = "Şehir belirtilmemiş".
    let city: String
    let stats: RegionStats
    var id: String { city }
}

struct DistrictSummary: Identifiable, Equatable {
    /// İlçe adı (resmi yazım); boş = "İlçe belirtilmemiş".
    let district: String
    let stats: RegionStats
    var id: String { district }
}

/// OSB'ye göre müşteri grubu.
struct ZoneGroup: Identifiable {
    /// OSB adı; boş = OSB'siz müşteriler.
    let zone: String
    let customers: [Customer]
    var id: String { zone }
}

/// Bölge ekranının üç seviyesini (şehir → ilçe → OSB'li müşteri listesi) kuran saf mantık. Hiçbir ekran durumu tutmaz.
@MainActor
enum RegionBuilder {
    private static let turkish = Locale(identifier: "tr_TR")

    // MARK: - Anahtarlar

    /// Müşterinin şehri: bölge listesindeki bir şehirle yazım farkıyla eşleşiyorsa o şehrin adı, yoksa yazıldığı gibi.
    static func cityName(of customer: Customer, regionCities: [String]) -> String {
        let trimmed = customer.city.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = DistrictCatalog.normalize(trimmed)
        if let match = regionCities.first(where: { DistrictCatalog.normalize($0) == key }) { return match }
        return DistrictCatalog.canonicalCity(trimmed) ?? trimmed
    }

    /// Müşterinin ilçesi: şehrin resmi listesiyle eşleşirse resmi yazım, yoksa yazıldığı gibi; boşsa "".
    static func districtName(of customer: Customer) -> String {
        DistrictCatalog.displayName(customer.district, city: customer.city)
    }

    static func zoneName(of customer: Customer) -> String {
        customer.industrialZone.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func sameKey(_ lhs: String, _ rhs: String) -> Bool {
        DistrictCatalog.normalize(lhs) == DistrictCatalog.normalize(rhs)
    }

    private static func inOrder(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive], range: nil, locale: turkish) == .orderedAscending
    }

    // MARK: - Filtre

    static func filtered(_ customers: [Customer], filter: RegionFilter, context: RegionContext) -> [Customer] {
        guard filter.isActive else { return customers }
        return customers.filter { filter.matches($0, context: context) }
    }

    static func stats(of customers: [Customer], context: RegionContext) -> RegionStats {
        RegionStats(
            customers: customers.count,
            pendingQuotes: customers.reduce(0) { $0 + context.pendingQuoteCount($1) },
            overdueTasks: customers.reduce(0) { $0 + context.overdueTaskCount($1) }
        )
    }

    // MARK: - Seviye 1: şehirler

    /// Bölge şehirleri (Ayarlar'daki sıra) her zaman listelenir (müşteri yoksa 0); ardından bölge dışı şehirler
    /// (alfabetik) ve şehri boş müşteriler. Sayılar filtreye göredir.
    static func cities(
        customers: [Customer], regionCities: [String], filter: RegionFilter, context: RegionContext
    ) -> [CitySummary] {
        let visible = filtered(customers, filter: filter, context: context)
        var groups: [String: [Customer]] = [:]
        var extra: [String] = []
        for customer in visible {
            let name = cityName(of: customer, regionCities: regionCities)
            groups[name, default: []].append(customer)
            if !name.isEmpty, !regionCities.contains(name), !extra.contains(name) { extra.append(name) }
        }
        extra.sort(by: inOrder)

        var ordered = regionCities + extra
        if groups[""] != nil { ordered.append("") }
        return ordered.map { CitySummary(city: $0, stats: stats(of: groups[$0] ?? [], context: context)) }
    }

    /// Bir şehrin (süzülmüş) müşterileri.
    static func customers(
        inCity city: String, customers: [Customer], regionCities: [String], filter: RegionFilter, context: RegionContext
    ) -> [Customer] {
        filtered(customers, filter: filter, context: context)
            .filter { sameKey(cityName(of: $0, regionCities: regionCities), city) }
    }

    // MARK: - Seviye 2: ilçeler

    /// Şehrin müşterisi olan ilçeleri (alfabetik; "İlçe belirtilmemiş" en sonda) ve ilçe başına özet.
    static func districts(
        inCity city: String, customers: [Customer], regionCities: [String], filter: RegionFilter, context: RegionContext
    ) -> [DistrictSummary] {
        let inCity = Self.customers(inCity: city, customers: customers, regionCities: regionCities, filter: filter, context: context)
        var groups: [String: (name: String, customers: [Customer])] = [:]
        for customer in inCity {
            let name = districtName(of: customer)
            let key = DistrictCatalog.normalize(name)
            groups[key, default: (name: name, customers: [])].customers.append(customer)
        }
        return groups.values
            .sorted { lhs, rhs in
                if lhs.name.isEmpty != rhs.name.isEmpty { return rhs.name.isEmpty }
                return inOrder(lhs.name, rhs.name)
            }
            .map { DistrictSummary(district: $0.name, stats: stats(of: $0.customers, context: context)) }
    }

    // MARK: - Seviye 3: ilçedeki müşteriler (OSB'ye göre)

    /// İlçedeki müşteriler OSB'ye göre gruplanır (OSB adları alfabetik); OSB'si olmayanlar en sonda ayrı grupta.
    /// Grup içinde müşteriler ada göre sıralıdır.
    static func zoneGroups(
        inCity city: String, district: String, customers: [Customer], regionCities: [String],
        filter: RegionFilter, context: RegionContext
    ) -> [ZoneGroup] {
        let inDistrict = Self.customers(inCity: city, customers: customers, regionCities: regionCities, filter: filter, context: context)
            .filter { sameKey(districtName(of: $0), district) }
        var groups: [String: (name: String, customers: [Customer])] = [:]
        for customer in inDistrict {
            let name = zoneName(of: customer)
            groups[DistrictCatalog.normalize(name), default: (name: name, customers: [])].customers.append(customer)
        }
        return groups.values
            .sorted { lhs, rhs in
                if lhs.name.isEmpty != rhs.name.isEmpty { return rhs.name.isEmpty }
                return inOrder(lhs.name, rhs.name)
            }
            .map { group in ZoneGroup(zone: group.name, customers: group.customers.sorted { inOrder($0.name, $1.name) }) }
    }
}

/// Bölge sekmesinin durumu: müşteriler, filtre ve hesaplama bağlamı.
@MainActor
@Observable
final class RegionModel {
    private let repositories: Repositories
    private let settings: AppSettings

    var filter = RegionFilter()
    private(set) var customers: [Customer] = []
    private(set) var now = Date()
    var errorMessage: String?

    init(repositories: Repositories, settings: AppSettings) {
        self.repositories = repositories
        self.settings = settings
    }

    var regionCities: [String] { settings.responsibleCities }

    var context: RegionContext {
        RegionContext(rules: settings.visitFrequencyRules, now: now)
    }

    func reload() {
        do {
            customers = try repositories.customers.fetchAll()
            now = Date()
        } catch {
            errorMessage = "Müşteriler yüklenemedi: \(error.localizedDescription)"
        }
    }

    var cities: [CitySummary] {
        RegionBuilder.cities(customers: customers, regionCities: regionCities, filter: filter, context: context)
    }

    func districts(inCity city: String) -> [DistrictSummary] {
        RegionBuilder.districts(inCity: city, customers: customers, regionCities: regionCities, filter: filter, context: context)
    }

    func zoneGroups(inCity city: String, district: String) -> [ZoneGroup] {
        RegionBuilder.zoneGroups(
            inCity: city, district: district, customers: customers, regionCities: regionCities,
            filter: filter, context: context
        )
    }

    /// Bir şehrin özeti (ilçe ekranının başlığında).
    func stats(inCity city: String) -> RegionStats {
        let list = RegionBuilder.customers(inCity: city, customers: customers, regionCities: regionCities, filter: filter, context: context)
        return RegionBuilder.stats(of: list, context: context)
    }
}
