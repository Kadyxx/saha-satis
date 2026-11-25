import Foundation

/// Bekleyen bir teklifin geçerlilik durumu.
enum QuoteExpiryState: Equatable {
    case none
    /// Geçerlilik bitişine `daysLeft` gün var (0 = bugün bitiyor).
    case approaching(daysLeft: Int)
    case expired(daysAgo: Int)
}

/// Teklifler listesinin iki bölümü: geçerliliği yaklaşan/dolan (üstte, vurgulu) ve diğerleri.
struct QuoteSections {
    var approaching: [Quote] = []
    var others: [Quote] = []

    var isEmpty: Bool { approaching.isEmpty && others.isEmpty }
}

enum QuoteListing {
    /// Yalnızca bekleyen (Gönderildi/Takipte) ve geçerlilik tarihi olan teklifler: bitişe `warningDays` gün veya
    /// daha az kaldıysa "yaklaşıyor", bitiş günü geçtiyse "doldu".
    static func expiryState(for quote: Quote, warningDays: Int, now: Date, calendar: Calendar) -> QuoteExpiryState {
        guard quote.status.isPending, let valid = quote.validUntil else { return .none }
        let today = calendar.startOfDay(for: now)
        let validDay = calendar.startOfDay(for: valid)
        let diff = calendar.dateComponents([.day], from: today, to: validDay).day ?? 0
        if diff < 0 { return .expired(daysAgo: -diff) }
        return diff <= max(warningDays, 0) ? .approaching(daysLeft: diff) : .none
    }

    /// `filter == nil`: tümü. Yaklaşan/dolanlar üstte, bitişe en yakın (en çok gecikmiş) önce; diğerleri teklif
    /// tarihine göre yeniden eskiye.
    static func make(
        quotes: [Quote],
        filter: QuoteStatus?,
        warningDays: Int,
        now: Date,
        calendar: Calendar
    ) -> QuoteSections {
        let selected = quotes.filter { filter == nil || $0.status == filter }
        var sections = QuoteSections()
        for quote in selected {
            if expiryState(for: quote, warningDays: warningDays, now: now, calendar: calendar) == .none {
                sections.others.append(quote)
            } else {
                sections.approaching.append(quote)
            }
        }
        sections.approaching.sort { ($0.validUntil ?? .distantFuture, $0.quoteNumber) < ($1.validUntil ?? .distantFuture, $1.quoteNumber) }
        sections.others.sort { ($0.date, $0.quoteNumber) > ($1.date, $1.quoteNumber) }
        return sections
    }

    /// Satırdaki geçerlilik metni: "Geçerlilik: 2 gün kaldı", "Süresi dün doldu", "Geçerlilik: 28 Kas 2026".
    static func expiryText(for state: QuoteExpiryState, validUntil: Date?) -> String {
        switch state {
        case .approaching(let days):
            switch days {
            case 0: return "Geçerlilik bugün bitiyor"
            case 1: return "Geçerlilik yarın bitiyor"
            default: return "Geçerlilik: \(days) gün kaldı"
            }
        case .expired(let days):
            return days == 1 ? "Süresi dün doldu" : "Süresi \(days) gün önce doldu"
        case .none:
            return validUntil.map { "Geçerlilik: \(AppFormat.date($0))" } ?? ""
        }
    }

    static func counts(of quotes: [Quote]) -> [QuoteStatus: Int] {
        Dictionary(grouping: quotes, by: \.status).mapValues(\.count)
    }
}

/// Yeni teklif numarası önerisi: "T-2026-001" (yıl içindeki en büyük sıra + 1).
enum QuoteNumbering {
    static func suggest(existing: [String], date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let prefix = "T-\(year)-"
        let highest = existing.compactMap { number -> Int? in
            guard number.hasPrefix(prefix) else { return nil }
            return Int(number.dropFirst(prefix.count))
        }.max() ?? 0
        return prefix + String(format: "%03d", highest + 1)
    }
}
