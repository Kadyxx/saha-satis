import SwiftUI

private struct FamilyEditTarget: Identifiable {
    let id = UUID()
    /// nil = yeni aile.
    let family: ProductFamily?
}

/// Ürün aileleri: aile adı + varsayılan yaşam döngüsü (+ not). Kurulu bazda aile seçilince durum buradan gelir.
struct ProductFamiliesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var target: FamilyEditTarget?

    var body: some View {
        List {
            Section {
                ForEach(settings.productFamilies) { family in
                    Button { target = FamilyEditTarget(family: family) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(family.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(family.lifecycle.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(family.lifecycle.isMigrationCandidate ? Theme.overdue : Theme.textSecondary)
                            }
                            if !family.note.isEmpty {
                                Text(family.note)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                }
                .onDelete { settings.productFamilies.remove(atOffsets: $0) }

                Button { target = FamilyEditTarget(family: nil) } label: {
                    Label("Aile ekle", systemImage: "plus")
                }
            } header: {
                Text("Ürün aileleri")
            } footer: {
                Text("Varsayılan yaşam döngüsü, kurulu bazda aile seçilince otomatik gelir (üründe elle değiştirilebilir). Ömrünü tamamlayan / üretimi duran aileler müşteriyi \"Migrasyon fırsatı\" olarak işaretler.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Örnek ailelere dön", role: .destructive) {
                    settings.productFamilies = ProductFamily.defaults
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Ürün aileleri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $target) { target in
            FamilyEditor(family: target.family) { saved in
                if let index = settings.productFamilies.firstIndex(where: { $0.id == saved.id }) {
                    settings.productFamilies[index] = saved
                } else {
                    settings.productFamilies.append(saved)
                }
            }
        }
    }
}

private struct FamilyEditor: View {
    let onSave: (ProductFamily) -> Void
    private let existingID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var lifecycle: LifecycleStatus
    @State private var note: String

    init(family: ProductFamily?, onSave: @escaping (ProductFamily) -> Void) {
        self.onSave = onSave
        existingID = family?.id
        _name = State(initialValue: family?.name ?? "")
        _lifecycle = State(initialValue: family?.lifecycle ?? .active)
        _note = State(initialValue: family?.note ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormTextField(title: "Aile adı", text: $name)
                    Picker("Varsayılan yaşam döngüsü", selection: $lifecycle) {
                        ForEach(LifecycleStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    FormMultilineField(title: "Not", text: $note, lines: 1...3)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(existingID == nil ? "Yeni aile" : "Aileyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var family = ProductFamily(name: trimmedName, lifecycle: lifecycle, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
                        if let existingID { family.id = existingID }
                        onSave(family)
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .tint(Theme.brandText)
    }
}
