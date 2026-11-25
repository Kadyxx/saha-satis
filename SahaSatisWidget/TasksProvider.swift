import SwiftUI
import WidgetKit

struct TasksEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Dört widget'ın ortak zaman çizelgesi sağlayıcısı. Veriyi App Group'taki ortak SwiftData deposundan okur.
/// Zaman çizelgesi: şu an + (24 saat içinde) her görev saatinde bir giriş + gece yarısı; gece yarısı yenilenir.
/// Uygulama görev/ziyaret/teklif değişince `WidgetCenter.shared.reloadAllTimelines()` çağırır.
struct TasksProvider: TimelineProvider {
    private func entry(_ data: WidgetData, at date: Date) -> TasksEntry {
        TasksEntry(date: date, snapshot: WidgetSnapshot.make(data: data, at: date, calendar: .current))
    }

    func placeholder(in context: Context) -> TasksEntry {
        entry(WidgetData.sample(now: Date()), at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (TasksEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(entry(WidgetData.sample(now: now), at: now))
            return
        }
        Task { @MainActor in
            completion(entry(WidgetDataLoader.loadFromStore(), at: now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TasksEntry>) -> Void) {
        Task { @MainActor in
            let now = Date()
            let calendar = Calendar.current
            let data = WidgetDataLoader.loadFromStore()
            let dates = WidgetSnapshot.entryDates(data: data, now: now, calendar: calendar)
            let entries = dates.map { entry(data, at: $0) }
            completion(Timeline(entries: entries, policy: .after(dates.last ?? now.addingTimeInterval(3600))))
        }
    }
}
