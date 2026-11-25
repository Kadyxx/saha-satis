import SwiftUI

/// Ziyaret kaydı (SPEC → Ziyaret kaydı): müşteri, görüşülen kişiler, tip, tarih, sesli/yazılı not,
/// sonraki adım ve takip tarihi. `visit != nil` ise mevcut ziyareti düzenler.
struct VisitFormView: View {
    let context: AppContext
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: VisitFormModel

    init(
        context: AppContext,
        customer: Customer?,
        visit: Visit?,
        seed: VisitFormSeed = VisitFormSeed(),
        onSaved: @escaping () -> Void = {}
    ) {
        self.context = context
        self.onSaved = onSaved
        _model = State(initialValue: VisitFormModel(
            repositories: context.repositories,
            reminderMinutes: context.settings.defaultReminderTime.minutesSinceMidnight,
            defaultCurrency: context.settings.defaultCurrency,
            engine: context.makeSpeechEngine(),
            customer: customer,
            visit: visit,
            seed: seed
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                customerSection
                contactsSection
                topicSection
                opportunitySection
                detailsSection
                VoiceNoteSection(controller: model.voice)
                noteSection
                nextStepSection
            }
            .scrollContentBackground(.hidden)
            .onChange(of: model.customer?.id) { model.customerChanged() }
            .background(Theme.background)
            .navigationTitle(model.isEditing ? "Ziyareti düzenle" : "Yeni ziyaret")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") {
                        model.voice.stop()
                        dismiss()
                    }
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
            .task {
                if model.seed.autoStartRecording {
                    await model.voice.start()
                }
            }
            .onDisappear { model.voice.stop() }
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

    @ViewBuilder
    private var contactsSection: some View {
        if model.customer != nil {
            Section("Görüşülen kişiler") {
                if model.contacts.isEmpty {
                    Text("Bu müşteride kayıtlı kişi yok.")
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(model.contacts) { contact in
                        Button {
                            model.toggleContact(contact)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.fullName)
                                        .foregroundStyle(Theme.textPrimary)
                                    if !contact.title.isEmpty {
                                        Text(contact.title)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: model.selectedContactIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.selectedContactIDs.contains(contact.id) ? Theme.brandText : Theme.textSecondary)
                            }
                        }
                        .accessibilityAddTraits(model.selectedContactIDs.contains(contact.id) ? .isSelected : [])
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var topicSection: some View {
        Section {
            FormTextField(title: "Konu", text: $model.topic)
            let suggestions = model.topicSuggestions
            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Önceki konular")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button { model.topic = suggestion } label: {
                                    Text(suggestion)
                                        .font(.footnote)
                                        .foregroundStyle(Theme.brandText)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Theme.brand.opacity(0.2), in: Capsule())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Konu")
        } footer: {
            Text("İsteğe bağlı. CRM raporunda \"Konu\" satırına yazılır.")
        }
        .listRowBackground(Theme.surface)
    }

    /// "Fırsata bağla / yeni fırsat aç": müşterinin açık fırsatları veya yeni fırsat başlığı.
    @ViewBuilder
    private var opportunitySection: some View {
        if model.customer != nil {
            Section {
                Picker("Fırsat", selection: $model.opportunityLink) {
                    Text("Bağlama").tag(OpportunityLink.none)
                    ForEach(model.availableOpportunities) { opportunity in
                        Text(opportunity.title).tag(OpportunityLink.existing(opportunity.id))
                    }
                    Text("Yeni fırsat aç…").tag(OpportunityLink.new)
                }
                if model.opportunityLink == .new {
                    FormTextField(title: "Fırsat başlığı", text: $model.newOpportunityTitle)
                }
            } header: {
                Text("Fırsat")
            } footer: {
                if model.opportunityLink == .new {
                    Text("Kaydedince bu müşteri için \"Yeni\" aşamasında bir fırsat açılır; ayrıntılarını Fırsat/Teklif sekmesinden tamamlayabilirsiniz.")
                } else {
                    Text("İsteğe bağlı. Ziyareti bir fırsata bağlarsanız fırsatın detayında görünür.")
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var detailsSection: some View {
        Section("Ziyaret") {
            Picker("Ziyaret tipi", selection: $model.type) {
                ForEach(VisitType.allCases, id: \.self) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            DatePicker("Tarih", selection: $model.date)
        }
        .listRowBackground(Theme.surface)
    }

    private var noteSection: some View {
        Section {
            FormMultilineField(title: "Görüşme notu", text: $model.note, lines: 4...12)
        } footer: {
            Text("Sesli not parçaları buraya eklenir; metni istediğiniz gibi düzenleyebilirsiniz.")
        }
        .listRowBackground(Theme.surface)
    }

    private var nextStepSection: some View {
        Section {
            FormMultilineField(title: "Sonraki adım", text: $model.nextStep, lines: 1...3)
            Toggle("Takip tarihi belirle", isOn: $model.hasNextStepDate)
            if model.hasNextStepDate {
                DatePicker("Takip tarihi", selection: $model.nextStepDate, displayedComponents: .date)
            }
        } header: {
            Text("Sonraki adım")
        } footer: {
            if model.hasNextStepDate {
                Text("Seçilen günde hatırlatma saatinde bir takip görevi oluşur.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

/// Sesli not: başlat / duraklat / devam / bitir, canlı metin ve izin/durum mesajları.
struct VoiceNoteSection: View {
    let controller: VoiceNoteController
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            controls
            if controller.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.action)
                        .frame(width: 10, height: 10)
                    Text(controller.partialText.isEmpty ? "Dinleniyor…" : controller.partialText)
                        .foregroundStyle(controller.partialText.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
            statusMessage
        } header: {
            Text("Sesli not")
        } footer: {
            Text("Mikrofon izni vermeseniz de notu klavyeyle yazabilirsiniz.")
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            switch controller.state {
            case .recording:
                Button { controller.pause() } label: {
                    Label("Duraklat", systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)
                Button { controller.stop() } label: {
                    Label("Bitir", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            case .paused:
                Button { Task { await controller.start() } } label: {
                    Label("Devam et", systemImage: "mic.fill")
                        .foregroundStyle(Theme.onAction)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.action)
                Button { controller.stop() } label: {
                    Label("Bitir", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            default:
                Button { Task { await controller.start() } } label: {
                    Label("Konuşmaya başla", systemImage: "mic.fill")
                        .foregroundStyle(Theme.onAction)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.action)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch controller.state {
        case .permissionDenied:
            VStack(alignment: .leading, spacing: 6) {
                Text("Mikrofon veya konuşma tanıma izni verilmedi. Notu klavyeyle yazabilirsiniz.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                Button("İzinleri Ayarlar'dan aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderless)
            }
        case .unavailable:
            Text("Konuşma tanıma bu cihazda şu anda kullanılamıyor. Notu klavyeyle yazabilirsiniz.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        case .failed(let message):
            Text("Sesli not durdu: \(message). Notu klavyeyle yazabilir veya tekrar deneyebilirsiniz.")
                .font(.callout)
                .foregroundStyle(Theme.overdue)
        case .idle, .recording, .paused:
            EmptyView()
        }
    }
}
