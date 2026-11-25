import SwiftData
import SwiftUI
import UserNotifications

@main
struct SahaSatisApp: App {
    private let container: ModelContainer
    private let context: AppContext

    init() {
        AppAppearance.configure()
        do {
            // DEBUG + `-DebugSampleData` başlatma argümanı: bellek içi depo ve hayali örnek veri
            // (ekran görüntüleri için). Release derlemesinde `useSampleData` her zaman false'tur.
            let useSampleData = DebugLaunch.useSampleData
            let container = try Persistence.makeContainer(inMemory: useSampleData)
            let repositories = Repositories.swiftData(context: container.mainContext)
            #if DEBUG
            if useSampleData {
                try SampleData.load(into: repositories)
                if let scene = DebugLaunch.scene, [.today, .todayForm, .export, .exportPreview].contains(scene) {
                    try SampleData.loadTodayShowcase(into: repositories)
                }
                if let scene = DebugLaunch.scene, [.region, .regionCity, .regionDistrict].contains(scene) {
                    try SampleData.loadRegionShowcase(into: repositories)
                }
            }
            #endif
            // Mevcut kayıtlardaki ilçe yazımları şehrin resmi listesiyle eşleştirilir (eşleşmeyenler olduğu gibi kalır).
            try? DistrictMigration.run(customers: repositories.customers)
            self.container = container
            let notificationScheduler: NotificationScheduling = DebugLaunch.skipNotifications
                ? NullNotificationScheduler()
                : SystemNotificationScheduler()
            let context = AppContext(
                repositories: repositories,
                settings: DebugLaunch.makeSettings(),
                makeSpeechEngine: DebugLaunch.speechEngineFactory(),
                notificationScheduler: notificationScheduler
            )
            if !DebugLaunch.skipNotifications {
                UNUserNotificationCenter.current().delegate = context.notificationResponder
            }
            self.context = context
        } catch {
            fatalError("Veri deposu açılamadı: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(
                repositories: context.repositories,
                settings: context.settings,
                debugScene: DebugLaunch.scene
            )
            .environmentObject(context)
        }
        .modelContainer(container)
        // Günde bir kez arka planda bildirimleri yeniden hesapla (sistem çalıştırmayı garanti etmez;
        // açılış ve veri değişimi asıl tetikleyicilerdir).
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            BackgroundRefresh.schedule()
            await context.reminders.refresh()
        }
    }
}
