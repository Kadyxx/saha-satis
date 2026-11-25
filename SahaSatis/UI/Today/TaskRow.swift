import SwiftUI

extension TaskSource {
    /// Satırın solundaki simge.
    var systemImage: String {
        switch self {
        case .manual: return "checklist"
        case .visitNextStep: return "arrow.turn.down.right"
        case .quoteFollowUp: return "doc.text"
        case .quoteExpiry: return "clock.badge.exclamationmark"
        case .visitFrequency: return "building.2"
        }
    }
}

/// Bugün ekranındaki takip satırı: simge, başlık, müşteri; sağda saat (bugün/yarın) veya gecikme (gecikmiş).
struct TaskRow: View {
    let task: FollowUpTask
    let isOverdue: Bool
    var now: Date = Date()
    var calendar: Calendar = .current

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: task.source.systemImage)
                .foregroundStyle(isOverdue ? Theme.overdue : Theme.brandText)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(Theme.textPrimary)
                if let name = task.customer?.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Text(trailingText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isOverdue ? Theme.overdue : Theme.textSecondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Gecikmiş: "2 gün gecikti"; diğerleri: "09:00".
    var trailingText: String {
        Self.trailingText(dueDate: task.dueDate, isOverdue: isOverdue, now: now, calendar: calendar)
    }

    static func trailingText(dueDate: Date, isOverdue: Bool, now: Date, calendar: Calendar) -> String {
        guard isOverdue else { return AppFormat.time(dueDate) }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: dueDate),
            to: calendar.startOfDay(for: now)
        ).day ?? 1
        return days <= 1 ? "Dün" : "\(days) gün gecikti"
    }
}
