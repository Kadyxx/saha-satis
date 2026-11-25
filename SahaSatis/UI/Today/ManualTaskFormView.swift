import SwiftUI

/// Yeni manuel takip formunun başlangıç değerleri (ekran görüntüsü senaryosu için doldurulabilir).
struct ManualTaskSeed: Identifiable {
    let id = UUID()
    var title = ""
    var customer: Customer?
}

/// Manuel takip ekleme (SPEC → Bugün: "Manuel takip ekleme butonu"): başlık, isteğe bağlı müşteri,
/// tarih ve saat (varsayılan: bir sonraki hatırlatma saati).
struct ManualTaskFormView: View {
    let context: AppContext
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var customer: Customer?
    @State private var dueDate: Date
    @State private var errorMessage: String?

    init(context: AppContext, seed: ManualTaskSeed, onSaved: @escaping () -> Void = {}) {
        self.context = context
        self.onSaved = onSaved
        _title = State(initialValue: seed.title)
        _customer = State(initialValue: seed.customer)
        _dueDate = State(initialValue: Self.initialDueDate(
            now: Date(),
            reminderTime: context.settings.defaultReminderTime,
            calendar: .current
        ))
    }

    /// Bugünün hatırlatma saati henüz gelmediyse o, geçtiyse yarının hatırlatma saati.
    static func initialDueDate(now: Date, reminderTime: TimeOfDay, calendar: Calendar) -> Date {
        let today = reminderTime.date(on: now, calendar: calendar)
        if today > now { return today }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return reminderTime.date(on: tomorrow, calendar: calendar)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormMultilineField(title: "Takip", text: $title, lines: 1...3)
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink {
                        CustomerPickerView(repository: context.repositories.customers, selection: $customer)
                    } label: {
                        LabeledContent("Müşteri", value: customer?.name ?? "Seçiniz (isteğe bağlı)")
                    }
                    if customer != nil {
                        Button("Müşteriyi kaldır", role: .destructive) { customer = nil }
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    DatePicker("Tarih ve saat", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                } footer: {
                    Text("Bildirim bu saatte gelir.")
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Yeni takip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .alert("Kaydedilemedi", isPresented: errorBinding) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Theme.brandText)
    }

    private func save() {
        let task = FollowUpTask(title: trimmedTitle, dueDate: dueDate, source: .manual)
        do {
            try context.repositories.tasks.add(task, customer: customer, quote: nil, visit: nil)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
