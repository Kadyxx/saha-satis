import Foundation

/// Bir ziyaretin CRM raporundaki alanları (SwiftData nesnesinden bağımsız değer; biçimlendirici bununla çalışır).
struct VisitExportItem: Equatable, Sendable {
    struct Person: Equatable, Sendable {
        var name: String
        var title: String = ""
    }

    var date: Date
    var customerName: String
    var city: String = ""
    var district: String = ""
    var contacts: [Person] = []
    var typeTitle: String
    /// "Konu": ziyaretin konuları, yoksa bağlı fırsatın başlığı.
    var topic: String = ""
    var note: String = ""
    var nextStep: String = ""
    var nextStepDate: Date?
}

/// Gün sonu CRM raporunun düz metni (SPEC → Gün sonu dışa aktarma). Her ziyaret ayrı blok, alanlar CRM'e tek tek
/// yapıştırılacak sırada:
///
///     === ZIYARET 1 ===
///     Tarih: 24.11.2026
///     Firma: Örnek Makina A.Ş.
///     Şehir / İlçe: Bursa / Nilüfer
///     Görüşülen: Ahmet Yılmaz (Bakım Müdürü), Ayşe Demir
///     Ziyaret tipi: Yüz yüze
///     Konu: Hat 3 PLC yenileme
///     Görüşme notu:
///     ...
///     Sonraki adım: Teklif hazırlanacak
///     Takip tarihi: 28.11.2026
///
/// Alan sırası ve satırlar sabittir; boş alan satırı atlanmaz, değeri "-" olur (CRM'e yapıştırma sırası şaşmasın).
/// Tek satırlık alanlarda satır sonları boşluğa çevrilir; yalnızca görüşme notu çok satırlı kalır.
enum VisitReportFormatter {
    static let emptyValue = "-"

    static func block(_ item: VisitExportItem, number: Int, calendar: Calendar = .current) -> String {
        let cityDistrict = [item.city, item.district]
            .map(singleLine)
            .filter { !$0.isEmpty }
            .joined(separator: " / ")
        let people = item.contacts.compactMap { person -> String? in
            let name = singleLine(person.name)
            guard !name.isEmpty else { return nil }
            let title = singleLine(person.title)
            return title.isEmpty ? name : "\(name) (\(title))"
        }.joined(separator: ", ")

        let lines = [
            "=== ZIYARET \(number) ===",
            "Tarih: \(AppFormat.numericDate(item.date, calendar: calendar))",
            "Firma: \(value(item.customerName))",
            "Şehir / İlçe: \(cityDistrict.isEmpty ? emptyValue : cityDistrict)",
            "Görüşülen: \(people.isEmpty ? emptyValue : people)",
            "Ziyaret tipi: \(value(item.typeTitle))",
            "Konu: \(value(item.topic))",
            "Görüşme notu:",
            multiLine(item.note),
            "Sonraki adım: \(value(item.nextStep))",
            "Takip tarihi: \(item.nextStepDate.map { AppFormat.numericDate($0, calendar: calendar) } ?? emptyValue)"
        ]
        return lines.joined(separator: "\n")
    }

    /// Seçili ziyaretlerin bloklarını sırayla numaralar; bloklar arasında bir boş satır.
    static func blocks(_ items: [VisitExportItem], calendar: Calendar = .current) -> [String] {
        items.enumerated().map { block($0.element, number: $0.offset + 1, calendar: calendar) }
    }

    static func report(_ items: [VisitExportItem], calendar: Calendar = .current) -> String {
        blocks(items, calendar: calendar).joined(separator: "\n\n")
    }

    /// "Ziyaret Raporu – 24.11.2026" (tire: en dash).
    static func subject(day: Date, calendar: Calendar = .current) -> String {
        "Ziyaret Raporu – \(AppFormat.numericDate(day, calendar: calendar))"
    }

    // MARK: - Yardımcılar

    /// Satır sonlarını ve art arda boşlukları tek boşluğa indirir, kenarları kırpar.
    static func singleLine(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    private static func value(_ text: String) -> String {
        let line = singleLine(text)
        return line.isEmpty ? emptyValue : line
    }

    /// Çok satırlı not: satır sonları korunur, her satırın sonundaki boşluk ve baştaki/sondaki boş satırlar atılır.
    private static func multiLine(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var s = String(line)
            while let last = s.last, last.isWhitespace { s.removeLast() }
            return s
        }
        var trimmed = lines
        while trimmed.first == "" { trimmed.removeFirst() }
        while trimmed.last == "" { trimmed.removeLast() }
        return trimmed.isEmpty ? emptyValue : trimmed.joined(separator: "\n")
    }
}

extension VisitExportItem {
    @MainActor
    init(visit: Visit) {
        let topics = visit.topics.map(VisitReportFormatter.singleLine).filter { !$0.isEmpty }
        let topic = topics.isEmpty ? (visit.opportunity?.title ?? "") : topics.joined(separator: ", ")
        self.init(
            date: visit.date,
            customerName: visit.customer?.name ?? "",
            city: visit.customer?.city ?? "",
            district: visit.customer?.district ?? "",
            contacts: (visit.contacts ?? [])
                .sorted { ($0.isPrimary ? 0 : 1, $0.fullName) < ($1.isPrimary ? 0 : 1, $1.fullName) }
                .map { Person(name: $0.fullName, title: $0.title) },
            typeTitle: visit.type.title,
            topic: topic,
            note: visit.summary,
            nextStep: visit.nextStep,
            nextStepDate: visit.nextStepDate
        )
    }
}
