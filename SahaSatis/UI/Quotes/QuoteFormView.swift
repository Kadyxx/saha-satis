import SwiftUI

/// Teklif ekleme/düzenleme formu: no, tarih, geçerlilik, müşteri, bağlı fırsat, para birimi ve kalemler.
/// Satır ve genel toplam otomatik hesaplanır; kalemler eklenir, silinir ve ↑ ↓ ile sıralanır.
/// Durum (Taslak → Gönderildi …) detay ekranından değiştirilir. Düzenlemede müşteri sabittir.
struct QuoteFormView: View {
    let context: AppContext
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: QuoteFormModel

    init(
        context: AppContext,
        quote: Quote?,
        customer: Customer? = nil,
        opportunity: Opportunity? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        self.context = context
        self.onSaved = onSaved
        _model = State(initialValue: QuoteFormModel(
            repositories: context.repositories,
            reminderRules: context.settings.quoteReminderRules,
            defaultCurrency: context.settings.defaultCurrency,
            quote: quote,
            customer: customer,
            opportunity: opportunity
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                headerSection
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, row in
                    itemSection(index: index, rowID: row.id)
                }
                addItemSection
                totalsSection
                notesSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .onChange(of: model.customer?.id) { model.customerChanged() }
            .navigationTitle(model.isEditing ? "Teklifi düzenle" : "Yeni teklif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        if model.save() {
                            onSaved()
                            dismiss()
                        }
                    }
                    .disabled(!model.canSave)
                }
            }
            .alert("Kaydedilemedi", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .tint(Theme.brandText)
    }

    // MARK: - Bölümler

    private var customerSection: some View {
        Section {
            if model.isEditing {
                LabeledContent("Müşteri", value: model.customer?.name ?? "—")
            } else {
                NavigationLink {
                    CustomerPickerView(repository: context.repositories.customers, selection: $model.customer)
                } label: {
                    LabeledContent("Müşteri", value: model.customer?.name ?? "Seçiniz")
                }
            }
            if model.customer != nil {
                Picker("Bağlı fırsat", selection: $model.opportunityID) {
                    Text("Yok").tag(UUID?.none)
                    ForEach(model.availableOpportunities) { opportunity in
                        Text(opportunity.title).tag(UUID?.some(opportunity.id))
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var headerSection: some View {
        Section {
            FormTextField(title: "Teklif no", text: $model.number, autocapitalization: .characters)
            DatePicker("Tarih", selection: $model.date, displayedComponents: .date)
            Toggle("Geçerlilik tarihi", isOn: $model.hasValidUntil)
            if model.hasValidUntil {
                DatePicker("Geçerlilik", selection: $model.validUntil, in: model.date..., displayedComponents: .date)
            }
            Picker("Para birimi", selection: $model.currency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName).tag(currency)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Theme.surface)
    }

    private func itemSection(index: Int, rowID: UUID) -> some View {
        Section {
            if let row = model.items.first(where: { $0.id == rowID }) {
                FormTextField(title: "Katalog no", text: binding(rowID, \.catalogNumber), autocapitalization: .characters)
                FormMultilineField(title: "Açıklama", text: binding(rowID, \.itemDescription), lines: 1...3)
                LabeledContent("Adet") {
                    TextField("1", text: binding(rowID, \.quantityText))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .foregroundStyle(row.quantity == nil ? Theme.overdue : Theme.textPrimary)
                        .accessibilityLabel("Adet")
                }
                LabeledContent("Birim fiyat (\(model.currency.symbol))") {
                    TextField("0", text: binding(rowID, \.unitPriceText))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(row.unitPrice == nil ? Theme.overdue : Theme.textPrimary)
                        .accessibilityLabel("Birim fiyat")
                }
                LabeledContent("İskonto (%)") {
                    TextField("0", text: binding(rowID, \.discountText))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .foregroundStyle(row.discountPercent == nil ? Theme.overdue : Theme.textPrimary)
                        .accessibilityLabel("İskonto yüzdesi")
                }
                LabeledContent("Satır toplamı") {
                    Text(AppFormat.moneyExact(row.lineTotal, currency: model.currency))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        } header: {
            HStack {
                Text("Kalem \(index + 1)")
                Spacer()
                Menu {
                    Button { model.moveItem(rowID, by: -1) } label: { Label("Yukarı taşı", systemImage: "arrow.up") }
                        .disabled(!model.canMove(rowID, by: -1))
                    Button { model.moveItem(rowID, by: 1) } label: { Label("Aşağı taşı", systemImage: "arrow.down") }
                        .disabled(!model.canMove(rowID, by: 1))
                    Button(role: .destructive) { model.removeItem(rowID) } label: { Label("Kalemi sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .accessibilityLabel("Kalem \(index + 1) işlemleri")
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var addItemSection: some View {
        Section {
            Button { model.addItem() } label: {
                Label("Kalem ekle", systemImage: "plus")
            }
        } footer: {
            if !model.itemsAreValid {
                Text("Adet 1 veya daha büyük bir sayı, iskonto 0–100 arasında olmalı; kırmızı alanları düzeltin.")
                    .foregroundStyle(Theme.overdue)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var totalsSection: some View {
        Section {
            LabeledContent("Ara toplam") {
                Text(AppFormat.moneyExact(model.subtotal, currency: model.currency))
                    .foregroundStyle(Theme.textSecondary)
            }
            if model.discountTotal > 0 {
                LabeledContent("İskonto") {
                    Text("−" + AppFormat.moneyExact(model.discountTotal, currency: model.currency))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            LabeledContent("Genel toplam") {
                Text(AppFormat.moneyExact(model.total, currency: model.currency))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var notesSection: some View {
        Section {
            FormMultilineField(title: "Notlar", text: $model.notes, lines: 2...6)
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Yardımcılar

    /// Kalem satırındaki bir alana kimlikle bağlanır (sıra değişse de doğru satırı düzenler).
    private func binding(_ id: UUID, _ keyPath: WritableKeyPath<QuoteItemRow, String>) -> Binding<String> {
        Binding(
            get: { model.items.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { newValue in
                if let index = model.items.firstIndex(where: { $0.id == id }) {
                    model.items[index][keyPath: keyPath] = newValue
                }
            }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
