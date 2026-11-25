import SwiftUI

/// Tek satırlık alan: etiket her zaman solda görünür (alan dolu olsa da), değer sağa yaslıdır.
struct FormTextField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        LabeledContent(title) {
            TextField("", text: $text)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .accessibilityLabel(title)
        }
    }
}

/// Çok satırlık alan: etiket üstte küçük başlık olarak her zaman görünür.
struct FormMultilineField: View {
    let title: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 2...5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            TextField("", text: $text, axis: .vertical)
                .lineLimit(lines)
                .accessibilityLabel(title)
        }
    }
}
