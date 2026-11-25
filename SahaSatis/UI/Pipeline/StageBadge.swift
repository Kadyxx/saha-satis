import SwiftUI

/// Fırsat aşaması rozeti. Yazı renkleri palet kuralına uyar: turkuaz yazı `brandText`, kayıp `overdue`.
struct StageBadge: View {
    let stage: OpportunityStage

    var body: some View {
        Label {
            Text(stage.title)
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(stage == .lost ? Theme.overdue : Theme.brandText)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((stage == .lost ? Theme.overdue : Theme.brand).opacity(0.16), in: Capsule())
    }

    private var symbol: String? {
        switch stage {
        case .won: return "checkmark.circle.fill"
        case .lost: return "xmark.circle.fill"
        default: return nil
        }
    }
}

/// Fırsatlar listesindeki ve müşteri detayındaki fırsat satırı: başlık, tutar, müşteri ve beklenen kapanış tarihi.
struct OpportunityRow: View {
    let opportunity: Opportunity
    var showCustomer = true
    var showStage = false
    var now = Date()
    var calendar: Calendar = .current

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(opportunity.title.isEmpty ? "Başlıksız fırsat" : opportunity.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if opportunity.estimatedValue > 0 {
                    Text(AppFormat.money(opportunity.estimatedValue, currency: opportunity.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            HStack(spacing: 8) {
                if showStage { StageBadge(stage: opportunity.stage) }
                if showCustomer, let name = opportunity.customer?.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let close = opportunity.expectedCloseDate {
                    Label(AppFormat.date(close), systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(isCloseDateOverdue(close) ? Theme.overdue : Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Açık bir fırsatın beklenen kapanış günü geçtiyse kırmızı.
    private func isCloseDateOverdue(_ close: Date) -> Bool {
        opportunity.stage.isOpen && close < calendar.startOfDay(for: now)
    }
}
