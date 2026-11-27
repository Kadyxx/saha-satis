import Foundation

/// App Group durumu. Kimlik Info.plist'teki `AppGroupID` anahtarından gelir (project.yml → APP_GROUP_ID).
/// İmzalamada App Group verilemediyse (ör. ücretsiz Apple ID ile yetki kaldırıldıysa) grup klasörü yoktur:
/// uygulama kendi klasörünü kullanır, widget'lar boş durum gösterir.
enum AppGroup {
    static var identifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String, !id.isEmpty else { return nil }
        return id
    }

    static var isAvailable: Bool {
        guard let identifier else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}
