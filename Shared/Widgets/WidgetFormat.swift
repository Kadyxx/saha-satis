import Foundation

/// Widget metinleri (saf mantık; testle denenir).
enum WidgetFormat {
    static let emptyTodayText = "Bugün için takip yok"

    /// Takibin zamanı: gecikmiş "Gecikmiş · 23 Kas", bugün "Bugün 09:00", yarın "Yarın 09:00", sonrası "28 Kas Cum 09:00".
    static func dueText(for task: WidgetTask, now: Date, calendar: Calendar) -> String {
        let todayStart = calendar.startOfDay(for: now)
        let time = AppFormat.time(task.dueDate)
        if task.dueDate < todayStart {
            return "Gecikmiş · \(AppFormat.date(task.dueDate).split(separator: " ").prefix(2).joined(separator: " "))"
        }
        if calendar.isDate(task.dueDate, inSameDayAs: now) { return "Bugün \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: todayStart),
           calendar.isDate(task.dueDate, inSameDayAs: tomorrow) {
            return "Yarın \(time)"
        }
        return "\(AppFormat.shortDay(task.dueDate)) \(time)"
    }

    /// Hafta görünümündeki gün başlığı: "Bugün", "Yarın", "28 Kas Cum".
    static func dayTitle(_ day: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Bugün" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Yarın"
        }
        return AppFormat.shortDay(day)
    }

    /// "3 teklif bekliyor" ve varsa toplamlar: "480.000 ₺ · 12.500 $".
    static func quoteSummary(count: Int, totals: [WidgetMoney]) -> String {
        guard count > 0 else { return "Bekleyen teklif yok" }
        let money = totals.map { AppFormat.money($0.amount, currency: $0.currency) }.joined(separator: " · ")
        return money.isEmpty ? "\(count) teklif bekliyor" : "\(count) teklif bekliyor · \(money)"
    }

    static func unexportedText(_ count: Int) -> String {
        count == 0 ? "Tüm ziyaretler aktarıldı" : "\(count) ziyaret CRM'e aktarılmadı"
    }
}

/// Büyük (haftalık) widget'ın satır sığdırma hesabı: satır yükseklikleri sabittir, kullanılabilir yüksekliğe
/// sığdığı kadar satır gösterilir; sığmayanlar "+N takip daha" ile belirtilir (saf mantık; testle denenir).
enum WeekWidgetLayout {
    static let headerHeight: CGFloat = 16
    static let taskHeight: CGFloat = 22
    static let moreHeight: CGFloat = 14
    static let spacing: CGFloat = 5

    /// - Parameters:
    ///   - isHeader: Her satır için başlık (true) veya görev (false).
    ///   - height: Listeye ayrılan toplam yükseklik.
    /// - Returns: Gösterilecek satır sayısı ve gizli kalan görev sayısı. Sona yalnız kalan gün başlığı atılır;
    ///   gizli görev varsa "+N takip daha" satırına yer ayrılır.
    static func fit(isHeader: [Bool], height: CGFloat) -> (shown: Int, hiddenTasks: Int) {
        var used: CGFloat = 0
        var shown = 0
        for (index, header) in isHeader.enumerated() {
            let lineHeight = header ? headerHeight : taskHeight
            let next = used + (shown > 0 ? spacing : 0) + lineHeight
            let isLast = index == isHeader.count - 1
            let reserve = isLast ? 0 : spacing + moreHeight
            if next + reserve > height { break }
            used = next
            shown += 1
        }
        while shown > 0, isHeader[shown - 1] { shown -= 1 }
        let hidden = isHeader.dropFirst(shown).filter { !$0 }.count
        return (shown, hidden)
    }
}
