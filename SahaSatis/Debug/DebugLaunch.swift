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
    case visitForm
    case visitRecording
    case visitHistory
    case today
    case todayForm
    case export
    case exportPreview
    case opportunities
    case opportunityDetail
    case opportunityForm
    case opportunityLost
    case quotes
    case quoteDetail
    case quoteForm
    case region
    case regionCity
    case regionDistrict
    case importMapping
    case importPreview
}

enum DebugLaunch {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    /// Bellek içi depo + hayali örnek veri.
    static var useSampleData: Bool {
        arguments.contains("-DebugSampleData")
    }

    /// Örnek veri modunda veya `-DebugNoNotifications` ile: bildirim izni istenmez, sisteme hiçbir şey planlanmaz
    /// (izin penceresi ekran görüntülerini kapatmasın).
    static var skipNotifications: Bool {
        useSampleData || arguments.contains("-DebugNoNotifications")
    }

    static var scene: DebugScene? {
        guard let index = arguments.firstIndex(of: "-DebugScene"), index + 1 < arguments.count else { return nil }
        return DebugScene(rawValue: arguments[index + 1])
    }
    #else
    static var useSampleData: Bool { false }
    static var scene: DebugScene? { nil }
    static var skipNotifications: Bool { false }
    #endif

    /// Konuşma tanıma motoru üreticisi. Örnek veri modunda (simülatörde mikrofon yok) canlı metin gösteren
    /// sahte motor; aksi halde gerçek Apple Speech motoru.
    static func speechEngineFactory() -> () -> SpeechEngine {
        if useSampleData {
            return {
                MockSpeechEngine(autoEmit: [
                    "Bugün Örnek Makina'da Ahmet Bey ile görüştük, hat üç için PLC yenileme teklifi istediler"
                ])
            }
        }
        return { AppleSpeechEngine() }
    }

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
