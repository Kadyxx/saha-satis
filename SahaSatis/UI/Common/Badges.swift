import SwiftUI

extension CustomerRating {
    /// Rozet zemin rengi (SPEC → Renk paleti: Önemli = action, Potansiyelli = brand, Zayıf = gri).
    var badgeBackground: Color {
        switch self {
        case .important: return Theme.ratingImportant
        case .promising: return Theme.ratingPromising
        case .weak: return Theme.ratingWeak
        }
    }

    /// Rozet yazı rengi: turkuaz/turuncu/gri zeminin üstünde onAction / onBrand.
    var badgeForeground: Color {
        switch self {
        case .important: return Theme.onAction
        case .promising, .weak: return Theme.onBrand
        }
    }
}

struct RatingBadge: View {
    let rating: CustomerRating

    var body: some View {
        Text(rating.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(rating.badgeForeground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rating.badgeBackground, in: Capsule())
    }
}

/// Küçük etiket (ör. "Migrasyon fırsatı").
struct TagLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.onBrand)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.brand, in: Capsule())
    }
}
