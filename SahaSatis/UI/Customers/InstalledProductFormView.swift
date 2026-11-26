import SwiftUI

/// Kurulu baz ürünü ekle/düzenle: katalog no, ürün ailesi, adet, yaşam döngüsü, not.
/// Aile listeden seçilince yaşam döngüsü ailenin varsayılanından gelir; elle değiştirilebilir.
struct InstalledProductFormView: View {
    let customer: Customer
    let product: InstalledProduct?
    let families: [ProductFamily]
    let repository: InstalledProductRepository
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var draft: InstalledProductDraft
    @State private var errorMessage: String?
    /// Aile listede yoksa (veya "Diğer…" seçildiyse) serbest metin alanı gösterilir.
    @State private var customFamily: Bool

    private static let otherTag = "__other__"

    init(
        customer: Customer, product: InstalledProduct?, families: [ProductFamily],
        repository: InstalledProductRepository, onSaved: @escaping () -> Void = {}
    ) {
        self.customer = customer
        self.product = product
        self.families = families
        self.repository = repository
        self.onSaved = onSaved
        let initial = product.map(InstalledProductDraft.init(product:)) ?? InstalledProductDraft()
        _draft = State(initialValue: initial)
        _customFamily = State(initialValue: !initial.family.isEmpty && ProductFamily.find(initial.family, in: families) == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormTextField(title: "Katalog no", text: $draft.catalogNumber, autocapitalization: .characters)
                    familyPicker
                    if customFamily {
                        FormTextField(title: "Aile adı", text: $draft.family)
                    }
                    Stepper(value: $draft.quantity, in: 1...9999) {
                        LabeledContent("Adet", value: "\(draft.quantity)")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Yaşam döngüsü", selection: $draft.lifecycle) {
                        ForEach(LifecycleStatus.allCases, id: \.self) { status in
                            Text(status.title).tag(status)
                        }
                    }
                    if draft.lifecycle.isMigrationCandidate {
                        Label("Müşteri \"Migrasyon fırsatı\" olarak işaretlenir.", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote)
                            .foregroundStyle(Theme.brandText)
                    }
                    if let note = familyNote {
                        Text(note).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Yaşam döngüsü")
                } footer: {
                    Text("Aile seçilince durum ailenin varsayılanından gelir; gerekirse değiştirin.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    FormMultilineField(title: "Not", text: $draft.notes, lines: 2...6)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(product == nil ? "Ürün ekle" : "Ürünü düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(!draft.canSave)
                }
            }
            .alert("Kaydedilemedi", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Theme.brandText)
    }

    private var familyNote: String? {
        guard let found = ProductFamily.find(draft.family, in: families), !found.note.isEmpty else { return nil }
        return "\(found.name): \(found.note)"
    }

    private var familyPicker: some View {
        Picker("Ürün ailesi", selection: familySelection) {
            Text("Seçiniz").tag("")
            ForEach(families) { family in
                Text(family.name).tag(family.name)
            }
            Text("Diğer…").tag(Self.otherTag)
        }
    }

    private var familySelection: Binding<String> {
        Binding(
            get: {
                if customFamily { return Self.otherTag }
                return ProductFamily.find(draft.family, in: families)?.name ?? ""
            },
            set: { value in
                if value == Self.otherTag {
                    customFamily = true
                    if ProductFamily.find(draft.family, in: families) != nil { draft.family = "" }
                } else {
                    customFamily = false
                    draft.selectFamily(value, families: families)
                }
            }
        )
    }

    private func save() {
        do {
            if let product {
                draft.apply(to: product)
                try repository.update(product)
            } else {
                try repository.add(draft.makeProduct(), to: customer)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
