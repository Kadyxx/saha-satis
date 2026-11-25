import SwiftUI

private struct CustomerEditTarget: Identifiable {
    let id = UUID()
    let customer: Customer?
}

/// Müşteriler sekmesi: arama, filtreler, sıralama, ekleme ve detaya gitme.
struct CustomersView: View {
    let repositories: Repositories
    @ObservedObject var settings: AppSettings
    let debugScene: DebugScene?

    @State private var model: CustomerListModel
    @State private var path = NavigationPath()
    @State private var editTarget: CustomerEditTarget?
    @State private var didRunDebugScene = false

    init(repositories: Repositories, settings: AppSettings, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        _settings = ObservedObject(wrappedValue: settings)
        self.debugScene = debugScene
        _model = State(initialValue: CustomerListModel(repository: repositories.customers))
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if model.customers.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(Theme.background)
            .navigationTitle("Müşteriler")
            .searchable(text: $model.filter.searchText, prompt: "Firma, şehir, sektör ara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .primaryAction) {
                    Button { editTarget = CustomerEditTarget(customer: nil) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Müşteri ekle")
                }
            }
            .navigationDestination(for: Customer.self) { customer in
                CustomerDetailView(
                    customer: customer,
                    repositories: repositories,
                    settings: settings,
                    onDelete: delete
                )
            }
            .sheet(item: $editTarget, onDismiss: { model.reload() }) { target in
                CustomerFormView(
                    customer: target.customer,
                    repository: repositories.customers,
                    cities: settings.responsibleCities
                )
            }
            .alert("Hata", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .onAppear { model.reload() }
        .onChange(of: model.filter) { model.reload() }
        .task { await runDebugSceneIfNeeded() }
    }

    // MARK: - Liste

    private var list: some View {
        List {
            ForEach(model.customers) { customer in
                NavigationLink(value: customer) {
                    CustomerRow(customer: customer)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(model.hasActiveFilter || !model.filter.searchText.isEmpty ? "Sonuç yok" : "Henüz müşteri yok",
                  systemImage: "building.2")
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(model.hasActiveFilter || !model.filter.searchText.isEmpty
                 ? "Arama veya filtreleri değiştirmeyi deneyin."
                 : "Sağ üstteki + ile ilk müşterinizi ekleyin.")
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - Filtre ve sıralama

    private var filterMenu: some View {
        Menu {
            Picker("Şehir", selection: $model.filter.city) {
                Text("Tüm şehirler").tag(String?.none)
                ForEach(model.cityOptions(regionCities: settings.responsibleCities), id: \.self) { city in
                    Text(city).tag(String?.some(city))
                }
            }
            Picker("Durum", selection: $model.filter.status) {
                Text("Tüm durumlar").tag(CustomerStatus?.none)
                ForEach(CustomerStatus.allCases, id: \.self) { status in
                    Text(status.title).tag(CustomerStatus?.some(status))
                }
            }
            Picker("Değerlendirme", selection: $model.filter.rating) {
                Text("Tüm değerlendirmeler").tag(CustomerRating?.none)
                ForEach(CustomerRating.allCases, id: \.self) { rating in
                    Text(rating.title).tag(CustomerRating?.some(rating))
                }
            }
            Picker("Sıralama", selection: $model.filter.sort) {
                Text("Ada göre").tag(CustomerSort.name)
                Text("Son ziyaret (yeni → eski)").tag(CustomerSort.lastVisitNewestFirst)
                Text("Son ziyaret (eski → yeni)").tag(CustomerSort.lastVisitOldestFirst)
            }
        } label: {
            Image(systemName: model.hasActiveFilter
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filtre ve sıralama")
    }

    // MARK: - İşlemler

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    /// Silinen modele ekran hâlâ bakarken erişilmesin diye: önce detaydan çık, kısa süre sonra sil.
    private func delete(_ customer: Customer) {
        path = NavigationPath()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            do {
                try repositories.customers.delete(customer)
            } catch {
                model.errorMessage = "Müşteri silinemedi: \(error.localizedDescription)"
            }
            model.reload()
        }
    }

    // MARK: - Ekran görüntüsü senaryoları (yalnızca DEBUG başlatma argümanıyla)

    private func runDebugSceneIfNeeded() async {
        guard let scene = debugScene, !didRunDebugScene else { return }
        didRunDebugScene = true
        model.reload()
        let showcase = model.customers.first { $0.name == "Örnek Makina A.Ş." } ?? model.customers.first
        switch scene {
        case .customers, .settings, .settingsReminders, .settingsCities:
            break
        case .detail:
            if let showcase { path.append(showcase) }
        case .form:
            if let showcase { editTarget = CustomerEditTarget(customer: showcase) }
        }
    }
}
