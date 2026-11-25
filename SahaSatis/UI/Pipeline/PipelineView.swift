import SwiftUI

private struct QuoteFormTarget: Identifiable {
    let id = UUID()
    let quote: Quote?
}

private struct OpportunityFormTarget: Identifiable {
    let id = UUID()
    let opportunity: Opportunity?
    let customer: Customer?
}

/// Fırsat/Teklif sekmesi: üstte Fırsatlar / Teklifler seçici. Fırsatlar aşamalara göre gruplu liste; her grubun
/// başlığında adet ve para birimine göre toplam tutar. Kazanıldı / Kaybedildi grupları varsayılan kapalı.
struct PipelineView: View {
    let repositories: Repositories
    let debugScene: DebugScene?

    @EnvironmentObject private var appContext: AppContext
    @State private var model: PipelineModel
    @State private var quoteModel: QuoteListModel
    @State private var quoteFormTarget: QuoteFormTarget?
    @State private var segment: PipelineSegment = .opportunities
    @State private var path = NavigationPath()
    @State private var formTarget: OpportunityFormTarget?
    @State private var didRunDebugScene = false

    init(repositories: Repositories, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        self.debugScene = debugScene
        _model = State(initialValue: PipelineModel(repositories: repositories))
        _quoteModel = State(initialValue: QuoteListModel(repositories: repositories))
        let quoteScenes: [DebugScene] = [.quotes, .quoteDetail, .quoteForm]
        _segment = State(initialValue: debugScene.map { quoteScenes.contains($0) } == true ? .quotes : .opportunities)
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("Görünüm", selection: $segment) {
                    Text("Fırsatlar").tag(PipelineSegment.opportunities)
                    Text("Teklifler").tag(PipelineSegment.quotes)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch segment {
                case .opportunities: opportunitiesContent
                case .quotes: quotesContent
                }
            }
            .background(Theme.background)
            .visitButton(onSaved: { reloadAll() })
            .navigationTitle("Fırsat/Teklif")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if segment == .opportunities {
                            formTarget = OpportunityFormTarget(opportunity: nil, customer: nil)
                        } else {
                            quoteFormTarget = QuoteFormTarget(quote: nil)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(segment == .opportunities ? "Fırsat ekle" : "Teklif ekle")
                }
            }
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity, context: appContext)
            }
            .navigationDestination(for: Quote.self) { quote in
                QuoteDetailView(quote: quote, context: appContext)
            }
            .sheet(item: $quoteFormTarget, onDismiss: { reloadAll() }) { target in
                QuoteFormView(context: appContext, quote: target.quote, onSaved: { reloadAll() })
            }
            .sheet(item: $formTarget, onDismiss: { model.reload() }) { target in
                OpportunityFormView(
                    context: appContext,
                    opportunity: target.opportunity,
                    customer: target.customer,
                    onSaved: { model.reload() }
                )
            }
            .alert("Hata", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
        .onAppear { reloadAll() }
        .onReceive(NotificationCenter.default.publisher(for: .appDataDidChange)) { _ in reloadAll() }
        .task { await runDebugSceneIfNeeded() }
    }

    // MARK: - Fırsatlar

    @ViewBuilder
    private var opportunitiesContent: some View {
        if model.groups.isEmpty {
            ContentUnavailableView {
                Label("Henüz fırsat yok", systemImage: "chart.bar.doc.horizontal")
                    .foregroundStyle(Theme.textPrimary)
            } description: {
                Text("Sağ üstteki + ile ilk fırsatınızı ekleyin.")
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.groups) { group in
                    Section {
                        if model.isExpanded(group.stage) {
                            ForEach(group.opportunities) { opportunity in
                                NavigationLink(value: opportunity) {
                                    OpportunityRow(opportunity: opportunity)
                                }
                                .listRowBackground(Theme.surface)
                            }
                        }
                    } header: {
                        groupHeader(group)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Grup başlığı: aşama adı, adet ve para birimine göre toplam; dokununca açılır/kapanır.
    private func groupHeader(_ group: StageGroup) -> some View {
        Button {
            withAnimation { model.toggle(group.stage) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .rotationEffect(.degrees(model.isExpanded(group.stage) ? 90 : 0))
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(group.stage.title) (\(group.count))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    if !group.totals.isEmpty {
                        Text(PipelineGrouping.summary(group.totals))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
        .accessibilityLabel("\(group.stage.title), \(group.count) fırsat")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(model.isExpanded(group.stage) ? "Açık" : "Kapalı")
    }

    // MARK: - Teklifler

    private var quotesContent: some View {
        QuoteListView(model: quoteModel, warningDays: appContext.settings.quoteExpiryWarningDays)
    }

    private func reloadAll() {
        model.reload()
        quoteModel.reload(warningDays: appContext.settings.quoteExpiryWarningDays)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    // MARK: - Ekran görüntüsü senaryoları (yalnızca DEBUG başlatma argümanıyla)

    /// `SampleData`'daki örnek fırsatın başlığı (SampleData yalnızca DEBUG derlemesinde var).
    private static let showcaseTitle = "Hat 3 PLC yenileme"

    /// Örnek veride kalem içeren, bağlı fırsatlı gönderilmiş teklif (`SampleData`; yalnızca DEBUG'da var).
    private func showcaseQuote() -> Quote? {
        (try? repositories.quotes.fetchAll())?.first { $0.quoteNumber == "T-2026-014" }
    }

    private func runDebugSceneIfNeeded() async {
        guard let scene = debugScene, !didRunDebugScene else { return }
        didRunDebugScene = true
        reloadAll()
        let all = (try? repositories.opportunities.fetchAll()) ?? []
        switch scene {
        case .opportunityDetail:
            if let showcase = all.first(where: { $0.title == Self.showcaseTitle }) { path.append(showcase) }
        case .opportunityForm:
            if let showcase = all.first(where: { $0.title == Self.showcaseTitle }) {
                formTarget = OpportunityFormTarget(opportunity: showcase, customer: nil)
            }
        case .opportunityLost:
            if let lost = all.first(where: { $0.stage == .lost }) {
                formTarget = OpportunityFormTarget(opportunity: lost, customer: nil)
            }
        case .quoteDetail:
            if let quote = showcaseQuote() { path.append(quote) }
        case .quoteForm:
            if let quote = showcaseQuote() { quoteFormTarget = QuoteFormTarget(quote: quote) }
        default:
            break
        }
    }
}
