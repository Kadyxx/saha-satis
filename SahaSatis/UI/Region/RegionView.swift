import SwiftUI

/// Bölge sekmesindeki gezinme adımları: şehir → ilçe. (Müşteri detayı `Customer` değeriyle açılır.)
enum RegionRoute: Hashable {
    case city(String)
    case district(city: String, district: String)
}

/// Boş şehir/ilçe/OSB adlarının ekranda görünen karşılıkları.
enum RegionNaming {
    static func city(_ name: String) -> String { name.isEmpty ? "Şehir belirtilmemiş" : name }
    static func district(_ name: String) -> String { name.isEmpty ? "İlçe belirtilmemiş" : name }
    static func zone(_ name: String) -> String { name.isEmpty ? "OSB belirtilmemiş" : name }
}

/// Bölge sekmesi: şehirler (Ayarlar'daki sorumlu şehirler) → şehrin ilçeleri → ilçedeki müşteriler (OSB'ye göre).
/// Her seviyede aynı filtreler geçerlidir.
struct RegionView: View {
    let repositories: Repositories
    @ObservedObject var settings: AppSettings
    let debugScene: DebugScene?

    @EnvironmentObject private var appContext: AppContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RegionModel
    @State private var path: NavigationPath

    init(repositories: Repositories, settings: AppSettings, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        _settings = ObservedObject(wrappedValue: settings)
        self.debugScene = debugScene
        _model = State(initialValue: RegionModel(repositories: repositories, settings: settings))
        _path = State(initialValue: Self.initialPath(for: debugScene))
    }

