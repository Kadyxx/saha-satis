import SwiftUI

/// Renk paleti. Değerler Shared/Assets.xcassets içindeki açık/koyu "Color Set"lerde tanımlıdır
/// (docs/SPEC.md → "Renk paleti"). Kodda doğrudan hex kullanılmaz; yalnızca bu sabitler kullanılır.
///
/// Kontrast kuralı: `brand` (#76ABAE) ve `action` (#FF5722) açık zeminde küçük yazı rengi olarak
/// kullanılmaz. Turkuaz yazı için `brandText`, bu renklerin üstündeki yazı için `onBrand` / `onAction`.
enum Theme {
    // Zemin ve yüzeyler
    static let background = Color("background")
    static let surface = Color("surface")

    // Yazı
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let brandText = Color("brandText")

    // Vurgu renkleri
    static let brand = Color("brand")
    static let action = Color("action")
    static let onAction = Color("onAction")
    static let onBrand = Color("onBrand")

    // Durum
    static let overdue = Color("overdue")
    static let done = Color("done")

    // Değerlendirme rozetleri (CustomerRating)
    static let ratingImportant = action
    static let ratingPromising = brand
    static let ratingWeak = Color("ratingWeak")
}
