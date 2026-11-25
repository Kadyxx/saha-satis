import AppIntents
import SwiftUI
import WidgetKit

// Widget görünümleri. Hem widget uzantısında hem uygulama/test hedefinde derlenir; testler bu görünümleri
// örnek veriyle PNG'ye çevirip CI artifact'ine koyar. Arka plan (`containerBackground`) widget tanımında verilir.

/// Onay kutusu: uygulamayı açmadan görevi tamamlar (`CompleteTaskIntent`).
struct WidgetCheckbox: View {
    let taskID: UUID
    let isOverdue: Bool

    var body: some View {
        Button(intent: CompleteTaskIntent(taskID: taskID)) {
            Image(systemName: "circle")
                .font(.body)
                .foregroundStyle(isOverdue ? Theme.overdue : Theme.brandText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tamamla")
    }
}

/// Tek satır: onay kutusu + (dokununca o görevi açan) "başlık · müşteri" + sağda saat.
struct WidgetTaskRow: View {
    let task: WidgetTask
    let isOverdue: Bool
    let trailing: String

    var body: some View {
        HStack(spacing: 8) {
            WidgetCheckbox(taskID: task.id, isOverdue: isOverdue)
            Link(destination: WidgetLink.task(task.id).url) {
                HStack(spacing: 4) {
                    titleText
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(trailing)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isOverdue ? Theme.overdue : Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var titleText: Text {
        let title = Text(task.title).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
        guard let name = task.customerName else { return title }
        return title + Text(" · \(name)").foregroundStyle(Theme.textSecondary)
    }
}

// MARK: - Bugünün takipleri (systemMedium)

struct TodayTasksWidgetView: View {
    let snapshot: WidgetSnapshot
    var calendar: Calendar = .current
    static let maxRows = 4

    private struct Row: Identifiable {
        let task: WidgetTask
        let isOverdue: Bool
        var id: UUID { task.id }
    }

    /// Önce gecikmişler, sonra bugünküler.
    private var rows: [Row] {
        snapshot.overdue.map { Row(task: $0, isOverdue: true) } + snapshot.today.map { Row(task: $0, isOverdue: false) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Bugün")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.brandText)
                Spacer()
                if !snapshot.overdue.isEmpty {
                    Text("\(snapshot.overdue.count) gecikmiş")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.overdue)
                }
            }
            if snapshot.isEmptyToday {
                Spacer(minLength: 0)
                Text(WidgetFormat.emptyTodayText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(rows.prefix(Self.maxRows))) { row in
                    WidgetTaskRow(
                        task: row.task,
                        isOverdue: row.isOverdue,
                        trailing: row.isOverdue ? "Gecikmiş" : AppFormat.time(row.task.dueDate)
                    )
                }
                if rows.count > Self.maxRows {
                    Text("+\(rows.count - Self.maxRows) takip daha")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.today.url)
    }
}

// MARK: - Haftalık görünüm (systemLarge)

struct WeekWidgetView: View {
    let snapshot: WidgetSnapshot
    var calendar: Calendar = .current
    static let maxLines = 9

    private enum Line: Identifiable {
        case header(String, isOverdue: Bool)
        case task(WidgetTask, isOverdue: Bool, trailing: String)

        var id: String {
            switch self {
            case .header(let title, _): return "h-\(title)"
            case .task(let task, _, _): return "t-\(task.id.uuidString)"
            }
        }
    }

    /// Gecikmişler + bugün ve sonraki 6 günün görevleri, başlıklarıyla düz bir liste.
    private var allLines: [Line] {
        var lines: [Line] = []
        if !snapshot.overdue.isEmpty {
            lines.append(.header("Gecikmiş", isOverdue: true))
            lines += snapshot.overdue.map { Line.task($0, isOverdue: true, trailing: AppFormat.shortDay($0.dueDate)) }
        }
        for day in snapshot.week {
            lines.append(.header(WidgetFormat.dayTitle(day.day, now: snapshot.date, calendar: calendar), isOverdue: false))
            lines += day.tasks.map { Line.task($0, isOverdue: false, trailing: AppFormat.time($0.dueDate)) }
        }
        return lines
    }

    var body: some View {
        let lines = allLines
        let shown = Array(lines.prefix(Self.maxLines))
        let hiddenTasks = lines.dropFirst(Self.maxLines).filter {
            if case .task = $0 { return true }
            return false
        }.count

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Bu hafta")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.brandText)
                Spacer()
                Link(destination: WidgetLink.newVisit.url) {
                    Label("Ziyaret", systemImage: "plus")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.onAction)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.action, in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Label(
                    WidgetFormat.quoteSummary(count: snapshot.pendingQuoteCount, totals: snapshot.pendingQuoteTotals),
                    systemImage: "doc.text"
                )
                Label(WidgetFormat.unexportedText(snapshot.unexportedVisitCount), systemImage: "tray.and.arrow.up")
            }
            .font(.caption2)
            .foregroundStyle(Theme.textSecondary)
            .lineLimit(1)

            Divider()

            if lines.isEmpty {
                Spacer(minLength: 0)
                Text("Bu hafta için takip yok")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(shown) { line in
                    switch line {
                    case .header(let title, let isOverdue):
                        Text(title)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(isOverdue ? Theme.overdue : Theme.brandText)
                            .padding(.top, 2)
                    case .task(let task, let isOverdue, let trailing):
                        WidgetTaskRow(task: task, isOverdue: isOverdue, trailing: trailing)
                    }
                }
                if hiddenTasks > 0 {
                    Text("+\(hiddenTasks) takip daha")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(WidgetLink.today.url)
    }
}

// MARK: - Sıradaki iş (accessoryRectangular, kilit ekranı)

/// Kilit ekranı widget'ları sistem tarafından tek renge (vibrant) boyanır; palet renkleri yerine
/// sistem stilleri kullanılır.
struct NextTaskWidgetView: View {
    let snapshot: WidgetSnapshot
    var calendar: Calendar = .current

    var body: some View {
        Group {
            if let task = snapshot.next {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        if snapshot.nextIsOverdue {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .accessibilityLabel("Gecikmiş")
                        }
                        Text("Sıradaki iş")
                    }
                    .font(.caption2.weight(.semibold))
                    Text(headline(task))
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(WidgetFormat.dueText(for: task, now: snapshot.date, calendar: calendar))
                        .font(.caption2)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sıradaki iş")
                        .font(.caption2.weight(.semibold))
                    Text(WidgetFormat.emptyTodayText)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(snapshot.next.map { WidgetLink.task($0.id).url } ?? WidgetLink.today.url)
    }

    private func headline(_ task: WidgetTask) -> String {
        guard let name = task.customerName else { return task.title }
        return "\(name) – \(task.title)"
    }
}

// MARK: - Bekleyen iş sayısı (accessoryCircular, kilit ekranı)

struct PendingCountWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text("\(snapshot.pendingCount)")
                    .font(.title2.weight(.bold))
                Text("takip")
                    .font(.system(size: 10))
            }
        }
        .widgetURL(WidgetLink.today.url)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.isEmptyToday ? WidgetFormat.emptyTodayText : "\(snapshot.pendingCount) bekleyen takip")
    }
}
