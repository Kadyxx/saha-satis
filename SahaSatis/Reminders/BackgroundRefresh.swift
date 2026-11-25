import BackgroundTasks
import Foundation

/// Günde bir kez arka planda bildirimleri yeniden hesaplatan `BGAppRefreshTask`.
/// Kimlik `project.yml` içindeki `BGTaskSchedulerPermittedIdentifiers` ile aynı olmalıdır: `<bundle id>.refresh`.
/// Sistem çalıştırmayı garanti etmez (simülatörde hiç çalışmaz); uygulama açılışı ve veri değişimi yedeğidir.
enum BackgroundRefresh {
    static var identifier: String {
        (Bundle.main.bundleIdentifier ?? "com.example.sahasatis") + ".refresh"
    }

    /// Bir sonraki sabahın erken saati (varsayılan 05:00): sabah özeti ve gün görevleri güncel olsun.
    static func nextEarliestDate(after now: Date, hour: Int = 5, calendar: Calendar = .current) -> Date {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: hour, minute: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(24 * 3600)
    }

    static func schedule(now: Date = Date()) {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = nextEarliestDate(after: now)
        try? BGTaskScheduler.shared.submit(request)
    }
}
