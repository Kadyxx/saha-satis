import SwiftUI
import UniformTypeIdentifiers

/// Seçilen CSV dosyasının ayrıştırılmış hâli (içe aktarma akışının girdisi).
struct ImportSession: Identifiable {
    let id = UUID()
    let fileName: String
    let rows: [[String]]
    let delimiter: Character

    /// Dosya baytlarından oturum; okunamayan/boş dosyada nil.
    static func make(fileName: String, data: Data) -> ImportSession? {
        guard let text = CSVParser.decode(data) else { return nil }
        let delimiter = CSVParser.detectDelimiter(text)
        let rows = CSVParser.parse(text, delimiter: delimiter)
        guard rows.count > 1 else { return nil }
        return ImportSession(fileName: fileName, rows: rows, delimiter: delimiter)
    }

    var headers: [String] { rows.first ?? [] }
    var delimiterName: String { delimiter == "\t" ? "sekme" : "\"\(delimiter)\"" }
}

private enum ImportRoute: Hashable { case preview }

@MainActor
@Observable
private final class ImportFlowModel {
    let session: ImportSession
    var mapping: [ImportField: Int]
    var rating: CustomerRating = .promising
    var policy: ConflictPolicy = .skip

    init(session: ImportSession) {
        self.session = session
        mapping = ColumnMapper.autoMap(headers: session.headers)
    }

    var canContinue: Bool { mapping[.name] != nil }

    func items(existing: [Customer], regionCities: [String]) -> [ImportItem] {
        let records = CustomerImporter.records(rows: session.rows, mapping: mapping)
        return CustomerImporter.plan(records: records, existing: existing, regionCities: regionCities)
    }
}

/// CSV içe aktarma: 1) sütun eşleme → 2) önizleme (sayılar, değerlendirme, çakışma politikası) → içe aktar.
struct CustomerImportView: View {
    let repositories: Repositories
    let regionCities: [String]
    let session: ImportSession
    let startAtPreview: Bool
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: ImportFlowModel
    @State private var path: NavigationPath
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    init(
        repositories: Repositories, regionCities: [String], session: ImportSession,
        startAtPreview: Bool = false, onFinished: @escaping () -> Void
    ) {
        self.repositories = repositories
        self.regionCities = regionCities
        self.session = session
        self.startAtPreview = startAtPreview
        self.onFinished = onFinished
        _model = State(initialValue: ImportFlowModel(session: session))
        _path = State(initialValue: startAtPreview ? NavigationPath([ImportRoute.preview]) : NavigationPath())
    }

    var body: some View {
        NavigationStack(path: $path) {
            mappingScreen
                .navigationDestination(for: ImportRoute.self) { _ in previewScreen }
        }
        .tint(Theme.brandText)
        .alert("İçe aktarma tamamlandı", isPresented: Binding(get: { resultMessage != nil }, set: { _ in })) {
            Button("Tamam") {
                resultMessage = nil
                onFinished()
                dismiss()
            }
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("Hata", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - 1) Sütun eşleme

    private var mappingScreen: some View {
        Form {
            Section {
                LabeledContent("Dosya", value: session.fileName)
                LabeledContent("Kayıt", value: "\(session.rows.count - 1) satır")
                LabeledContent("Ayraç", value: session.delimiterName)
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(ImportField.allCases) { field in
                    Picker(selection: binding(for: field)) {
                        Text("Eşleme").tag(Int?.none)
                        ForEach(Array(session.headers.enumerated()), id: \.offset) { index, header in
                            Text(header.isEmpty ? "Sütun \(index + 1)" : header).tag(Int?.some(index))
                        }
                    } label: {
                        Text(field == .name ? "\(field.title) *" : field.title)
                    }
                }
            } header: {
                Text("Sütun eşleme")
            } footer: {
                Text("Başlıklar benzerliğe göre otomatik eşlendi; gerekirse değiştirin. * zorunlu.")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Sütunları eşle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Önizle") { path.append(ImportRoute.preview) }
                    .disabled(!model.canContinue)
            }
        }
    }

    private func binding(for field: ImportField) -> Binding<Int?> {
        Binding(
            get: { model.mapping[field] },
            set: { model.mapping[field] = $0 }
        )
    }

    // MARK: - 2) Önizleme

    private var previewScreen: some View {
        let existing = (try? repositories.customers.fetchAll()) ?? []
        let items = model.items(existing: existing, regionCities: regionCities)
        let counts = CustomerImporter.counts(items)
        return Form {
            Section("Özet") {
                countRow("Eklenecek", counts.add, color: Theme.brandText)
                countRow("Mevcut müşteriyle çakışan", counts.conflict, color: Theme.textPrimary)
                countRow("Hatalı", counts.invalid, color: counts.invalid > 0 ? Theme.overdue : Theme.textSecondary)
            }
            .listRowBackground(Theme.surface)

            Section {
                Picker("Değerlendirme", selection: $model.rating) {
                    ForEach(CustomerRating.allCases, id: \.self) { rating in
                        Text(rating.title).tag(rating)
                    }
                }
            } header: {
                Text("Yeni müşteriler")
            } footer: {
                Text("Eklenenler \"Aday\" durumunda açılır.")
            }
            .listRowBackground(Theme.surface)

            if counts.conflict > 0 {
                Section {
                    Picker("Çakışanlar", selection: $model.policy) {
                        ForEach(ConflictPolicy.allCases) { policy in
                            Text(policy.title).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Çakışanlar")
                } footer: {
                    Text("Aynı firma adı + şehir. Güncelle: CSV'deki dolu alanlar mevcut kaydın üstüne yazılır.")
                }
                .listRowBackground(Theme.surface)
            }

            let invalid = items.filter { if case .invalid = $0.outcome { return true } else { return false } }
            if !invalid.isEmpty {
                Section("Hatalı satırlar") {
                    ForEach(invalid.prefix(8)) { item in
                        HStack {
                            Text("Satır \(item.record.line)")
                            Spacer()
                            if case .invalid(let reason) = item.outcome {
                                Text(reason).foregroundStyle(Theme.overdue)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button {
                    apply(items)
                } label: {
                    Text("İçe aktar").frame(maxWidth: .infinity).fontWeight(.semibold)
                }
                .disabled(counts.add == 0 && !(model.policy == .update && counts.conflict > 0))
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Önizleme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func countRow(_ title: String, _ count: Int, color: Color) -> some View {
        LabeledContent(title) {
            Text("\(count)").foregroundStyle(color).fontWeight(.semibold)
        }
    }

    private func apply(_ items: [ImportItem]) {
        do {
            let result = try CustomerImporter.apply(
                items, policy: model.policy, rating: model.rating,
                regionCities: regionCities, repositories: repositories
            )
            var parts = ["\(result.added) müşteri eklendi"]
            if result.updated > 0 { parts.append("\(result.updated) güncellendi") }
            if result.skipped > 0 { parts.append("\(result.skipped) atlandı") }
            resultMessage = parts.joined(separator: ", ") + "."
        } catch {
            errorMessage = "İçe aktarılamadı: \(error.localizedDescription)"
        }
    }
}
