import Foundation

/// "Ertele" seçenekleri (SPEC → Bugün: 1 gün, 3 gün, 1 hafta, tarih seç).
enum PostponeOption: Hashable, Sendable {
    /// Bugünden (vadesi ileri bir güne düşüyorsa o günden) itibaren N gün sonra.
    case days(Int)
    /// Seçilen gün.
    case date(Date)

    /// Bildirimdeki "Yarına ertele" aksiyonu.
    static let tomorrow = PostponeOption.days(1)
    /// Hızlı seçenekler.
    static let presets: [PostponeOption] = [.days(1), .days(3), .days(7)]

    var title: String {
        switch self {
        case .days(7): return "1 hafta"
        case .days(let count): return "\(count) gün"
        case .date: return "Tarih seç…"
        }
    }
}

enum PostponeRule {
    /// Yeni vade. Görevin saati (hatırlatma saati) korunur, yalnızca gün değişir.
    /// `.days(n)`: gecikmiş görevler bugünden sayar (dünün üstüne eklemek hâlâ geçmişte kalabilir),
    /// ileri tarihli görevler kendi gününden sayar.
    static func newDueDate(current: Date, option: PostponeOption, now: Date, calendar: Calendar) -> Date {
        let time = TimeOfDay(date: current, calendar: calendar)
        switch option {
        case .days(let count):
            let base = max(calendar.startOfDay(for: now), calendar.startOfDay(for: current))
            let day = calendar.date(byAdding: .day, value: count, to: base) ?? base
            return time.date(on: day, calendar: calendar)
        case .date(let chosen):
            return time.date(on: chosen, calendar: calendar)
        }
    }
}