    /// Yalnızca ekran görüntüsü senaryoları: ilgili seviyeyi doğrudan açar.
    private static func initialPath(for scene: DebugScene?) -> NavigationPath {
        switch scene {
        case .regionCity: return NavigationPath([RegionRoute.city("Bursa")])
        case .regionDistrict:
            return NavigationPath([RegionRoute.city("Bursa"), RegionRoute.district(city: "Bursa", district: "Nilüfer")])
        default: return NavigationPath()
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            cityLevel
                .navigationDestination(for: RegionRoute.self) { route in
                    switch route {
                    case .city(let city):
                        districtLevel(city: city)
                    case .district(let city, let district):
                        customerLevel(city: city, district: district)
                    }
                }
                .navigationDestination(for: Customer.self) { customer in
                    CustomerDetailView(
                        customer: customer,
                        repositories: repositories,
                        settings: settings,
                        onDelete: delete,
                        scrollToHistory: false
                    )
                }
                .navigationDestination(for: Opportunity.self) { opportunity in
                    OpportunityDetailView(opportunity: opportunity, context: appContext)
                }
                .navigationDestination(for: Quote.self) { quote in
                    QuoteDetailView(quote: quote, context: appContext)
                }
        }
        .tint(Theme.brandText)
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .appDataDidChange)) { _ in model.reload() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.reload() }
        }
    }

    // MARK: - Seviye 1: şehirler

    private var cityLevel: some View {
        List {
            filterSection
            Section {
                ForEach(model.cities) { summary in
                    NavigationLink(value: RegionRoute.city(summary.city)) {
                        RegionRow(title: RegionNaming.city(summary.city), stats: summary.stats, unit: "müşteri")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Theme.background)
        .visitButton(onSaved: { model.reload() })
        .navigationTitle("Bölge")
    }

    // MARK: - Seviye 2: ilçeler

    private func districtLevel(city: String) -> some View {
        let districts = model.districts(inCity: city)
        let stats = model.stats(inCity: city)
        return List {
            filterSection
            if districts.isEmpty {
                emptySection(
                    title: model.filter.isActive ? "Filtreye uyan müşteri yok" : "Bu şehirde müşteri yok",
                    message: model.filter.isActive ? "Filtreleri değiştirmeyi deneyin." : "Müşteriler sekmesinden müşteri ekleyin."
                )
            } else {
                Section {
                    ForEach(districts) { summary in
                        NavigationLink(value: RegionRoute.district(city: city, district: summary.district)) {
                            RegionRow(title: RegionNaming.district(summary.district), stats: summary.stats, unit: "müşteri")
                        }
                        .listRowBackground(Theme.surface)
                    }
                } header: {
                    Text("\(stats.customers) müşteri · \(districts.count) ilçe")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Theme.background)
        .visitButton(onSaved: { model.reload() })
        .navigationTitle(RegionNaming.city(city))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Seviye 3: müşteriler (OSB'ye göre)

    private func customerLevel(city: String, district: String) -> some View {
        let groups = model.zoneGroups(inCity: city, district: district)
        return List {
            filterSection
            if groups.isEmpty {
                emptySection(
                    title: model.filter.isActive ? "Filtreye uyan müşteri yok" : "Bu ilçede müşteri yok",
                    message: model.filter.isActive ? "Filtreleri değiştirmeyi deneyin." : "Müşteriler sekmesinden müşteri ekleyin."
                )
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.customers) { customer in
                            NavigationLink(value: customer) {
                                RegionCustomerRow(customer: customer, context: model.context)
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text("\(RegionNaming.zone(group.zone)) (\(group.customers.count))")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .background(Theme.background)
        .visitButton(onSaved: { model.reload() })
        .navigationTitle(RegionNaming.district(district))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Filtre çubuğu listenin ilk satırıdır (listeyle birlikte kayar). Liste dışına koymak gezinme çubuğuyla
    /// güvenli alan çakışması / fazladan boşluk üretiyordu.
    private var filterSection: some View {
        Section {
            RegionFilterBar(filter: $model.filter)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func emptySection(title: String, message: String) -> some View {
        Section {
            VStack(spacing: 8) {
                Label(title, systemImage: "mappin.slash")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .listRowBackground(Color.clear)
        }
    }

    /// Silinen modele ekran hâlâ bakarken erişilmesin diye: önce detaydan çık, kısa süre sonra sil.
    private func delete(_ customer: Customer) {
        path = NavigationPath()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            try? repositories.customers.delete(customer)
            model.reload()
        }
    }
}

/// Satır: başlık, müşteri sayısı ve (varsa) bekleyen teklif / gecikmiş takip özeti.
struct RegionRow: View {
    let title: String
    let stats: RegionStats
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text("\(stats.customers) \(unit)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(stats.customers == 0 ? Theme.textSecondary : Theme.brandText)
            }
            if stats.pendingQuotes > 0 || stats.overdueTasks > 0 {
                HStack(spacing: 12) {
                    if stats.pendingQuotes > 0 {
                        Label("\(stats.pendingQuotes) bekleyen teklif", systemImage: "doc.text")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if stats.overdueTasks > 0 {
                        Label("\(stats.overdueTasks) gecikmiş takip", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.overdue)
                    }
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// İlçedeki müşteri satırı: ad, değerlendirme, durum ve öne çıkan uyarılar (bekleyen teklif, ziyaret sıklığı, migrasyon).
struct RegionCustomerRow: View {
    let customer: Customer
    let context: RegionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(customer.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                RatingBadge(rating: customer.rating)
            }
            HStack(spacing: 6) {
                Text(customer.status.title)
                if !customer.sector.isEmpty {
                    Text("·")
                    Text(customer.sector)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            flags
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var flags: some View {
        let pending = context.pendingQuoteCount(customer)
        let visitOverdue = context.visitFrequencyExceeded(customer)
        if pending > 0 || visitOverdue || customer.hasMigrationOpportunity {
            HStack(spacing: 10) {
                if pending > 0 {
                    Label("\(pending) bekleyen teklif", systemImage: "doc.text")
                        .foregroundStyle(Theme.textSecondary)
                }
                if visitOverdue {
                    Label("Ziyaret zamanı geldi", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(Theme.overdue)
                }
                if customer.hasMigrationOpportunity {
                    Label("Migrasyon", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Theme.brandText)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }
}

/// Her seviyenin üstündeki filtre çubuğu: durum, değerlendirme (menü) ve üç açma/kapama filtresi.
struct RegionFilterBar: View {
    @Binding var filter: RegionFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                menuChip(title: filter.status?.title ?? "Durum", isOn: filter.status != nil) {
                    Picker("Durum", selection: $filter.status) {
                        Text("Tüm durumlar").tag(CustomerStatus?.none)
                        ForEach(CustomerStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(CustomerStatus?.some(status))
                        }
                    }
                }
                menuChip(title: filter.rating?.title ?? "Değerlendirme", isOn: filter.rating != nil) {
                    Picker("Değerlendirme", selection: $filter.rating) {
                        Text("Tüm değerlendirmeler").tag(CustomerRating?.none)
                        ForEach(CustomerRating.allCases, id: \.self) { rating in
                            Text(rating.title).tag(CustomerRating?.some(rating))
                        }
                    }
                }
                toggleChip(title: "Teklif bekleyen", isOn: $filter.pendingQuote)
                toggleChip(title: "Ziyareti geçen", isOn: $filter.visitOverdue)
                toggleChip(title: "Migrasyon fırsatı", isOn: $filter.migration)
                if filter.isActive {
                    Button("Temizle") { filter = RegionFilter() }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(height: 48)
    }

    private func chipLabel(_ title: String, isOn: Bool, showsChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(isOn ? Theme.onBrand : Theme.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isOn ? Theme.brand : Theme.surface, in: Capsule())
    }

    private func menuChip<Content: View>(title: String, isOn: Bool, @ViewBuilder content: () -> Content) -> some View {
        Menu { content() } label: { chipLabel(title, isOn: isOn, showsChevron: true) }
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func toggleChip(title: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: { chipLabel(title, isOn: isOn.wrappedValue, showsChevron: false) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}
