import Foundation

struct CurrencyTotal: Equatable, Sendable {
    let currency: Currency
    let amount: Double
}

/// Fırsatlar listesinde bir aşamanın grubu: fırsatlar + para birimine göre ayrı toplam.
struct StageGroup: Identifiable {
    let stage: OpportunityStage
    let opportunities: [Opportunity]
    let totals: [CurrencyTotal]

    var id: OpportunityStage { stage }
    var count: Int { opportunities.count }
}

/// Fırsatları aşamalara göre gruplar (SPEC → Fırsat / Teklif → Pipeline görünümü).
enum PipelineGrouping {
    /// Aşama sırası: Yeni, Nitelikli, Teklif verildi, Pazarlık, Kazanıldı, Kaybedildi. Boş gruplar atlanır.
    /// Grup içinde beklenen kapanış tarihi yakın olan önce (tarihsizler sonda), eşitlikte başlığa göre.
    static func groups(from opportunities: [Opportunity]) -> [StageGroup] {
        OpportunityStage.allCases.compactMap { stage in
            let members = opportunities.filter { $0.stage == stage }.sorted(by: order)
            guard !members.isEmpty else { return nil }
            return StageGroup(stage: stage, opportunities: members, totals: totals(of: members))
        }
    }

    /// Para birimi başına tahmini tutar toplamı (sıra: TL, USD, EUR); tutarı 0 olanlar toplama girmez.
    static func totals(of opportunities: [Opportunity]) -> [CurrencyTotal] {
        Currency.allCases.compactMap { currency in
            let amount = opportunities.filter { $0.currency == currency }.reduce(0) { $0 + $1.estimatedValue }
            return amount > 0 ? CurrencyTotal(currency: currency, amount: amount) : nil
        }
    }

    /// "480.000 ₺ · 12.500 $"; toplam yoksa boş.
    static func summary(_ totals: [CurrencyTotal]) -> String {
        totals.map { AppFormat.money($0.amount, currency: $0.currency) }.joined(separator: " · ")
    }

    private static func order(_ lhs: Opportunity, _ rhs: Opportunity) -> Bool {
        switch (lhs.expectedCloseDate, rhs.expectedCloseDate) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs.title.compare(rhs.title, options: .caseInsensitive, locale: AppFormat.locale) == .orderedAscending
        }
    }
}

/// Tutar alanı ayrıştırma/biçimleme (Türkçe ve nokta ondalık girişlerini kabul eder).
enum AmountParser {
    /// "1.250,50" → 1250.5; "1250.5" → 1250.5; "1.250" → 1250; "12,5" → 12.5; boş/geçersiz → nil.
    /// Hem nokta hem virgül varsa sonuncusu ondalık ayracıdır. Yalnızca nokta varsa: birden çok nokta veya
    /// noktadan sonra tam 3 hane binlik ayracı sayılır (Türkçe "1.250"; "0.500" hariç), aksi halde ondalıktır.
    static func parse(_ text: String) -> Double? {
        let cleaned = text.filter { !$0.isWhitespace }
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "." || $0 == ",") }) else { return nil }

        let lastDot = cleaned.lastIndex(of: ".")
        let lastComma = cleaned.lastIndex(of: ",")
        let normalized: String
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            let decimalIsComma = comma > dot
            let thousands: Character = decimalIsComma ? "." : ","
            let decimal: Character = decimalIsComma ? "," : "."
            let withoutThousands = cleaned.filter { $0 != thousands }
            normalized = String(withoutThousands.map { $0 == decimal ? Character(".") : $0 })
        case (nil, _?):
            let commas = cleaned.filter { $0 == "," }.count
            normalized = commas > 1 ? cleaned.filter { $0 != "," } : cleaned.replacingOccurrences(of: ",", with: ".")
        case (let dot?, nil):
            let dots = cleaned.filter { $0 == "." }.count
            let digitsAfter = cleaned.distance(from: dot, to: cleaned.endIndex) - 1
            let looksLikeThousands = dots > 1 || (digitsAfter == 3 && !cleaned.hasPrefix("0."))
            normalized = looksLikeThousands ? cleaned.filter { $0 != "." } : cleaned
        default:
            normalized = cleaned
        }
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Düzenleme alanı için: binlik ayracı yok, ondalık virgül ("1250,5"); tam sayıda ondalık yok; 0 → boş.
    static func editingText(_ value: Double) -> String {
        guard value > 0 else { return "" }
        if value == value.rounded() { return String(Int(value)) }
        return String(value).replacingOccurrences(of: ".", with: ",")
    }
}
