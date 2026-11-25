import Foundation
import Observation

/// Gün sonu dışa aktarma durumu (SPEC → Gün sonu dışa aktarma): seçilen günün ziyaretleri, işaretleme,
/// rapor metni ve "aktarıldı" işaretleme. Veriye yalnızca repository'ler üzerinden erişir.
@MainActor
@Observable
final class VisitExportModel {
    private let repositories: Repositories
    private let calendar: Calendar

    /// Seçilen gün (varsayılan bugün).
    var day: Date
    /// Daha önce aktarılmış ziyaretleri de listele (yeniden göndermek için).
    var showExported = false
    /// Listedeki ziyaretler, eskiden yeniye.
    private(set) var visits: [Visit] = []
    private(set) var selectedIDs: Set<UUID> = []
    var errorMessage: String?

    init(repositories: Repositories, day: Date = Date(), calendar: Calendar = .current) {
        self.repositories = repositories
        self.day = day
        self.calendar = calendar
    }

    // MARK: - Liste ve seçim

    /// Günü değiştirince aktarılmamış ziyaretler baştan seçilir; aynı gün için (ör. "aktarılmışları göster")
    /// mevcut seçim korunur, listeden çıkanlar seçimden düşer.
    func reload(resetSelection: Bool) {
        do {
            let all = try repositories.visits.visits(on: day, calendar: calendar).sorted { $0.date < $1.date }
            visits = showExported ? all : all.filter { !$0.exportedToCRM }
            if resetSelection {
                selectedIDs = Set(visits.filter { !$0.exportedToCRM }.map(\.id))
            } else {
                selectedIDs.formIntersection(visits.map(\.id))
            }
        } catch {
            errorMessage = "Ziyaretler yüklenemedi: \(error.localizedDescription)"
        }
    }

    func isSelected(_ visit: Visit) -> Bool { selectedIDs.contains(visit.id) }

    func toggle(_ visit: Visit) {
        if selectedIDs.contains(visit.id) {
            selectedIDs.remove(visit.id)
        } else {
            selectedIDs.insert(visit.id)
        }
    }

    func selectAll() { selectedIDs = Set(visits.map(\.id)) }
    func deselectAll() { selectedIDs = [] }

    var allSelected: Bool { !visits.isEmpty && selectedIDs.count == visits.count }

    /// Seçili ziyaretler, eskiden yeniye (raporun sırası).
    var selectedVisits: [Visit] { visits.filter { selectedIDs.contains($0.id) } }

    // MARK: - Rapor

    var items: [VisitExportItem] { selectedVisits.map { VisitExportItem(visit: $0) } }
    var blocks: [String] { VisitReportFormatter.blocks(items, calendar: calendar) }
    var reportText: String { VisitReportFormatter.report(items, calendar: calendar) }
    var subject: String { VisitReportFormatter.subject(day: day, calendar: calendar) }

    /// Ayarlar'daki CRM adresi → alıcı listesi (boşsa alıcı yok; kullanıcı mail uygulamasında seçer).
    static func recipients(from crmEmail: String) -> [String] {
        let trimmed = crmEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    // MARK: - Aktarıldı işaretleme

    /// Seçili ziyaretleri `exportedToCRM = true`, `exportedAt = now` yapar. Daha önce aktarılmış olanların
    /// `exportedAt` değeri yeniden gönderim zamanıyla güncellenir. Bugün ekranı, gün sonu hatırlatması ve
    /// widget'lar kayıt bildirimiyle kendiliğinden yenilenir.
    @discardableResult
    func markSelectedExported(now: Date = Date()) -> Bool {
        do {
            try repositories.visits.markExported(selectedVisits, at: now)
            reload(resetSelection: false)
            return true
        } catch {
            errorMessage = "Aktarıldı olarak işaretlenemedi: \(error.localizedDescription)"
            return false
        }
    }
}
