import SwiftUI
import WidgetKit

struct HelloEntry: TimelineEntry {
    let date: Date
}

struct HelloProvider: TimelineProvider {
    func placeholder(in context: Context) -> HelloEntry {
        HelloEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (HelloEntry) -> Void) {
        completion(HelloEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelloEntry>) -> Void) {
        completion(Timeline(entries: [HelloEntry(date: Date())], policy: .never))
    }
}

struct HelloWidget: Widget {
    let kind = "HelloWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelloProvider()) { entry in
            HelloWidgetView(date: entry.date)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Merhaba")
        .description("Saha Satış altyapı denemesi.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
