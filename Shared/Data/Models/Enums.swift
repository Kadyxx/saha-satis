import Foundation

// SwiftData + CloudKit için modellerde bu enum'lar ham String olarak (`...Raw`) saklanır;
// modeller üzerinde güvenli erişim için `status`, `rating` gibi hesaplanan özellikler vardır.
// Arayüz metinleri (`title`) Türkçe, kod tanımlayıcıları İngilizcedir.

enum CustomerStatus: String, Codable, CaseIterable, Sendable {
    case current
    case potential
    case passive

    var title: String {
        switch self {
        case .current: return "Mevcut"
        case .potential: return "Aday"
        case .passive: return "Pasif"
        }
    }
}

enum CustomerRating: String, Codable, CaseIterable, Sendable {
    case important
    case promising
    case weak

    var title: String {
        switch self {
        case .important: return "Önemli"
        case .promising: return "Potansiyelli"
        case .weak: return "Zayıf"
        }
    }
}

enum VisitType: String, Codable, CaseIterable, Sendable {
    case visit
    case phone
    case online

    var title: String {
        switch self {
        case .visit: return "Yüz yüze"
        case .phone: return "Telefon"
        case .online: return "Online"
        }
    }
}

enum Currency: String, Codable, CaseIterable, Sendable {
    case tl = "TRY"
    case usd = "USD"
    case eur = "EUR"

    var code: String { rawValue }

    /// Arayüzde gösterilen kısa ad: TL, USD, EUR.
    var displayName: String {
        switch self {
        case .tl: return "TL"
        case .usd: return "USD"
        case .eur: return "EUR"
        }
    }

    var symbol: String {
        switch self {
        case .tl: return "₺"
        case .usd: return "$"
        case .eur: return "€"
        }
    }
}

enum OpportunityStage: String, Codable, CaseIterable, Sendable {
    case lead
    case qualified
    case quoted
    case negotiation
    case won
    case lost

    var title: String {
        switch self {
        case .lead: return "Yeni"
        case .qualified: return "Nitelikli"
        case .quoted: return "Teklif verildi"
        case .negotiation: return "Pazarlık"
        case .won: return "Kazanıldı"
        case .lost: return "Kaybedildi"
        }
    }

    var isOpen: Bool { self != .won && self != .lost }
}

enum QuoteStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case sent
    case followUp
    case won
    case lost

    var title: String {
        switch self {
        case .draft: return "Taslak"
        case .sent: return "Gönderildi"
        case .followUp: return "Takipte"
        case .won: return "Kazanıldı"
        case .lost: return "Kaybedildi"
        }
    }

    var isClosed: Bool { self == .won || self == .lost }
}

enum LifecycleStatus: String, Codable, CaseIterable, Sendable {
    case active
    case activeMature
    case endOfLife
    case discontinued

    var title: String {
        switch self {
        case .active: return "Aktif"
        case .activeMature: return "Aktif (olgun)"
        case .endOfLife: return "Ömrünü tamamlıyor"
        case .discontinued: return "Üretimden kalktı"
        }
    }

    /// "Migrasyon fırsatı" etiketi için: ömrünü tamamlayan veya üretimi duran ürünler.
    var isMigrationCandidate: Bool { self == .endOfLife || self == .discontinued }
}

enum TaskSource: String, Codable, CaseIterable, Sendable {
    case manual
    case visitNextStep
    case quoteFollowUp
    case quoteExpiry
    case visitFrequency
    case opportunityClose

    var title: String {
        switch self {
        case .manual: return "Elle eklendi"
        case .visitNextStep: return "Ziyaret sonraki adımı"
        case .quoteFollowUp: return "Teklif takibi"
        case .quoteExpiry: return "Teklif geçerlilik uyarısı"
        case .visitFrequency: return "Ziyaret sıklığı"
        case .opportunityClose: return "Fırsat kapanış tarihi"
        }
    }
}
