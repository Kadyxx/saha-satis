import Foundation

/// CSV ayrıştırma: Türkçe Excel dosyaları (ayraç `;` veya `,`, kodlama UTF-8 veya Windows-1254).
enum CSVParser {
    /// Dosya baytlarını metne çevirir. Önce UTF-8 (BOM atılır); olmazsa Windows-1254 (Türkçe Excel'in "CSV" çıktısı).
    static func decode(_ data: Data) -> String? {
        var bytes = data
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        if let utf8 = String(data: bytes, encoding: .utf8) { return utf8 }
        return String(data: bytes, encoding: .windowsCP1254)
    }

    /// İlk satırdaki (tırnak dışı) `;`, `,` ve sekme sayısına bakarak ayracı seçer; eşitlikte `;` (Türkçe Excel varsayılanı).
    static func detectDelimiter(_ text: String) -> Character {
        var counts: [Character: Int] = [";": 0, ",": 0, "\t": 0]
        var inQuotes = false
        for char in text {
            if char == "\"" { inQuotes.toggle() }
            if !inQuotes {
                if char.isNewline { break }
                if counts[char] != nil { counts[char]! += 1 }
            }
        }
        var best: Character = ";"
        for candidate in [";", ",", "\t"] as [Character] where (counts[candidate] ?? 0) > (counts[best] ?? 0) {
            best = candidate
        }
        return best
    }

    /// RFC 4180'e uygun ayrıştırma: tırnaklı alanlar, çift tırnak kaçışı (`""`), alan içinde ayraç/satır sonu.
    /// Tamamen boş satırlar atlanır.
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
            row = []
        }

        while let char = pending {
            pending = iterator.next()
            if inQuotes {
                if char == "\"" {
                    if pending == "\"" { field.append("\""); pending = iterator.next() } else { inQuotes = false }
                } else {
                    field.append(char)
                }
                continue
            }
            switch char {
            case "\"" where field.isEmpty: inQuotes = true
            case delimiter: endField()
            case "\r\n", "\n", "\r": endRow()
            default: field.append(char)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
