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

/// Tutar alanı: yazarken binlik ayracı ekler ("480000" → "480.000"), virgül ondalık ayracıdır.
/// Metin `AmountParser.parse` ile sayıya geri çevrilir (kaydederken ayraçlar atılır).
struct AmountTextField: View {
    @Binding var text: String
    let label: String
    var isValid = true

    var body: some View {
        TextField("0", text: $text)
            .multilineTextAlignment(.trailing)
            .keyboardType(.decimalPad)
            .foregroundStyle(isValid ? Theme.textPrimary : Theme.overdue)
            .accessibilityLabel(label)
            .onChange(of: text) { old, new in
                let formatted = AmountParser.formatTyping(new, previous: old)
                if formatted != new { text = formatted }
            }
    }
}

/// Tutarın altında küçük "KDV hariç" notu (teklif tutarları KDV'siz girilir ve gösterilir).
struct ExcludingVATAmount: View {
    let text: String
    var font: Font = .body
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
            Text("KDV hariç")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), KDV hariç")
    }
}
