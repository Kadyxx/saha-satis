import SwiftUI

/// Formun düzenlediği geçici kopya; "Kaydet"e basılana kadar modele dokunulmaz.
struct CustomerDraft: Equatable {
    var name = ""
    var sector = ""
    var city = ""
    var district = ""
    var industrialZone = ""
    var address = ""
    var status: CustomerStatus = .potential
    var rating: CustomerRating = .promising
    var ratingNote = ""
    var notes = ""

    init() {}

    init(customer: Customer) {
        name = customer.name
        sector = customer.sector
        city = customer.city
        district = customer.district
        industrialZone = customer.industrialZone
        address = customer.address
        status = customer.status
        rating = customer.rating
        ratingNote = customer.ratingNote
        notes = customer.notes
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func apply(to customer: Customer) {
        customer.name = trimmedName
        customer.sector = sector
        customer.city = city
        customer.district = district
        customer.industrialZone = industrialZone
        customer.address = address
        customer.status = status
        customer.rating = rating
        customer.ratingNote = ratingNote
        customer.notes = notes
    }
}

/// Müşteri ekleme (`customer == nil`) ve düzenleme formu.
struct CustomerFormView: View {
    let customer: Customer?
    let repository: CustomerRepository
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomerDraft
    @State private var errorMessage: String?
    /// "Diğer" seçildi: ilçe listede yok, elle yazılır.
    @State private var districtIsOther: Bool
    private let cityOptions: [String]

    /// - Parameter cities: Kullanıcının bölge şehirleri (`AppSettings.responsibleCities`).
    init(customer: Customer?, repository: CustomerRepository, cities: [String], onSaved: @escaping () -> Void = {}) {
        self.customer = customer
        self.repository = repository
        self.onSaved = onSaved
        var initial = customer.map { CustomerDraft(customer: $0) } ?? CustomerDraft()
        // Kayıtlı ilçe listedekiyle yalnızca yazım farkıyla eşleşiyorsa resmi yazıma çekilir.
        if let official = DistrictCatalog.match(initial.district, city: initial.city) { initial.district = official }
        _districtIsOther = State(initialValue: Self.isOtherDistrict(initial))
        _draft = State(initialValue: initial)
        // Müşterinin mevcut şehri bölge listesinde yoksa seçenek olarak korunur.
        var options = cities
        if !initial.city.isEmpty && !options.contains(initial.city) {
            options.append(initial.city)
        }
        cityOptions = options
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Firma") {
                    FormTextField(title: "Firma adı", text: $draft.name)
                    FormTextField(title: "Sektör", text: $draft.sector)
                }
                .listRowBackground(Theme.surface)

                Section("Konum") {
                    Picker("Şehir", selection: $draft.city) {
                        Text("Seçiniz").tag("")
                        ForEach(cityOptions, id: \.self) { city in
                            Text(city).tag(city)
                        }
                    }
                    districtField
                    FormTextField(title: "OSB", text: $draft.industrialZone)
                    FormMultilineField(title: "Adres", text: $draft.address, lines: 2...4)
                }
                .listRowBackground(Theme.surface)

                Section("Durum") {
                    Picker("Durum", selection: $draft.status) {
                        ForEach(CustomerStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Değerlendirme") {
                    Picker("Değerlendirme", selection: $draft.rating) {
                        ForEach(CustomerRating.allCases, id: \.self) { rating in
                            Text(rating.title).tag(rating)
                        }
                    }
                    .pickerStyle(.segmented)
                    FormMultilineField(title: "Kısa değerlendirme notu", text: $draft.ratingNote, lines: 1...3)
                }
                .listRowBackground(Theme.surface)

                Section("Notlar") {
                    FormMultilineField(title: "Notlar", text: $draft.notes, lines: 3...8)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: draft.city) { cityChanged() }
            .background(Theme.background)
            .navigationTitle(customer == nil ? "Yeni müşteri" : "Müşteriyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(draft.trimmedName.isEmpty)
                }
            }
            .alert("Kaydedilemedi", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Theme.brandText)
    }

    // MARK: - İlçe

    private static let otherTag = "\u{1}diger"

    /// Şehir katalogda ve ilçe boş değil ama listede yok → "Diğer" (elle yazılmış ilçe).
    private static func isOtherDistrict(_ draft: CustomerDraft) -> Bool {
        guard let list = DistrictCatalog.districts(forCity: draft.city) else { return false }
        return !draft.district.isEmpty && !list.contains(draft.district)
    }

    /// Şehrin resmi ilçe listesi varsa seçim (+ "Diğer" ile elle yazma); yoksa (yeni eklenen şehir veya şehir seçilmemiş)
    /// serbest metin.
    @ViewBuilder
    private var districtField: some View {
        if let list = DistrictCatalog.districts(forCity: draft.city) {
            Picker("İlçe", selection: districtSelection(list)) {
                Text("Seçiniz").tag("")
                ForEach(list, id: \.self) { district in
                    Text(district).tag(district)
                }
                Text("Diğer…").tag(Self.otherTag)
            }
            if districtIsOther {
                FormTextField(title: "İlçe (elle)", text: $draft.district)
            }
        } else {
            FormTextField(title: "İlçe", text: $draft.district)
        }
    }

    private func districtSelection(_ list: [String]) -> Binding<String> {
        Binding(
            get: { districtIsOther ? Self.otherTag : draft.district },
            set: { value in
                if value == Self.otherTag {
                    districtIsOther = true
                    if list.contains(draft.district) { draft.district = "" }
                } else {
                    districtIsOther = false
                    draft.district = value
                }
            }
        )
    }

    /// Şehir değişince: yeni şehrin listesinde olmayan ilçe temizlenir (elle yazılmış "Diğer" ilçe de yeni şehre ait değildir).
    private func cityChanged() {
        if let list = DistrictCatalog.districts(forCity: draft.city) {
            if !list.contains(draft.district) { draft.district = "" }
        }
        districtIsOther = false
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        do {
            if let customer {
                draft.apply(to: customer)
                try repository.update(customer)
            } else {
                let created = Customer(name: draft.trimmedName)
                draft.apply(to: created)
                try repository.add(created)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
