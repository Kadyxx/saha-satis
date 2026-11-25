import SwiftUI

/// Müşteri detayındaki "Ziyaret geçmişi" satırı: başlık (konu, boşsa notun ilk satırı), tarih, tip, not özeti ve sonraki adım.
struct VisitHistoryRow: View {
    let visit: Visit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if visit.displayTitle.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text(AppFormat.dateTime(visit.date))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    Text(visit.type.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text(visit.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(AppFormat.dateTime(visit.date))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Text(visit.type.title)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if !visit.noteBelowTitle.isEmpty {
                Text(visit.noteBelowTitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(3)
            }
            if !visit.nextStep.isEmpty || visit.nextStepDate != nil {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption)
                    Text(nextStepText)
                        .font(.caption)
                }
                .foregroundStyle(Theme.brandText)
            }
            if !(visit.contacts ?? []).isEmpty {
                Text((visit.contacts ?? []).map(\.fullName).sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var nextStepText: String {
        let step = visit.nextStep.isEmpty ? "Sonraki adım" : visit.nextStep
        if let day = visit.nextStepDate {
            return "\(step) · \(AppFormat.date(day))"
        }
        return step
    }
}
