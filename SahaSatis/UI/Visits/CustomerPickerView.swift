import SwiftUI

/// Ziyaret için müşteri seçimi: en son ziyaret edilenler üstte, arama destekli.
/// (SPEC "konuma en yakınlar üstte" der; konum izni/konum verisi henüz yok, bkz. docs/NOTES.md.)
struct CustomerPickerView: View {
    let repository: CustomerRepository
    @Binding var selection: Customer?

    @Environment(\.dismiss) private var dismiss
    @State private var model: CustomerListModel

    init(repository: CustomerRepository, selection: Binding<Customer?>) {
        self.repository = repository
        _selection = selection
        let model = CustomerListModel(repository: repository)
        model.filter.sort = .lastVisitNewestFirst
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            ForEach(model.customers) { customer in
                Button {
                    selection = customer
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(customer.name)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            if !customer.locationText.isEmpty {
                                Text(customer.locationText)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let last = customer.lastVisitDate {
                                Text("Son ziyaret: \(AppFormat.date(last))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        if selection?.id == customer.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.brandText)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Müşteri seç")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.filter.searchText, prompt: "Firma, şehir, sektör ara")
        .onAppear { model.reload() }
        .onChange(of: model.filter) { model.reload() }
        .overlay {
            if model.customers.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}
