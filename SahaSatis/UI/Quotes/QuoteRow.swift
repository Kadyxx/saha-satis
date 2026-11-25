import SwiftUI

/// Teklif durumu rozeti. Yazı renkleri palet kuralına uyar: turkuaz yazı `brandText`, kayıp `overdue`, taslak `textSecondary`.
struct QuoteStatusBadge: View {
    let status: QuoteStatus

    var body: some View {
        Label {
            Text(status.title)
        } icon: {
            if let symbol { Image(systemName: symbol) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
    }

    private var color: Color {
        switch status {
        case .lost: return Theme.overdue
        case .draft: return Theme.textSecondary
        default: return Theme.brandText
        }
    }

    private var symbol: String? {
        switch status {
        case .won: return "checkmark.circle.fill"
        case .lost: return "xmark.circle.fill"
        default: return nil
        }
    }
}

/// Teklif satırı: numara, toplam, müşteri, durum ve geçerlilik. Geçerliliği yaklaşan/dolan teklifler vurgulanır
/// (kalın metin + uyarı simgesi; liste ayrıca arka planı boyar).
struct QuoteRow: View {
    let quote: Quote
    var expiry: QuoteExpiryState = .none
    var showCustomer = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(quote.quoteNumber.isEmpty ? "Teklif" : quote.quoteNumber)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(AppFormat.moneyExact(quote.totalAmount, currency: quote.currency))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 8) {
                if showCustomer, let name = quote.customer?.name {
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                QuoteStatusBadge(status: quote.status)
            }
            let text = QuoteListing.expiryText(for: expiry, validUntil: quote.validUntil)
            if !text.isEmpty {
                switch expiry {
                case .none:
                    Label(text, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                case .approaching:
                    Label(text, systemImage: "clock.badge.exclamationmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                case .expired:
                    Label(text, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.overdue)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
