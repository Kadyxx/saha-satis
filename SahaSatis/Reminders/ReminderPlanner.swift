import Foundation

/// Planlanan tek bir yerel bildirim. Sistem nesnelerinden bağımsızdır, bu yüzden birim testle denenebilir.
struct PlannedNotification: Equatable, Identifiable, Sendable {
    enum Kind: String, Sendable {
        case task
        case morningSummary
        case endOfDay
    }

    /// Kararlı kimlik (`task.<uuid>`, `summary.2026-11-25`, `endofday.2026-11-25`): aynı bildirim yeniden
    /// planlandığında aynı kimliği alır.
    let id: String
    let kind: Kind
    let title: String
    let body: String
    let fireDate: Date
    let taskID: UUID?
    let customerID: UUID?
}

/// Planlayıcının görevden ihtiyaç duyduğu alanlar (SwiftData nesnesinden bağımsız).
struct TaskSnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let customerName: String?
    let customerID: UUID?
    let dueDate: Date
}

/// Ayarlar'dan planlayıcıyı ilgilendiren değerler. Varsayılanlar SPEC'tekilerdir.
struct ReminderSettingsSnapshot: Equatable, Sendable {
    var morningSummaryEnabled = true
    var morningSummaryTime = TimeOfDay(hour: 8)
    var endOfDayEnabled = true
    var endOfDayTime = TimeOfDay(hour: 18)
    var weekendNotifications = false
}

/// Bekleyen bildirimleri hesaplayan saf mantık (SPEC → Hatırlatma motoru → Çalışma mantığı).
/// - Her açık görev için, vade saatinde bir bildirim (geçmişte kalanlar planlanmaz).
/// - Hafta sonu bildirimleri kapalıysa Cumartesi/Pazar'a düşen bildirim Pazartesi'ye kayar (saat korunur).
/// - Sabah özeti: önümüzdeki `summaryHorizonDays` gün için, o gün takibi (veya gecikmişi) olan iş günleri.
/// - Gün sonu: yalnızca bugün için, bugün aktarılmamış ziyaret varsa ve saat geçmediyse.
/// - iOS en fazla 64 bekleyen bildirime izin verir: hepsi zamana göre sıralanır ve en yakın 64'ü alınır.
enum ReminderPlanner {
    static let maxPendingNotifications = 64
    static let summaryHorizonDays = 7

    static func plan(
        tasks: [TaskSnapshot],
        unexportedVisitsToday: Int,
        settings: ReminderSettingsSnapshot,
        now: Date,
        calendar: Calendar,
        limit: Int = ReminderPlanner.maxPendingNotifications
    ) -> [PlannedNotification] {
        var result: [PlannedNotification] = []

        for task in tasks {
            let fire = notificationDate(
                for: task.dueDate,
                weekendNotifications: settings.weekendNotifications,
                calendar: calendar
            )
            guard fire > now else { continue }
            result.append(PlannedNotification(
                id: TaskNotificationID.make(for: task.id),
                kind: .task,
                title: task.customerName ?? "Takip hatırlatması",
                body: task.title,
                fireDate: fire,
                taskID: task.id,
                customerID: task.customerID
            ))
        }

        let today = calendar.startOfDay(for: now)

        if settings.morningSummaryEnabled {
            for offset in 0..<summaryHorizonDays {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if !settings.weekendNotifications && isWeekend(day, calendar: calendar) { continue }
                let fire = settings.morningSummaryTime.date(on: day, calendar: calendar)
                guard fire > now else { continue }
                let dueThatDay = tasks.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }.count
                let overdue = tasks.filter { $0.dueDate < day }.count
                guard let body = summaryBody(dueToday: dueThatDay, overdue: overdue) else { continue }
                result.append(PlannedNotification(
                    id: "summary.\(dayKey(day, calendar: calendar))",
                    kind: .morningSummary,
                    title: "Günaydın",
                    body: body,
                    fireDate: fire,
                    taskID: nil,
                    customerID: nil
                ))
            }
        }

        if settings.endOfDayEnabled, unexportedVisitsToday > 0,
           settings.weekendNotifications || !isWeekend(today, calendar: calendar) {
            let fire = settings.endOfDayTime.date(on: today, calendar: calendar)
            if fire > now {
                result.append(PlannedNotification(
                    id: "endofday.\(dayKey(today, calendar: calendar))",
                    kind: .endOfDay,
                    title: "Gün sonu",
                    body: "\(unexportedVisitsToday) ziyaret CRM'e aktarılmadı",
                    fireDate: fire,
                    taskID: nil,
                    customerID: nil
                ))
            }
        }

        result.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(result.prefix(max(0, limit)))
    }

    // MARK: - Yardımcılar

    /// Cumartesi (7) ve Pazar (1). Gregoryen hafta günü numaraları bölgeden bağımsızdır.
    static func isWeekend(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Bildirimin gerçek zamanı: hafta sonu kapalıysa Cumartesi/Pazar Pazartesi'ye kayar, saat korunur.
    static func notificationDate(for dueDate: Date, weekendNotifications: Bool, calendar: Calendar) -> Date {
        guard !weekendNotifications else { return dueDate }
        let shift: Int
        switch calendar.component(.weekday, from: dueDate) {
        case 7: shift = 2
        case 1: shift = 1
        default: shift = 0
        }
        guard shift > 0 else { return dueDate }
        return calendar.date(byAdding: .day, value: shift, to: dueDate) ?? dueDate
    }

    static func summaryBody(dueToday: Int, overdue: Int) -> String? {
        switch (dueToday, overdue) {
        case (0, 0): return nil
        case (let due, 0): return "Bugün \(due) takibiniz var"
        case (0, let late): return "\(late) gecikmiş takibiniz var"
        case (let due, let late): return "Bugün \(due) takip, \(late) gecikmiş"
        }
    }

    private static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
