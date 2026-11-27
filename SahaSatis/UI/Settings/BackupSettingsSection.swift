import SwiftUI
import UniformTypeIdentifiers

/// Ayarlar → Yedekleme: "Yedekle" (Dosyalar / paylaşım menüsü) ve onaylı "Yedekten geri yükle".
struct BackupSettingsSection: View {
    @ObservedObject var settings: AppSettings

    @EnvironmentObject private var context: AppContext
    @State private var exportFile: ExportFile?
    @State private var showImporter = false
    @State private var pendingRestore: BackupFile?
    @State private var errorMessage: String?

    private struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
        let createdAt: Date
    }

    var body: some View {
        Section {
            LabeledContent("Son yedek", value: lastBackupText)
            Button { makeBackup() } label: {
                Label("Yedekle", systemImage: "square.and.arrow.up")
            }
            .sheet(item: $exportFile) { file in
                FileShareSheet(url: file.url) { completed in
                    // Yalnızca gerçekten tamamlanan paylaşım/kaydetme "son yedek" sayılır.
                    if completed { settings.lastBackupAt = file.createdAt }
                    // Dosya müşteri bilgisi içerir; geçici kopya bırakılmaz.
                    try? FileManager.default.removeItem(at: file.url)
                    exportFile = nil
                }
            }
            Button { showImporter = true } label: {
                Label("Yedekten geri yükle", systemImage: "arrow.counterclockwise")
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                read(result)
            }
            .alert("Yedekten geri yüklensin mi?", isPresented: restoreBinding, presenting: pendingRestore) { file in
                Button("Geri yükle", role: .destructive) {
                    Task { await context.restore(file) }
                }
                Button("Vazgeç", role: .cancel) {}
            } message: { file in
                Text(Self.confirmationText(file))
            }
        } header: {
            Text("Yedekleme")
        } footer: {
            Text("Tüm veriler ve ayarlar tek JSON dosyasına yazılır. \"Dosyalara Kaydet\" ile telefon dışında da erişebileceğiniz bir yere (ör. iCloud Drive) koyun. Dosya şifresizdir ve müşteri bilgisi içerir.")
        }
        .listRowBackground(Theme.surface)
        .alert("Yedekleme", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var lastBackupText: String {
        guard let date = settings.lastBackupAt else { return "Henüz alınmadı" }
        return "\(AppFormat.date(date)) \(AppFormat.time(date))"
    }

    static func confirmationText(_ file: BackupFile) -> String {
        let created = "\(AppFormat.date(file.createdAt)) \(AppFormat.time(file.createdAt))"
        return "\(created) tarihli yedek: \(file.data.customers.count) müşteri, \(file.data.visits.count) ziyaret, \(file.data.quotes.count) teklif.\n\nCihazdaki tüm veriler ve ayarlar silinip yedektekiler yazılacak. Bu işlem geri alınamaz."
    }

    private func makeBackup() {
        do {
            let now = Date()
            let data = try BackupCodec.encode(try context.makeBackup(now: now))
            let url = FileManager.default.temporaryDirectory.appending(path: BackupCodec.fileName(for: now))
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url, createdAt: now)
        } catch {
            errorMessage = "Yedek oluşturulamadı: \(error.localizedDescription)"
        }
    }

    private func read(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pendingRestore = try BackupCodec.decode(try Data(contentsOf: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}
