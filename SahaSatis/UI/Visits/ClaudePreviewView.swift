import SwiftUI

/// Yapıştırılan cevabın önizlemesi (sheet hedefi).
struct SuggestionPreview: Identifiable {
    let id = UUID()
    let suggestion: NoteSuggestion
}

/// Claude cevabı forma yazılmadan önce gösterilir; "Forma uygula" ile onaylanır.
struct ClaudePreviewView: View {
    let suggestion: NoteSuggestion
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if !suggestion.warnings.isEmpty {
                    Section {
                        ForEach(suggestion.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.callout)
                                .foregroundStyle(Theme.overdue)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
                if suggestion.followsTemplate {
                    row("Konu", suggestion.topic)
                }
                row("Görüşme notu", suggestion.summary)
                if suggestion.followsTemplate {
                    row("Sonraki adım", suggestion.nextStep)
                    row("Takip tarihi", suggestion.followUpDate.map { AppFormat.date($0) } ?? "")
                }
                Section {
                } footer: {
                    Text("Görüşme notu değiştirilir; ham notunuz ayrıca saklanır. Boş gelen alanlar formdaki haliyle kalır.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Önizleme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Forma uygula") {
                        onApply()
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.brandText)
    }

    private func row(_ title: String, _ value: String) -> some View {
        Section(title) {
            if value.isEmpty {
                Text("Boş — değişmeyecek")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(value)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .listRowBackground(Theme.surface)
    }
}
