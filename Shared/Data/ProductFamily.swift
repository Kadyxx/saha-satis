import Foundation

/// Ürün ailesi tanımı (Ayarlar → Ürün aileleri): ad + varsayılan yaşam döngüsü + not. Kurulu bazda aile seçilince
/// yaşam döngüsü buradan gelir (elle değiştirilebilir). Değerler uygulama içinde güncellenebilir; gömülü örnekler
/// yalnızca başlangıçtır.
struct ProductFamily: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var lifecycleRaw: String
    var note: String

    init(id: UUID = UUID(), name: String, lifecycle: LifecycleStatus, note: String = "") {
        self.id = id
        self.name = name
        self.lifecycleRaw = lifecycle.rawValue
        self.note = note
    }

    var lifecycle: LifecycleStatus {
        get { LifecycleStatus(rawValue: lifecycleRaw) ?? .active }
        set { lifecycleRaw = newValue.rawValue }
    }

    static let verifyNote = "Rockwell yaşam döngüsü sayfasından doğrulayın"

    /// İlk açılış örnekleri. Durumlar güncel Rockwell duyurularına göre doğrulanmalıdır.
    static let defaults: [ProductFamily] = [
        ProductFamily(
            id: UUID(uuidString: "5C1A0001-0000-4000-8000-000000000001")!,
            name: "PLC-5", lifecycle: .discontinued, note: verifyNote
        ),
        ProductFamily(
            id: UUID(uuidString: "5C1A0001-0000-4000-8000-000000000002")!,
            name: "SLC 500", lifecycle: .endOfLife, note: verifyNote
        )
    ]

    /// Ada göre (büyük/küçük harf ve Türkçe karakter duyarsız) aile bulur.
    static func find(_ name: String, in families: [ProductFamily]) -> ProductFamily? {
        let key = DistrictCatalog.normalize(name)
        guard !key.isEmpty else { return nil }
        return families.first { DistrictCatalog.normalize($0.name) == key }
    }
}
