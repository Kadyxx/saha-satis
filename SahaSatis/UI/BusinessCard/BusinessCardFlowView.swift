import PhotosUI
import SwiftUI

/// "Kartvizit tara" sheet'inin hedefi.
struct CardScanSession: Identifiable {
    let id = UUID()
    /// Yalnızca ekran görüntüsü senaryoları: tarama atlanır, bu metin ayrıştırılır.
    var sampleText: String?
}

/// Kartvizit tarama: canlı tarama (desteklenmiyorsa fotoğraf seçme) → düzeltilebilir sonuç formu.
struct BusinessCardFlowView: View {
    private enum CameraState {
        case checking, live, unavailable
    }

    let repositories: Repositories
    let settings: AppSettings
    /// Müşteri detayından açıldıysa kişi doğrudan bu müşteriye eklenir.
    let fixedCustomer: Customer?
    let onFinished: () -> Void
    private let isSample: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var result: BusinessCardFields?
    @State private var cameraState: CameraState = .checking
    @State private var photoItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var message: String?
    @State private var scanner = CardScannerHandle()

    init(
        repositories: Repositories,
        settings: AppSettings,
        session: CardScanSession = CardScanSession(),
        fixedCustomer: Customer? = nil,
        onFinished: @escaping () -> Void = {}
    ) {
        self.repositories = repositories
        self.settings = settings
        self.fixedCustomer = fixedCustomer
        self.onFinished = onFinished
        isSample = session.sampleText != nil
        let cities = settings.responsibleCities
        _result = State(initialValue: session.sampleText.map { BusinessCardParser.parse(text: $0, cities: cities) })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    BusinessCardResultView(
                        fields: result,
                        repositories: repositories,
                        cities: settings.responsibleCities,
                        fixedCustomer: fixedCustomer,
                        onRescan: { self.result = nil },
                        onFinished: {
                            onFinished()
                            dismiss()
                        }
                    )
                } else {
                    scanContent
                }
            }
            .background(Theme.background)
            .navigationTitle(result == nil ? "Kartvizit tara" : "Kartvizit bilgileri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
        }
        .tint(Theme.brandText)
        .task {
            guard !isSample else { return }
            cameraState = await CardScannerView.prepare() ? .live : .unavailable
        }
        .onChange(of: photoItem) {
            guard let item = photoItem else { return }
            photoItem = nil
            Task { await read(item) }
        }
    }

    // MARK: - Tarama

    @ViewBuilder
    private var scanContent: some View {
        switch cameraState {
        case .checking:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .live:
            VStack(spacing: 12) {
                CardScannerView(handle: scanner)
                Text("Kartviziti kadraja alın; yazılar işaretlenince \"Metni al\"a dokunun.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                messageText
                Button { captureLive() } label: {
                    Label("Metni al", systemImage: "text.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brandText)
                .padding(.horizontal)
                photoPicker
                    .padding(.bottom, 8)
            }
        case .unavailable:
            VStack(spacing: 16) {
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.brandText)
                Text("Canlı tarama bu cihazda kullanılamıyor veya kamera izni yok. Kartvizitin fotoğrafını seçin; metin cihazınızda okunur.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                messageText
                photoPicker
                    .buttonStyle(.bordered)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var photoPicker: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            if isReading {
                ProgressView()
            } else {
                Label("Fotoğraftan seç", systemImage: "photo")
            }
        }
        .disabled(isReading)
    }

    @ViewBuilder
    private var messageText: some View {
        if let message {
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.overdue)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func captureLive() {
        show(lines: scanner.currentLines(), emptyMessage: "Henüz metin okunmadı. Kartviziti biraz daha yaklaştırın.")
    }

    @MainActor
    private func read(_ item: PhotosPickerItem) async {
        isReading = true
        defer { isReading = false }
        message = nil
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CardTextRecognizer.Failure.unreadableImage
            }
            let lines = try await CardTextRecognizer.lines(from: data)
            show(lines: lines, emptyMessage: "Fotoğrafta metin bulunamadı. Daha net bir fotoğraf deneyin.")
        } catch {
            message = "Metin okunamadı: \(error.localizedDescription)"
        }
    }

    private func show(lines: [String], emptyMessage: String) {
        guard !lines.isEmpty else {
            message = emptyMessage
            return
        }
        message = nil
        result = BusinessCardParser.parse(lines: lines, cities: settings.responsibleCities)
    }
}

/// Sonuç formu: alanlar dolu gelir, kullanıcı düzeltir. Firma mevcut bir müşteriyle eşleşiyorsa kişi ona eklenir;
/// yoksa müşteri formu dolu açılır.
struct BusinessCardResultView: View {
    let repositories: Repositories
    let cities: [String]
    let fixedCustomer: Customer?
    let onRescan: () -> Void
    let onFinished: () -> Void

    @State private var fields: BusinessCardFields
    @State private var customers: [Customer] = []
    @State private var showingCustomerForm = false
    @State private var createdCustomer = false
    @State private var errorMessage: String?

    init(
        fields: BusinessCardFields,
        repositories: Repositories,
        cities: [String],
        fixedCustomer: Customer?,
        onRescan: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        _fields = State(initialValue: fields)
        self.repositories = repositories
        self.cities = cities
        self.fixedCustomer = fixedCustomer
        self.onRescan = onRescan
        self.onFinished = onFinished
    }

    private var target: Customer? {
        fixedCustomer ?? BusinessCardMatcher.match(company: fields.company, in: customers)
    }

    private var trimmedName: String {
        fields.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("Kişi") {
                FormTextField(title: "Ad soyad", text: $fields.fullName, autocapitalization: .words)
                FormTextField(title: "Unvan", text: $fields.title, autocapitalization: .words)
                FormTextField(title: "Telefon", text: $fields.phone, keyboard: .phonePad)
                FormTextField(title: "E-posta", text: $fields.email, keyboard: .emailAddress, autocapitalization: .never)
            }
            .listRowBackground(Theme.surface)

            Section("Firma") {
                FormMultilineField(title: "Firma", text: $fields.company, lines: 1...3)
                FormTextField(title: "Web", text: $fields.website, keyboard: .URL, autocapitalization: .never)
                FormMultilineField(title: "Adres", text: $fields.address, lines: 1...4)
            }
            .listRowBackground(Theme.surface)

            Section {
                if !fields.otherPhones.isEmpty {
                    LabeledContent("Diğer telefon", value: fields.otherPhones.joined(separator: ", "))
                }
                Button { onRescan() } label: {
                    Label("Yeniden tara", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Alanlar tahmindir; kaydetmeden önce kontrol edin.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) { actionBar }
        .onAppear { customers = (try? repositories.customers.fetchAll()) ?? [] }
        .sheet(isPresented: $showingCustomerForm, onDismiss: {
            if createdCustomer { onFinished() }
        }) {
            CustomerFormView(
                customer: nil,
                repository: repositories.customers,
                cities: cities,
                initialDraft: BusinessCardImport.customerDraft(from: fields),
                onCreated: { addContact(toNew: $0) }
            )
        }
        .alert("Kaydedilemedi", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Alt çubuk

    private var actionBar: some View {
        VStack(spacing: 6) {
            if let target {
                Text(fixedCustomer == nil ? "Eşleşen müşteri: \(target.name)" : "Müşteri: \(target.name)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let warning = warning(for: target) {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(Theme.overdue)
                        .multilineTextAlignment(.center)
                }
                primaryButton("Bu müşteriye kişi olarak ekle", systemImage: "person.badge.plus") { add(to: target) }
                    .disabled(trimmedName.isEmpty)
            } else {
                Text("Eşleşen müşteri bulunamadı. Müşteri formu dolu açılır (durum: Aday).")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                primaryButton("Yeni müşteri oluştur", systemImage: "building.2") { showingCustomerForm = true }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private func primaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.onAction)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.action)
        .controlSize(.large)
    }

    private func warning(for target: Customer) -> String? {
        if trimmedName.isEmpty { return "Kişi eklemek için ad soyad yazın." }
        let name = DistrictCatalog.normalize(trimmedName)
        if (target.contacts ?? []).contains(where: { DistrictCatalog.normalize($0.fullName) == name }) {
            return "Bu müşteride aynı adlı bir kişi zaten var."
        }
        if fixedCustomer != nil, !fields.company.isEmpty,
           BusinessCardMatcher.match(company: fields.company, in: [target]) == nil {
            return "Karttaki firma adı bu müşteriden farklı görünüyor."
        }
        return nil
    }

    // MARK: - Kayıt

    private func add(to customer: Customer) {
        guard let contact = BusinessCardImport.contact(from: fields, includeWebsite: true) else { return }
        do {
            try repositories.contacts.add(contact, to: customer)
            onFinished()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Yeni müşteri kaydedilince karttaki kişi de eklenir.
    private func addContact(toNew customer: Customer) {
        createdCustomer = true
        guard let contact = BusinessCardImport.contact(from: fields, includeWebsite: false) else { return }
        do {
            try repositories.contacts.add(contact, to: customer)
        } catch {
            errorMessage = "Müşteri kaydedildi ama kişi eklenemedi: \(error.localizedDescription)"
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
