import SwiftUI

/// Kişi ekleme (`contact == nil`) ve düzenleme formu.
struct ContactFormView: View {
    let contact: Contact?
    let customer: Customer
    let repository: ContactRepository
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullName: String
    @State private var title: String
    @State private var phone: String
    @State private var email: String
    @State private var notes: String
    @State private var isPrimary: Bool
    @State private var errorMessage: String?

    init(contact: Contact?, customer: Customer, repository: ContactRepository, onSaved: @escaping () -> Void = {}) {
        self.contact = contact
        self.customer = customer
        self.repository = repository
        self.onSaved = onSaved
        _fullName = State(initialValue: contact?.fullName ?? "")
        _title = State(initialValue: contact?.title ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
        _isPrimary = State(initialValue: contact?.isPrimary ?? false)
    }

    private var trimmedName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FormTextField(title: "Ad soyad", text: $fullName)
                    FormTextField(title: "Unvan", text: $title)
                }
                .listRowBackground(Theme.surface)

                Section {
                    FormTextField(title: "Telefon", text: $phone, keyboard: .phonePad)
                    FormTextField(title: "E-posta", text: $email, keyboard: .emailAddress, autocapitalization: .never)
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Asıl kişi", isOn: $isPrimary)
                    FormMultilineField(title: "Notlar", text: $notes, lines: 2...5)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(contact == nil ? "Yeni kişi" : "Kişiyi düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .disabled(trimmedName.isEmpty)
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

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func save() {
        do {
            if let contact {
                contact.fullName = trimmedName
                contact.title = title
                contact.phone = phone
                contact.email = email
                contact.notes = notes
                try repository.update(contact)
                if isPrimary && !contact.isPrimary {
                    try repository.setPrimary(contact)
                }
            } else {
                let created = Contact(
                    fullName: trimmedName, title: title, phone: phone, email: email,
                    notes: notes, isPrimary: isPrimary
                )
                try repository.add(created, to: customer)
            }
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
