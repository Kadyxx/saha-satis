import SwiftUI

private struct CustomerEditTarget: Identifiable {
    let id = UUID()
    let customer: Customer?
}

/// Yalnızca ekran görüntüsü senaryoları: ziyaret formunu önceden doldurulmuş açar.
private struct DebugVisitTarget: Identifiable {
    let id = UUID()
    let customer: Customer
    let seed: VisitFormSeed
}

/// Müşteriler sekmesi: arama, filtreler, sıralama, ekleme ve detaya gitme.
struct CustomersView: View {
    let repositories: Repositories
    @ObservedObject var settings: AppSettings
    let debugScene: DebugScene?

    @EnvironmentObject private var appContext: AppContext
    @State private var model: CustomerListModel
    @State private var path = NavigationPath()
    @State private var editTarget: CustomerEditTarget?
    @State private var debugVisit: DebugVisitTarget?
    @State private var didRunDebugScene = false
    @State private var importSession: ImportSession?
    @State private var showFileImporter = false
    @State private var importError: String?

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
            .visitButton(onSaved: { model.reload() })
            .navigationTitle("Müşteriler")
            .searchable(text: $model.filter.searchText, prompt: "Firma, şehir, sektör ara")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFileImporter = true } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("CSV'den içe aktar")
                }
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
                    onDelete: delete,
                    scrollToHistory: debugScene == .visitHistory,
                    scrollToInstalledBase: debugScene == .installedBase,
                    openMigrationProductForm: debugScene == .installedBaseForm
                )
            }
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity, context: appContext)
            }
            .navigationDestination(for: Quote.self) { quote in
                QuoteDetailView(quote: quote, context: appContext)
            }
            .sheet(item: $debugVisit, onDismiss: { model.reload() }) { target in
                VisitFormView(context: appContext, customer: target.customer, visit: nil, seed: target.seed)
            }
            .sheet(item: $importSession, onDismiss: { model.reload() }) { session in
                CustomerImportView(
                    repositories: repositories,
                    regionCities: settings.responsibleCities,
                    session: session,
                    startAtPreview: debugScene == .importPreview,
                    onFinished: { model.reload() }
                )
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]
            ) { result in
                switch result {
                case .success(let url):
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url),
                       let session = ImportSession.make(fileName: url.lastPathComponent, data: data) {
                        importSession = session
                    } else {
                        importError = "Dosya okunamadı veya veri satırı yok. CSV (UTF-8 ya da Windows-1254) olmalı."
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
            .alert("İçe aktarılamadı", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(importError ?? "")
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
        .onAppear {
            model.reload()
            openRequestedCustomer()
        }
        .onChange(of: appContext.customerToOpen) { openRequestedCustomer() }
        .onChange(of: model.filter.city) { model.filter.district = nil }
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
            Picker("İlçe", selection: $model.filter.district) {
                Text("Tüm ilçeler").tag(String?.none)
                ForEach(model.districtOptions(), id: \.self) { district in
                    Text(district).tag(String?.some(district))
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
            Toggle("Migrasyon fırsatı olanlar", isOn: $model.filter.migration)
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

    /// Bildirime dokunma veya Bugün satırı bir müşteri istediyse detayını açar.
    private func openRequestedCustomer() {
        guard let id = appContext.customerToOpen else { return }
        appContext.customerToOpen = nil
        guard let customer = try? repositories.customers.customer(id: id) else { return }
        path = NavigationPath()
        path.append(customer)
    }

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
        case .customers, .settings, .settingsReminders, .settingsCities, .today, .todayForm, .export, .exportPreview,
             .opportunities, .opportunityDetail, .opportunityForm, .opportunityLost,
             .quotes, .quoteDetail, .quoteForm,
             .region, .regionCity, .regionDistrict, .weekDay:
            break
        case .detail, .visitHistory, .installedBase, .installedBaseForm:
            if let showcase { path.append(showcase) }
        case .form:
            if let showcase { editTarget = CustomerEditTarget(customer: showcase) }
        case .visitForm:
            if let showcase { debugVisit = DebugVisitTarget(customer: showcase, seed: .showcaseForm) }
        case .importMapping, .importPreview:
            #if DEBUG
            importSession = ImportSession.make(fileName: "musteriler.csv", data: Data(SampleData.importCSV.utf8))
            #endif
        case .visitRecording:
            if let showcase { debugVisit = DebugVisitTarget(customer: showcase, seed: .showcaseRecording) }
        }
    }
}
