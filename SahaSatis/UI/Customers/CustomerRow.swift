import SwiftUI

extension Customer {
    /// "Bursa / Nilüfer" gibi; boş parçalar atlanır.
    var locationText: String {
        [city, district].filter { !$0.isEmpty }.joined(separator: " / ")
    }
}

struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(customer.name)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                RatingBadge(rating: customer.rating)
            }
            if !customer.locationText.isEmpty {
                Text(customer.locationText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                Text(customer.status.title)
                if let last = customer.lastVisitDate {
                    Text("·")
                    Text("Son ziyaret: \(AppFormat.date(last))")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }
}
