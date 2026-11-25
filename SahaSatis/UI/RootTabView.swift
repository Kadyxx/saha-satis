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

    init(repositories: Repositories, settings: AppSettings, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        self.settings = settings
        self.debugScene = debugScene
        _selection = State(initialValue: Self.initialTab(for: debugScene))
    }

    private static func initialTab(for scene: DebugScene?) -> AppTab {
        switch scene {
        case nil: return .today
        case .settings, .settingsReminders, .settingsCities: return .settings
        case .customers, .detail, .form, .visitForm, .visitRecording, .visitHistory: return .customers
        case .today, .todayForm, .export, .exportPreview: return .today
        case .opportunities, .opportunityDetail, .opportunityForm, .opportunityLost,
             .quotes, .quoteDetail, .quoteForm: return .pipeline
        case .region, .regionCity, .regionDistrict: return .region
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView(repositories: repositories, reminders: context.reminders, debugScene: debugScene)
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

    private func showRequestedTab() {
        guard let tab = context.requestedTab else { return }
        selection = tab
        context.requestedTab = nil
    }
}
