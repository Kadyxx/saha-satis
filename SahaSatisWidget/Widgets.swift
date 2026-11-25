import SwiftUI
import WidgetKit

/// Ana ekran, orta: gecikmiş + bugünün ilk görevleri, her satırda onay kutusu.
struct TodayTasksWidget: Widget {
    let kind = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            TodayTasksWidgetView(snapshot: entry.snapshot)
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName("Bugünün takipleri")
        .description("Gecikmiş ve bugünkü takipleriniz. Onay kutusuyla uygulamayı açmadan tamamlayın.")
        .supportedFamilies([.systemMedium])
    }
}

/// Ana ekran, büyük: bugün + 6 gün, bekleyen teklifler, aktarılmamış ziyaretler, "+ Ziyaret".
struct WeekWidget: Widget {
    let kind = "WeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            WeekWidgetView(snapshot: entry.snapshot)
                .containerBackground(Theme.background, for: .widget)
        }
        .configurationDisplayName("Haftalık görünüm")
        .description("Bu haftanın takipleri, bekleyen teklifler ve CRM'e aktarılmamış ziyaretler.")
        .supportedFamilies([.systemLarge])
    }
}

/// Kilit ekranı, dikdörtgen: en yakın görev.
struct NextTaskWidget: Widget {
    let kind = "NextTaskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            NextTaskWidgetView(snapshot: entry.snapshot)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Sıradaki iş")
        .description("En yakın takibiniz.")
        .supportedFamilies([.accessoryRectangular])
    }
}

/// Kilit ekranı, yuvarlak: bugün + gecikmiş görev sayısı.
struct PendingCountWidget: Widget {
    let kind = "PendingCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TasksProvider()) { entry in
            PendingCountWidgetView(snapshot: entry.snapshot)
                .containerBackground(Color.clear, for: .widget)
        }
        .configurationDisplayName("Bekleyen iş sayısı")
        .description("Bugünkü ve gecikmiş takip sayısı.")
        .supportedFamilies([.accessoryCircular])
    }
}
