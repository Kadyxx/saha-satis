import SwiftData
import SwiftUI

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
            }
            #endif
            self.container = container
            self.context = AppContext(
                repositories: repositories,
                settings: DebugLaunch.makeSettings(),
                makeSpeechEngine: DebugLaunch.speechEngineFactory()
            )
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
    }
}
