import SwiftUI

/// Fırsat detayı: bilgiler, aşama değiştirme, kapanış hatırlatması, bağlı ziyaretler ve bağlı teklifler.
struct OpportunityDetailView: View {
    let opportunity: Opportunity
    let context: AppContext

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var askingLostReason = false
    @State private var lostReasonText = ""
    @State private var visitTarget: Visit?
    @State private var errorMessage: String?

    private var service: OpportunityService {
        OpportunityService(repositories: context.repositories, reminderRules: context.settings.opportunityReminderRules)
    }

    var body: some View {
        List {
            headerSection
            stageSection
            if !opportunity.details.isEmpty {
                Section("Açıklama") {
                    Text(opportunity.details).foregroundStyle(Theme.textPrimary)
                }
                .listRowBackground(Theme.surface)
            }
            reminderSection
            visitsSection
            quotesSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .visitButton(customer: opportunity.customer)
        .navigationTitle("Fırsat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingEdit = true } label: { Label("Düzenle", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Fırsatı sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            OpportunityFormView(context: context, opportunity: opportunity, customer: nil)
        }
        .sheet(item: $visitTarget) { visit in
            VisitFormView(context: context, customer: visit.customer, visit: visit)
        }
        .confirmationDialog("Bu fırsat silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Fırsatı sil", role: .destructive) { delete() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Bağlı ziyaretler silinmez; yalnızca fırsatla bağlantıları kalkar.")
        }
        .alert("Kayıp sebebi", isPresented: $askingLostReason) {
            TextField("Neden kaybedildi?", text: $lostReasonText)
            Button("Kaybedildi olarak kaydet") { setStage(.lost, reason: lostReasonText) }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("İsterseniz kısa bir sebep yazın. Bekleyen kapanış hatırlatması iptal edilir.")
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
                Text(opportunity.title.isEmpty ? "Başlıksız fırsat" : opportunity.title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                if let customer = opportunity.customer {
                    Button { context.open(customer: customer) } label: {
                        Label(customer.name, systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundStyle(Theme.brandText)
                    }
                    .buttonStyle(.borderless)
                }
            }
            LabeledContent("Tahmini tutar") {
                Text(opportunity.estimatedValue > 0
                     ? AppFormat.money(opportunity.estimatedValue, currency: opportunity.currency)
                     : "—")
                    .foregroundStyle(Theme.textPrimary)
            }
            LabeledContent("Beklenen kapanış") {
                Text(opportunity.expectedCloseDate.map { AppFormat.date($0) } ?? "—")
                    .foregroundStyle(closeDateIsOverdue ? Theme.overdue : Theme.textPrimary)
            }
            if opportunity.stage == .lost {
                LabeledContent("Kayıp sebebi") {
                    Text(opportunity.lostReason.isEmpty ? "—" : opportunity.lostReason)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var closeDateIsOverdue: Bool {
        guard opportunity.stage.isOpen, let close = opportunity.expectedCloseDate else { return false }
        return close < Calendar.current.startOfDay(for: Date())
    }

    /// Aşama değiştirme: Kaybedildi seçilince sebep sorulur.
    private var stageSection: some View {
        Section {
            Menu {
                ForEach(OpportunityStage.allCases, id: \.self) { stage in
                    Button {
                        change(to: stage)
                    } label: {
                        if stage == opportunity.stage {
                            Label(stage.title, systemImage: "checkmark")
                        } else {
                            Text(stage.title)
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Aşama")
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    StageBadge(stage: opportunity.stage)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        } footer: {
            Text("Kazanıldı veya Kaybedildi olunca bekleyen kapanış hatırlatması iptal edilir.")
        }
        .listRowBackground(Theme.surface)
    }

    /// Kapanış tarihinden önce kurulan açık hatırlatma (varsa).
    @ViewBuilder
    private var reminderSection: some View {
        if let task = (opportunity.tasks ?? []).first(where: { $0.source == .opportunityClose && !$0.isDone }) {
            Section("Hatırlatma") {
                Label(AppFormat.dateTime(task.dueDate), systemImage: "bell")
                    .foregroundStyle(Theme.textPrimary)
            }
            .listRowBackground(Theme.surface)
        }
    }

    private var visitsSection: some View {
        Section("Bağlı ziyaretler") {
            let visits = (opportunity.visits ?? []).sorted { $0.date > $1.date }
            if visits.isEmpty {
                Text("Bu fırsata bağlı ziyaret yok. Ziyaret formunda \"Fırsat\" alanından bağlayabilirsiniz.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(visits) { visit in
                    Button { visitTarget = visit } label: {
                        VisitHistoryRow(visit: visit)
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var quotesSection: some View {
        Section("Bağlı teklifler") {
            let quotes = (opportunity.quotes ?? []).sorted { $0.date > $1.date }
            if quotes.isEmpty {
                Text("Henüz teklif yok. Teklifler bir sonraki adımda eklenecek.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(quotes) { quote in
                    HStack {
                        Text(quote.quoteNumber.isEmpty ? "Teklif" : quote.quoteNumber)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(quote.status.title)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - İşlemler

    private func change(to stage: OpportunityStage) {
        guard stage != opportunity.stage else { return }
        if stage == .lost {
            lostReasonText = ""
            askingLostReason = true
        } else {
            setStage(stage, reason: nil)
        }
    }

    private func setStage(_ stage: OpportunityStage, reason: String?) {
        do {
            try service.setStage(opportunity, to: stage, lostReason: reason)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Silinen modele ekran hâlâ bakarken erişilmesin diye: önce ekrandan çık, kısa süre sonra sil.
    private func delete() {
        let service = self.service
        let target = opportunity
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
