import Foundation

/// Widget'ların gösterdiği tek bir takip (SwiftData nesnesinden bağımsız değer; widget'lar ve testler bununla çalışır).
struct WidgetTask: Equatable, Hashable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let customerName: String?
    let dueDate: Date
}

struct WidgetMoney: Equatable, Sendable {
    let currency: Currency
    let amount: Double
}

/// Depodan okunan ham veri. Zamana bağlı her şey (`WidgetSnapshot.make`) bundan hesaplanır;
/// böylece bir zaman çizelgesindeki tüm girişler tek okumayla üretilir.
struct WidgetData: Equatable, Sendable {
    /// Açık (tamamlanmamış) görevler.
    var tasks: [WidgetTask] = []
    /// Bekleyen teklifler: durumu "Gönderildi" veya "Takipte".
    var pendingQuoteCount = 0
    var pendingQuoteTotals: [WidgetMoney] = []
    /// CRM'e aktarılmamış ziyaretler (tüm günler).
    var unexportedVisitCount = 0
}

struct WidgetDay: Equatable, Sendable, Identifiable {
    let day: Date
    let tasks: [WidgetTask]
    var id: Date { day }
}

/// Belirli bir andaki widget içeriği.
struct WidgetSnapshot: Equatable, Sendable {
    let date: Date
    /// Vade günü bugünden önce olanlar (gün bazlı, uygulamadaki Bugün ekranıyla aynı kural).
    let overdue: [WidgetTask]
    let today: [WidgetTask]
    /// Bugün ve sonraki 6 gün; yalnızca görevi olan günler (bugün dahil, gecikmişler hariç).
    let week: [WidgetDay]
    /// En yakın açık görev (gecikmişler en önde) ve gecikmiş mi.
    let next: WidgetTask?
    let nextIsOverdue: Bool
    let pendingQuoteCount: Int
    let pendingQuoteTotals: [WidgetMoney]
    let unexportedVisitCount: Int

    /// Gecikmiş + bugünkü görev sayısı ("Bekleyen iş sayısı").
    var pendingCount: Int { overdue.count + today.count }
    /// "Bugün için takip yok" durumu.
    var isEmptyToday: Bool { pendingCount == 0 }

    static func make(data: WidgetData, at date: Date, calendar: Calendar) -> WidgetSnapshot {
        let dayStart = calendar.startOfDay(for: date)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let sorted = data.tasks.sorted { ($0.dueDate, $0.id.uuidString) < ($1.dueDate, $1.id.uuidString) }

        let overdue = sorted.filter { $0.dueDate < dayStart }
        let today = sorted.filter { $0.dueDate >= dayStart && $0.dueDate < tomorrowStart }

        var week: [WidgetDay] = []
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let tasks = sorted.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
            if !tasks.isEmpty { week.append(WidgetDay(day: day, tasks: tasks)) }
        }

        let next = sorted.first
        return WidgetSnapshot(
            date: date,
            overdue: overdue,
            today: today,
            week: week,
            next: next,
            nextIsOverdue: next.map { $0.dueDate < dayStart } ?? false,
            pendingQuoteCount: data.pendingQuoteCount,
            pendingQuoteTotals: data.pendingQuoteTotals,
            unexportedVisitCount: data.unexportedVisitCount
        )
    }

    /// Zaman çizelgesi giriş zamanları (SPEC: şu an + her görev saatinde bir giriş, en fazla 24 saat;
    /// gece yarısı yenilenir). Sonuncu eleman her zaman bir sonraki gece yarısıdır.
    static func entryDates(data: WidgetData, now: Date, calendar: Calendar, maxTaskEntries: Int = 20) -> [Date] {
        let midnight = nextMidnight(after: now, calendar: calendar)
        let horizon = min(now.addingTimeInterval(24 * 3600), midnight)
        let taskTimes = Set(data.tasks.map(\.dueDate).filter { $0 > now && $0 < horizon })
            .sorted()
            .prefix(maxTaskEntries)
        return [now] + Array(taskTimes) + [midnight]
    }

    static func nextMidnight(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(24 * 3600)
    }
}

extension WidgetData {
    /// Widget galerisi ve ekran görüntüleri için hayali örnek veri. Gerçek müşteri verisi değildir.
    static func sample(now: Date, calendar: Calendar = .current) -> WidgetData {
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func task(_ n: Int, _ title: String, _ customer: String?, _ due: Date) -> WidgetTask {
            WidgetTask(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)) ?? UUID(),
                title: title, customerName: customer, dueDate: due
            )
        }
        return WidgetData(
            tasks: [
                task(1, "Bakım sözleşmesi örneğini gönder", "Örnek Makina A.Ş.", at(-2, 9)),
                task(2, "Fiyat listesi güncellemesini ilet", "Marmara Gıda", at(-1, 14)),
                task(3, "Ziyaret zamanı geldi", "Anadolu Seramik", at(0, 9)),
                task(4, "Hat 3 teklifini hazırla", "Örnek Makina A.Ş.", at(0, 10, 30)),
                task(5, "Satın alma ile telefon görüşmesi", "Deniz Otomotiv", at(0, 16)),
                task(6, "Numune ürün listesini gönder", "Marmara Gıda", at(1, 9)),
                task(7, "Kuzey Tekstil'i ara", "Kuzey Tekstil", at(1, 11)),
                task(8, "Teklif takibi", "Örnek Makina A.Ş.", at(3, 10)),
                task(9, "Fırın otomasyonu toplantısı", "Anadolu Seramik", at(5, 14)),
            ],
            pendingQuoteCount: 3,
            pendingQuoteTotals: [WidgetMoney(currency: .tl, amount: 480_000), WidgetMoney(currency: .usd, amount: 12_500)],
            unexportedVisitCount: 2
        )
    }
}
