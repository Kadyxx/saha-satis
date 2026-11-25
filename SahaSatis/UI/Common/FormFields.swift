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
/// SwiftUI `TextField` imleç konumunu okutmadığı için `UITextField` sarmalayıcıdır: biçimleme sırasında imleç
/// yazılan yerde kalır (ortadan yazma/silme sona atlamaz). İmleç hesabı `AmountParser.formatTyping(_:cursor:previous:)`'dedir.
struct AmountTextField: UIViewRepresentable {
    @Binding var text: String
    let label: String
    var isValid = true

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.adjustsFontForContentSizeCategory = true
        field.font = .preferredFont(forTextStyle: .body)
        field.placeholder = "0"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.accessibilityLabel = label
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.text = $text
        if field.text != text { field.text = text }
        field.accessibilityLabel = label
        field.textColor = UIColor(named: isValid ? "textPrimary" : "overdue")
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 120, height: uiView.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textField(_ field: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = field.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return true }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            let cursorUTF16 = range.location + (string as NSString).length
            let cursor = proposed.distance(
                from: proposed.startIndex,
                to: String.Index(utf16Offset: min(cursorUTF16, proposed.utf16.count), in: proposed)
            )

            let result = AmountParser.formatTyping(proposed, cursor: cursor, previous: current)
            field.text = result.text
            if let position = field.position(from: field.beginningOfDocument, offset: utf16Offset(result.cursor, in: result.text)) {
                field.selectedTextRange = field.textRange(from: position, to: position)
            }
            text.wrappedValue = result.text
            return false
        }

        private func utf16Offset(_ characterOffset: Int, in string: String) -> Int {
            let index = string.index(string.startIndex, offsetBy: min(characterOffset, string.count))
            return string.utf16.distance(from: string.utf16.startIndex, to: index)
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
