import SwiftUI

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
    @State private var segment: PipelineSegment = .opportunities
    @State private var path = NavigationPath()
    @State private var formTarget: OpportunityFormTarget?
    @State private var didRunDebugScene = false

    init(repositories: Repositories, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        self.debugScene = debugScene
        _model = State(initialValue: PipelineModel(repositories: repositories))
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
            .visitButton(onSaved: { model.reload() })
            .navigationTitle("Fırsat/Teklif")
            .toolbar {
                if segment == .opportunities {
                    ToolbarItem(placement: .primaryAction) {
                        Button { formTarget = OpportunityFormTarget(opportunity: nil, customer: nil) } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Fırsat ekle")
                    }
                }
            }
            .navigationDestination(for: Opportunity.self) { opportunity in
                OpportunityDetailView(opportunity: opportunity, context: appContext)
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
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .appDataDidChange)) { _ in model.reload() }
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
        ContentUnavailableView {
            Label("Teklifler", systemImage: "doc.text")
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text("Teklif formu ve listesi bir sonraki adımda eklenecek.")
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    // MARK: - Ekran görüntüsü senaryoları (yalnızca DEBUG başlatma argümanıyla)

    /// `SampleData`'daki örnek fırsatın başlığı (SampleData yalnızca DEBUG derlemesinde var).
    private static let showcaseTitle = "Hat 3 PLC yenileme"

    private func runDebugSceneIfNeeded() async {
        guard let scene = debugScene, !didRunDebugScene else { return }
        didRunDebugScene = true
        model.reload()
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
        default:
            break
        }
    }
}
