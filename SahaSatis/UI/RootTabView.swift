import SwiftUI

enum AppTab: Hashable {
    case today, customers, pipeline, region, settings
}

/// Ana gezinme: Bugün, Müşteriler, Fırsat/Teklif, Bölge, Ayarlar (SPEC → Modüller ve ekranlar).
struct RootTabView: View {
    let repositories: Repositories
    let settings: AppSettings
    let debugScene: DebugScene?

    @EnvironmentObject private var context: AppContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab
    /// Ekranda sorulan taslak (`context.pendingDraft`'ın kopyası: uyarı ilk görünümden sonra açılsın).
    @State private var draftPrompt: VisitFormDraft?

    init(repositories: Repositories, settings: AppSettings, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        self.settings = settings
        self.debugScene = debugScene
        _selection = State(initialValue: Self.initialTab(for: debugScene))
    }

    private static func initialTab(for scene: DebugScene?) -> AppTab {
        switch scene {
        case nil: return .today
        case .settings, .settingsReminders, .settingsCities, .settingsClaude, .settingsBackup: return .settings
        case .draftPrompt: return .today
        case .customers, .detail, .form, .visitForm, .visitRecording, .visitHistory,
             .importMapping, .importPreview, .installedBase, .installedBaseForm,
             .cardResult, .cardResultNew, .claudeButtons, .claudePreview, .claudeBroken: return .customers
        case .today, .todayForm, .export, .exportPreview, .weekDay: return .today
        case .opportunities, .opportunityDetail, .opportunityForm, .opportunityLost,
             .quotes, .quoteDetail, .quoteForm: return .pipeline
        case .region, .regionCity, .regionDistrict: return .region
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            TodayView(repositories: repositories, reminders: context.reminders, settings: settings, debugScene: debugScene)
            .tabItem { Label("Bugün", systemImage: "sun.max") }
            .tag(AppTab.today)

            CustomersView(repositories: repositories, settings: settings, debugScene: debugScene)
                .tabItem { Label("Müşteriler", systemImage: "building.2") }
                .tag(AppTab.customers)

            PipelineView(repositories: repositories, debugScene: debugScene)
            .tabItem { Label("Fırsat/Teklif", systemImage: "doc.text") }
            .tag(AppTab.pipeline)

            RegionView(repositories: repositories, settings: settings, debugScene: debugScene)
                .tabItem { Label("Bölge", systemImage: "square.grid.2x2") }
                .tag(AppTab.region)

            SettingsView(settings: settings, debugScene: debugScene)
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }

    var body: some View {
        Group {
            if context.isRestoring {
                ProgressView("Yedek geri yükleniyor…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                tabs
            }
        }
        // Küçük metin/düğme renkleri açık zeminde okunur olsun diye brandText (brand değil).
        .tint(Theme.brandText)
        // Arayüz dili Türkçe: sistemin otomatik büyük harf dönüşümü (bölüm başlıkları vb.) tr_TR ile yapılsın
        // ("Kişiler" → "KİŞİLER").
        .environment(\.locale, AppFormat.locale)
        // Hatırlatma motoru: açılışta izin + planlama; öne gelince yeniden planla; arka plana giderken
        // günlük yenileme isteği ver (DEBUG ekran görüntülerinde kapalı).
        .task {
            context.widgetReloader.start()
            context.widgetReloader.reloadNow()
            await context.reminders.start()
        }
        // Widget bağlantıları: görev aç, Bugün, yeni ziyaret.
        .onOpenURL { context.handle(url: $0) }
        .sheet(isPresented: $context.presentVisitForm) {
            VisitFormView(context: context, customer: nil, visit: nil)
        }
        // Uygulama kapanırken kaydedilmemiş ziyaret formu varsa.
        .alert("Yarım kalan ziyaret notu var", isPresented: draftPromptBinding, presenting: draftPrompt) { _ in
            // "Sil"e bilerek `.destructive` rolü verilmedi: o rolde sistem kendiliğinden "Vazgeç" ekliyor ve
            // soru yanıtsız kapanınca sonraki form taslağın üstüne yazabiliyor.
            Button("Devam et") { context.resumePendingDraft() }
            Button("Sil") { context.discardPendingDraft() }
        } message: { draft in
            Text(Self.draftMessage(draft))
        }
        .sheet(item: resumingDraftBinding) { item in
            VisitFormView(context: context, resuming: item.draft)
        }
        .alert("Yedekten geri yükleme", isPresented: restoreResultBinding, presenting: context.restoreResult) { _ in
            Button("Tamam", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onAppear { draftPrompt = context.pendingDraft }
        .onChange(of: context.pendingDraft) { draftPrompt = context.pendingDraft }
        .onChange(of: scenePhase) {
            guard !DebugLaunch.skipNotifications else { return }
            switch scenePhase {
            case .active: Task { await context.reminders.refresh() }
            case .background: BackgroundRefresh.schedule()
            default: break
            }
        }
        // Bildirime dokunma / Bugün satırı: istenen sekmeye geç.
        .onChange(of: context.requestedTab) { showRequestedTab() }
        .onAppear { showRequestedTab() }
    }

    // MARK: - Yarım kalan not ve geri yükleme

    private struct ResumingDraft: Identifiable {
        let draft: VisitFormDraft
        var id: Date { draft.savedAt }
    }

    private var draftPromptBinding: Binding<Bool> {
        Binding(get: { draftPrompt != nil }, set: { if !$0 { draftPrompt = nil } })
    }

    private var resumingDraftBinding: Binding<ResumingDraft?> {
        Binding(
            get: { context.resumingDraft.map { ResumingDraft(draft: $0) } },
            set: { if $0 == nil { context.resumingDraft = nil } }
        )
    }

    private var restoreResultBinding: Binding<Bool> {
        Binding(get: { context.restoreResult != nil }, set: { if !$0 { context.restoreResult = nil } })
    }

    private static func draftMessage(_ draft: VisitFormDraft) -> String {
        let saved = "\(AppFormat.date(draft.savedAt)) \(AppFormat.time(draft.savedAt))"
        let customer = draft.customerName.isEmpty ? "Müşteri seçilmemiş" : draft.customerName
        return "\(customer) · son değişiklik \(saved)"
    }

    private func showRequestedTab() {
        guard let tab = context.requestedTab else { return }
        selection = tab
        context.requestedTab = nil
    }
}
