import SwiftUI

enum AppTab: Hashable {
    case today, customers, pipeline, map, settings
}

/// Ana gezinme: Bugün, Müşteriler, Fırsat/Teklif, Harita, Ayarlar (SPEC → Modüller ve ekranlar).
struct RootTabView: View {
    let repositories: Repositories
    let settings: AppSettings
    let debugScene: DebugScene?

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
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            PlaceholderView(
                title: "Bugün",
                systemImage: "sun.max",
                message: "Gecikmiş ve bugünkü takipleriniz burada görünecek."
            )
            .tabItem { Label("Bugün", systemImage: "sun.max") }
            .tag(AppTab.today)

            CustomersView(repositories: repositories, settings: settings, debugScene: debugScene)
                .tabItem { Label("Müşteriler", systemImage: "building.2") }
                .tag(AppTab.customers)

            PlaceholderView(
                title: "Fırsat/Teklif",
                systemImage: "doc.text",
                message: "Fırsat hattı ve teklifleriniz burada olacak."
            )
            .tabItem { Label("Fırsat/Teklif", systemImage: "doc.text") }
            .tag(AppTab.pipeline)

            PlaceholderView(
                title: "Harita",
                systemImage: "map",
                message: "Müşterileriniz ve haftalık bölge planınız haritada görünecek."
            )
            .tabItem { Label("Harita", systemImage: "map") }
            .tag(AppTab.map)

            SettingsView(settings: settings, debugScene: debugScene)
                .tabItem { Label("Ayarlar", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // Küçük metin/düğme renkleri açık zeminde okunur olsun diye brandText (brand değil).
        .tint(Theme.brandText)
        // Arayüz dili Türkçe: sistemin otomatik büyük harf dönüşümü (bölüm başlıkları vb.) tr_TR ile yapılsın
        // ("Kişiler" → "KİŞİLER").
        .environment(\.locale, AppFormat.locale)
    }
}
