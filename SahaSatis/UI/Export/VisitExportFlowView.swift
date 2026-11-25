import MessageUI
import Observation
import SwiftUI

enum ExportRoute: Hashable {
    case preview
}

/// "Ziyaretleri CRM için gönder" akışı: seçim → önizleme → gönderim. Bugün ekranından sheet olarak açılır.
struct VisitExportFlowView: View {
    let context: AppContext
    var onFinished: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var model: VisitExportModel
    @State private var path: [ExportRoute]

    init(context: AppContext, startAtPreview: Bool = false, onFinished: @escaping () -> Void = {}) {
        self.context = context
        self.onFinished = onFinished
        let model = VisitExportModel(repositories: context.repositories)
        model.reload(resetSelection: true)
        _model = State(initialValue: model)
        _path = State(initialValue: startAtPreview ? [.preview] : [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            VisitExportSelectionView(model: model) { path.append(.preview) }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Kapat") { dismiss() }
                    }
                }
                .navigationDestination(for: ExportRoute.self) { _ in
                    VisitExportPreviewView(
                        model: model,
                        recipients: VisitExportModel.recipients(from: context.settings.crmEmail)
                    ) {
                        onFinished()
                        dismiss()
                    }
                }
        }
        .tint(Theme.brandText)
    }
}

// MARK: - Seçim

struct VisitExportSelectionView: View {
    @Bindable var model: VisitExportModel
    let onNext: () -> Void

    var body: some View {
        List {
            Section {
                DatePicker("Gün", selection: $model.day, in: ...Date(), displayedComponents: .date)
                Toggle("Aktarılmış ziyaretleri de göster", isOn: $model.showExported)
            } footer: {
                Text("Daha önce aktarılmış bir ziyareti seçip yeniden gönderebilirsiniz.")
            }
            .listRowBackground(Theme.surface)

            Section {
                if model.visits.isEmpty {
                    Text(model.showExported ? "Bu günde ziyaret yok" : "Bu günde CRM'e aktarılmamış ziyaret yok")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(model.visits) { visit in
                        row(visit)
                    }
                }
            } header: {
                Text("Ziyaretler (\(model.selectedIDs.count)/\(model.visits.count) seçili)")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("CRM için gönder")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: model.day) { model.reload(resetSelection: true) }
        .onChange(of: model.showExported) { model.reload(resetSelection: false) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(model.allSelected ? "Seçimi kaldır" : "Tümünü seç") {
                    model.allSelected ? model.deselectAll() : model.selectAll()
                }
                .disabled(model.visits.isEmpty)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onNext) {
                Text(model.selectedIDs.isEmpty ? "Ziyaret seçin" : "Önizleme (\(model.selectedIDs.count))")
                    .font(.headline)
                    .foregroundStyle(Theme.onAction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.action.opacity(model.selectedIDs.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(model.selectedIDs.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .alert("Hata", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func row(_ visit: Visit) -> some View {
        Button {
            model.toggle(visit)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: model.isSelected(visit) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(model.isSelected(visit) ? Theme.brandText : Theme.textSecondary)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(visit.customer?.name ?? "Müşteri yok")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        if visit.exportedToCRM { TagLabel(text: "Aktarıldı") }
                    }
                    Text("\(visit.type.title) · \(AppFormat.time(visit.date))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    if !visit.summary.isEmpty {
                        Text(visit.summary)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.isSelected(visit) ? .isSelected : [])
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }
}

// MARK: - Önizleme

struct VisitExportPreviewView: View {
    let model: VisitExportModel
    let recipients: [String]
    let onFinished: () -> Void

    @State private var copiedBlock: Int?
    @State private var copiedAll = false
    @State private var showMail = false
    @State private var showShare = false
    @State private var confirmMark = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                infoCard
                if model.blocks.isEmpty {
                    Text("Gönderilecek ziyaret seçilmedi.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(model.blocks.enumerated()), id: \.offset) { index, block in
                    blockCard(index: index, text: block)
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Önizleme")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { actions }
        .sheet(isPresented: $showMail) {
            MailComposeView(subject: model.subject, body: model.reportText, recipients: recipients) { result in
                showMail = false
                // Yalnızca gerçekten gönderildiyse (veya giden kutusuna alındıysa) aktarıldı sayılır; taslak/iptal sayılmaz.
                if result == .sent, model.markSelectedExported() {
                    onFinished()
                }
            }
        }
        .sheet(isPresented: $showShare) {
            ShareSheet(text: model.reportText, subject: model.subject)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(
            "\(model.selectedIDs.count) ziyaret CRM'e aktarıldı olarak işaretlensin mi?",
            isPresented: $confirmMark,
            titleVisibility: .visible
        ) {
            Button("Aktarıldı olarak işaretle") {
                if model.markSelectedExported() { onFinished() }
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Alıcı", value: recipients.first ?? "—")
            LabeledContent("Konu", value: model.subject)
            if recipients.isEmpty {
                Label("CRM e-posta adresi Ayarlar'da boş; alıcıyı mail uygulamasında seçebilirsiniz.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.textPrimary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func blockCard(index: Int, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.selectedVisits.indices.contains(index) ? (model.selectedVisits[index].customer?.name ?? "") : "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Button(copiedBlock == index ? "Kopyalandı" : "Kopyala") {
                    copy(text)
                    copiedBlock = index
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        if copiedBlock == index { copiedBlock = nil }
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
            }
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button(action: send) {
                Label("Gönder", systemImage: "paperplane.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.onAction)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.action.opacity(model.blocks.isEmpty ? 0.4 : 1), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                Button(copiedAll ? "Kopyalandı" : "Tümünü kopyala") {
                    copy(model.reportText)
                    copiedAll = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedAll = false
                    }
                }
                .frame(maxWidth: .infinity)
                Button("Aktarıldı olarak işaretle") { confirmMark = true }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
        .disabled(model.blocks.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.background)
    }

    /// Mail hesabı varsa mail yazma ekranı, yoksa sistem paylaşım menüsü.
    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showMail = true
        } else {
            showShare = true
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
