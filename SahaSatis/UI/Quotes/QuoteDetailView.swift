import SwiftUI

/// Teklif detayı: başlık, kalemler ve toplam, durum değiştirme (Kaybedildi'de sebep, Kazanıldı'da bağlı fırsat sorusu),
/// "Takip ayarları" (bu teklife özel takip günleri) ve kurulu hatırlatmalar.
struct QuoteDetailView: View {
    let quote: Quote
    let context: AppContext

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var askingLostReason = false
    @State private var lostReasonText = ""
    @State private var opportunityToWin: Opportunity?
    @State private var followUpText = ""
    @State private var errorMessage: String?

    private var rules: QuoteReminderRules { context.settings.quoteReminderRules }

    private var service: QuoteService {
        QuoteService(repositories: context.repositories, reminderRules: rules)
    }

    var body: some View {
        List {
            headerSection
            statusSection
            itemsSection
            followUpSection
            remindersSection
            if !quote.notes.isEmpty {
                Section("Notlar") {
                    Text(quote.notes).foregroundStyle(Theme.textPrimary)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .visitButton(customer: quote.customer)
        .navigationTitle("Teklif")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingEdit = true } label: { Label("Düzenle", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Teklifi sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear { followUpText = DayListFormat.format(quote.effectiveFollowUpDays(defaultDays: rules.defaultFollowUpDays)) }
        .sheet(isPresented: $showingEdit) {
            QuoteFormView(context: context, quote: quote)
        }
        .confirmationDialog("Bu teklif silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Teklifi sil", role: .destructive) { delete() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kalemleri ve bekleyen takip görevleri de silinir.")
        }
        .alert("Kayıp sebebi", isPresented: $askingLostReason) {
            TextField("Neden kaybedildi?", text: $lostReasonText)
            Button("Kaybedildi olarak kaydet") { setStatus(.lost, reason: lostReasonText) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("İsterseniz kısa bir sebep yazın. Bekleyen tüm takipler iptal edilir.")
        }
        .confirmationDialog(
            "Bağlı fırsat da Kazanıldı olsun mu?",
            isPresented: Binding(get: { opportunityToWin != nil }, set: { if !$0 { opportunityToWin = nil } }),
            titleVisibility: .visible,
            presenting: opportunityToWin
        ) { opportunity in
            Button("Evet, \"\(opportunity.title)\" Kazanıldı olsun") { winOpportunity(opportunity) }
            Button("Hayır, fırsat kalsın", role: .cancel) {}
        } message: { opportunity in
            Text("Bu teklif \"\(opportunity.title)\" fırsatına bağlı; fırsat şu an \"\(opportunity.stage.title)\" aşamasında.")
        }
        .alert("İşlem başarısız", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Bölümler

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(quote.quoteNumber.isEmpty ? "Teklif" : quote.quoteNumber)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    QuoteStatusBadge(status: quote.status)
                }
                if let customer = quote.customer {
                    Button { context.open(customer: customer) } label: {
                        Label(customer.name, systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(Theme.brandText)
                    }
                    .buttonStyle(.borderless)
                }
            }
            LabeledContent("Genel toplam") {
                Text(AppFormat.moneyExact(quote.totalAmount, currency: quote.currency))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            }
            LabeledContent("Tarih") {
                Text(AppFormat.date(quote.date)).foregroundStyle(Theme.textPrimary)
            }
            LabeledContent("Geçerlilik") {
                validityText
            }
            if let opportunity = quote.opportunity {
                NavigationLink(value: opportunity) {
                    LabeledContent("Fırsat") {
                        Text(opportunity.title)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(Theme.brandText)
                    }
                }
            }
            if quote.status == .lost {
                LabeledContent("Kayıp sebebi") {
                    Text(quote.lostReason.isEmpty ? "—" : quote.lostReason)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    @ViewBuilder
    private var validityText: some View {
        let state = QuoteListing.expiryState(
            for: quote, warningDays: context.settings.quoteExpiryWarningDays, now: Date(), calendar: .current
        )
        if let valid = quote.validUntil {
            switch state {
            case .expired:
                Label("\(AppFormat.date(valid)) · süresi doldu", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.overdue)
            case .approaching:
                Label("\(AppFormat.date(valid)) · yaklaşıyor", systemImage: "clock.badge.exclamationmark")
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.textPrimary)
            case .none:
                Text(AppFormat.date(valid)).foregroundStyle(Theme.textPrimary)
            }
        } else {
            Text("—").foregroundStyle(Theme.textSecondary)
        }
    }

    private var statusSection: some View {
        Section {
            Menu {
                ForEach(QuoteStatus.allCases, id: \.self) { status in
                    Button { change(to: status) } label: {
                        if status == quote.status {
                            Label(status.title, systemImage: "checkmark")
                        } else {
                            Text(status.title)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Durum").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    QuoteStatusBadge(status: quote.status)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            Text("Gönderildi olunca takip görevleri ve geçerlilik uyarısı oluşur; Kazanıldı, Kaybedildi veya Taslak olunca bekleyen tümü iptal edilir.")
        }
        .listRowBackground(Theme.surface)
    }

    private var itemsSection: some View {
        Section("Kalemler") {
            let items = quote.sortedItems
            if items.isEmpty {
                Text("Kalem yok. Düzenle ile ekleyin.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.catalogNumber.isEmpty ? "—" : item.catalogNumber)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 8)
                            Text(AppFormat.moneyExact(item.lineTotal, currency: quote.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        if !item.itemDescription.isEmpty {
                            Text(item.itemDescription)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(itemDetail(item))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if quote.subtotalAmount != quote.totalAmount {
                    LabeledContent("Ara toplam") {
                        Text(AppFormat.moneyExact(quote.subtotalAmount, currency: quote.currency))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledContent("Genel toplam") {
                    Text(AppFormat.moneyExact(quote.totalAmount, currency: quote.currency))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// "2 × 142.500,00 ₺ · %5 iskonto"
    private func itemDetail(_ item: QuoteItem) -> String {
        var text = "\(item.quantity) × \(AppFormat.moneyExact(item.unitPrice, currency: quote.currency))"
        if item.discountPercent > 0 {
            text += " · %\(AmountParser.editingText(item.discountPercent)) iskonto"
        }
        return text
    }

    /// "Takip ayarları": bu teklife özel takip günleri; varsayılana dönülebilir.
    private var followUpSection: some View {
        Section {
            Toggle("Ayarlardaki günleri kullan (\(DayListFormat.format(rules.defaultFollowUpDays)))", isOn: usesDefaultBinding)
            if !quote.followUpDays.isEmpty {
                LabeledContent("Takip günleri") {
                    TextField("3, 7", text: $followUpText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityLabel("Bu teklife özel takip günleri")
                        .onSubmit(applyFollowUpText)
                }
                Button("Günleri uygula", action: applyFollowUpText)
                    .buttonStyle(.borderless)
            }
        } header: {
            Text("Takip ayarları")
        } footer: {
            Text("Gönderimden kaç gün sonra hatırlatılsın (virgülle ayırın, ör. 2, 5, 10). Değişince bekleyen takip görevleri yeniden kurulur.")
        }
        .listRowBackground(Theme.surface)
    }

    /// Bu teklifin açık takip ve geçerlilik görevleri.
    @ViewBuilder
    private var remindersSection: some View {
        let tasks = (quote.tasks ?? []).filter { !$0.isDone }.sorted { $0.dueDate < $1.dueDate }
        if !tasks.isEmpty {
            Section("Kurulu hatırlatmalar") {
                ForEach(tasks) { task in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: task.source.systemImage)
                            .foregroundStyle(Theme.brandText)
                            .accessibilityHidden(true)
                        Text(task.title)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Text(AppFormat.date(task.dueDate))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    // MARK: - İşlemler

    private var usesDefaultBinding: Binding<Bool> {
        Binding(
            get: { quote.followUpDays.isEmpty },
            set: { useDefault in
                if useDefault {
                    apply(days: [])
                } else {
                    // Ayarlardaki günlerle başlayıp düzenlenebilir.
                    apply(days: rules.defaultFollowUpDays)
                    followUpText = DayListFormat.format(rules.defaultFollowUpDays)
                }
            }
        )
    }

    private func applyFollowUpText() {
        let days = DayListFormat.parse(followUpText)
        guard !days.isEmpty else { return }
        apply(days: days)
        followUpText = DayListFormat.format(days)
    }

    private func apply(days: [Int]) {
        do {
            try service.setFollowUpDays(quote, to: days)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func change(to status: QuoteStatus) {
        guard status != quote.status else { return }
        if status == .lost {
            lostReasonText = ""
            askingLostReason = true
        } else {
            setStatus(status, reason: nil)
        }
    }

    private func setStatus(_ status: QuoteStatus, reason: String?) {
        do {
            try service.setStatus(quote, to: status, lostReason: reason)
            if status == .won { opportunityToWin = QuoteService.opportunityToWin(for: quote) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func winOpportunity(_ opportunity: Opportunity) {
        do {
            try OpportunityService(
                repositories: context.repositories,
                reminderRules: context.settings.opportunityReminderRules
            ).setStage(opportunity, to: .won)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Silinen modele ekran hâlâ bakarken erişilmesin diye: önce ekrandan çık, kısa süre sonra sil.
    private func delete() {
        let service = self.service
        let target = quote
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            try? service.delete(target)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
