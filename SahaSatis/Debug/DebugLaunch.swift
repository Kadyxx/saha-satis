import Foundation

/// Ekran görüntüsü / CI için başlatma seçenekleri. Yalnızca DEBUG derlemesinde etkindir;
/// Release (TestFlight) derlemesinde her zaman kapalıdır.
///
/// Kullanım (simülatör): `xcrun simctl launch <udid> <bundle> -DebugSampleData -DebugScene detail`
enum DebugScene: String {
    case customers
    case detail
    case form
    case settings
    case settingsReminders
    case settingsCities
}

enum DebugLaunch {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    /// Bellek içi depo + hayali örnek veri.
    static var useSampleData: Bool {
        arguments.contains("-DebugSampleData")
    }

    static var scene: DebugScene? {
        guard let index = arguments.firstIndex(of: "-DebugScene"), index + 1 < arguments.count else { return nil }
        return DebugScene(rawValue: arguments[index + 1])
    }
    #else
    static var useSampleData: Bool { false }
    static var scene: DebugScene? { nil }
    #endif

    /// Ayarlar nesnesi. Örnek veri modunda gerçek App Group ayarlarına dokunmayan geçici bir
    /// UserDefaults kümesi ve hayali profil kullanılır.
    static func makeSettings() -> AppSettings {
        #if DEBUG
        if useSampleData {
            let suiteName = "debug-sample-settings"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            let settings = AppSettings(defaults: defaults)
            settings.fullName = "Örnek Satış Mühendisi"
            settings.jobTitle = "Saha Satış Mühendisi"
            settings.crmEmail = "crm@example.com"
            return settings
        }
        #endif
        return AppSettings()
    }
}
