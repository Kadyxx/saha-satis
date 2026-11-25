import SwiftUI

/// Ertele → "Tarih seç…": yeni günü seçtirir; görevin saati korunur.
struct PostponeDateSheet: View {
    let task: FollowUpTask
    let onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    init(task: FollowUpTask, onPick: @escaping (Date) -> Void) {
        self.task = task
        self.onPick = onPick
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        _selection = State(initialValue: tomorrow)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                DatePicker(
                    "Yeni tarih",
                    selection: $selection,
                    in: Calendar.current.startOfDay(for: Date())...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                Spacer(minLength: 0)
            }
            .padding()
            .background(Theme.background)
            .navigationTitle("Ertele")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ertele") {
                        onPick(selection)
                        dismiss()
                    }
                }
            }
        }
        .tint(Theme.brandText)
        .presentationDetents([.large])
    }
}
