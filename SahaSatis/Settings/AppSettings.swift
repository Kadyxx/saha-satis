import Foundation

/// Kullanıcı ayarları. SPEC: UserDefaults, App Group altında (widget de okuyabilsin).
/// Sorumlu şehir listesi sabit kodlanmaz; varsayılanı aşağıdadır ve Ayarlar ekranından
/// değiştirilebilecek şekilde `responsibleCities` üzerinden okunup yazılır.
final class AppSettings {
    /// İlk kullanıcının sorumlu bölgesi (SPEC → Amaç ve kapsam). Yeni kullanıcı kendi listesini ayarlar.
    static let defaultCities = [
        "Çanakkale", "Balıkesir", "Bursa", "Bilecik",
        "Yalova", "Eskişehir", "Kütahya", "Afyonkarahisar"
    ]

    private enum Key {
        static let responsibleCities = "responsibleCities"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppSettings.sharedDefaults) {
        self.defaults = defaults
    }

    /// App Group paylaşımlı UserDefaults. Grup kimliği Info.plist'teki `AppGroupID` anahtarından gelir
    /// (project.yml → APP_GROUP_ID); bulunamazsa standart UserDefaults kullanılır.
    static var sharedDefaults: UserDefaults {
        if let groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
           !groupID.isEmpty,
           let shared = UserDefaults(suiteName: groupID) {
            return shared
        }
        return .standard
    }

    var responsibleCities: [String] {
        get {
            let stored = defaults.stringArray(forKey: Key.responsibleCities) ?? []
            return stored.isEmpty ? Self.defaultCities : stored
        }
        set {
            defaults.set(newValue, forKey: Key.responsibleCities)
        }
    }
}
