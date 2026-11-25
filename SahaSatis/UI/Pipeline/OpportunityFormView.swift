import SwiftUI

/// Fırsat ekleme/düzenleme formu (SPEC → Fırsat / Teklif). Düzenlemede müşteri sabittir.
struct OpportunityFormView: View {
    let context: AppContext
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: OpportunityFormModel

    init(context: AppContext, opportunity: Opportunity?, customer: Customer?, onSaved: @escaping () -> Void = {}) {
        self.context = context
        self.onSaved = onSaved
        _model = State(initialValue: OpportunityFormModel(
            repositories: context.repositories,
            reminderRules: context.settings.opportunityReminderRules,
            defaultCurrency: context.settings.defaultCurrency,
            opportunity: opportunity,
            customer: customer
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                infoSection
                amountSection
                stageSection
                closeDateSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(model.isEditing ? "Fırsatı düzenle" : "Yeni fırsat")
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
        }
        .listRowBackground(Theme.surface)
    }

    private var infoSection: some View {
        Section {
            FormTextField(title: "Başlık", text: $model.title)
            FormMultilineField(title: "Açıklama", text: $model.details, lines: 2...6)
        }
        .listRowBackground(Theme.surface)
    }

    private var amountSection: some View {
        Section {
            LabeledContent("Tahmini tutar") {
                TextField("0", text: $model.amountText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.decimalPad)
                    .foregroundStyle(model.amountIsValid ? Theme.textPrimary : Theme.overdue)
                    .accessibilityLabel("Tahmini tutar")
            }
            Picker("Para birimi", selection: $model.currency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName).tag(currency)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            if !model.amountIsValid {
                Text("Tutarı sayı olarak yazın (ör. 125000 veya 1.250,50).")
                    .foregroundStyle(Theme.overdue)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var stageSection: some View {
        Section {
            Picker("Aşama", selection: $model.stage) {
                ForEach(OpportunityStage.allCases, id: \.self) { stage in
                    Text(stage.title).tag(stage)
                }
            }
            if model.asksLostReason {
                FormMultilineField(title: "Kayıp sebebi", text: $model.lostReason, lines: 1...4)
            }
        } footer: {
            if model.asksLostReason {
                Text("Neden kaybedildi? İsteğe bağlı; bekleyen kapanış hatırlatması iptal edilir.")
            } else if model.stage == .won {
                Text("Kazanıldı olunca bekleyen kapanış hatırlatması iptal edilir.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var closeDateSection: some View {
        Section {
            Toggle("Beklenen kapanış tarihi", isOn: $model.hasCloseDate)
            if model.hasCloseDate {
                DatePicker("Tarih", selection: $model.closeDate, displayedComponents: .date)
            }
        } footer: {
            if model.hasCloseDate && model.stage.isOpen && context.settings.opportunityCloseReminderEnabled {
                Text("Kapanıştan \(context.settings.opportunityCloseReminderDays) gün önce hatırlatma oluşur (Ayarlar'dan değiştirilebilir).")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}
