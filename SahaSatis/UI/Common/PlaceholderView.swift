import SwiftUI

/// Henüz yapılmamış sekmeler için boş ekran ve kısa açıklama.
struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(Theme.textPrimary)
            } description: {
                Text(message)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .visitButton()
            .navigationTitle(title)
        }
    }
}
