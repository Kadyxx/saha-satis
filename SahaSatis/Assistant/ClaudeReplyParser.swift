import Foundation

/// Claude'un cevabını "Konu / Özet / Sonraki adım / Takip tarihi" şablonuna göre ayrıştırır (saf mantık).
///
/// Şablondan önceki/sonraki fazladan metin, Markdown süsleri (**kalın**, başlık, madde işareti, kod bloğu) tolere
/// edilir. "Özet" yoksa şablon bozuk sayılır ve metnin tamamı not olarak döner.
enum ClaudeReplyParser {
    private enum Field {
        case topic, summary, nextStep, date
    }

    static let brokenTemplateWarning =
        "Cevap beklenen şablonda değil. Metnin tamamı görüşme notuna yazılacak; diğer alanlar değişmeyecek."

    static func parse(_ text: String, today: Date = Date(), calendar: Calendar = .current) -> NoteSuggestion {
        var values: [Field: [String]] = [:]
        var current: Field?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "__", with: "")
                .trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                current = nil
                continue
            }
            if case let (field, rest)? = label(in: line) {
                if values[field] == nil {
                    values[field] = rest.isEmpty ? [] : [rest]
                    current = field
                } else {
                    current = nil
                }
                continue
            }
            guard let field = current else { continue }
            let hasContent = !(values[field] ?? []).allSatisfy(\.isEmpty)
            switch field {
            case .summary:
                values[field, default: []].append(line)
            case .topic:
                if hasContent {
                    current = nil
                } else if !line.isEmpty {
                    values[field, default: []].append(line)
                    current = nil
                }
            case .date:
                // Boş tarihten sonraki kapanış cümlesi tarih sanılmasın: yalnızca rakam içeren satır alınır.
                if !hasContent, line.contains(where: \.isNumber) {
                    values[field, default: []].append(line)
                }
                current = nil
            case .nextStep:
                if line.isEmpty {
                    if hasContent { current = nil }
                } else {
                    values[field, default: []].append(line)
                }
            }
        }

        func value(_ field: Field) -> String {
            let joined = (values[field] ?? [])
                .joined(separator: "\n")
                .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return isPlaceholder(joined) ? "" : joined
        }

        let summary = value(.summary)
        guard !summary.isEmpty else {
            return NoteSuggestion(
                summary: text.trimmingCharacters(in: .whitespacesAndNewlines),
                followsTemplate: false,
                warnings: [brokenTemplateWarning]
            )
        }

        var suggestion = NoteSuggestion(
            topic: VisitText.singleLine(value(.topic)),
            summary: summary,
            nextStep: value(.nextStep)
        )
        let dateText = value(.date)
        if !dateText.isEmpty {
            suggestion.followUpDate = parseDate(dateText, today: today, calendar: calendar)
            if suggestion.followUpDate == nil {
                suggestion.warnings.append("Takip tarihi anlaşılamadı: \"\(dateText)\". Tarihi formdan elle seçin.")
            }
        }
        return suggestion
    }

    // MARK: - Etiketler

    private static func label(in line: String) -> (Field, String)? {
        var text = line
        while let first = text.first, "#>-*•".contains(first) {
            text.removeFirst()
            text = text.trimmingCharacters(in: .whitespaces)
        }
        if let numbering = text.range(of: "^\\d+[.)]\\s*", options: .regularExpression) {
            text.removeSubrange(numbering)
        }
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let field: Field
        switch DistrictCatalog.normalize(String(text[..<colon])) {
        case "konu": field = .topic
        case "ozet": field = .summary
        case "sonraki adim": field = .nextStep
        case "takip tarihi": field = .date
        default: return nil
        }
        let rest = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (field, rest)
    }

    /// "-", "Yok", "(yoksa boş)", "GG.AA.YYYY", "..." gibi boş sayılan değerler.
    private static func isPlaceholder(_ value: String) -> Bool {
        var key = DistrictCatalog.normalize(value)
        key = key.trimmingCharacters(in: CharacterSet(charactersIn: "()[] "))
        if key.count > 1, key.hasSuffix("."), !key.hasSuffix("..") { key.removeLast() }
        let empty: Set<String> = [
            "", "-", "—", "–", "...", "…", "yok", "bos", "yoksa bos", "belirtilmedi", "belirtilmemis",
            "gg.aa.yyyy", "gg.aa.yyyy (yoksa bos"
        ]
        return empty.contains(key)
    }

    // MARK: - Tarih

    private static let monthNames = [
        "ocak", "subat", "mart", "nisan", "mayis", "haziran",
        "temmuz", "agustos", "eylul", "ekim", "kasim", "aralik"
    ]

    /// "28.11.2026", "8/1/2027", "28-11-26", "2026-11-28", "28 Kasım 2026", "28 Kasım", "28.11" biçimleri.
    /// Yılsız tarih bugünden önceye düşerse gelecek yıl sayılır. Gün başı döner.
    static func parseDate(_ text: String, today: Date, calendar: Calendar) -> Date? {
        let key = DistrictCatalog.normalize(text)

        if let found = groups("\\b(\\d{4})-(\\d{1,2})-(\\d{1,2})\\b", in: key) {
            return makeDate(day: Int(found[2]), month: Int(found[1]), year: Int(found[0]), calendar: calendar)
        }
        if let found = groups("\\b(\\d{1,2})\\s*[./-]\\s*(\\d{1,2})\\s*[./-]\\s*(\\d{4}|\\d{2})\\b", in: key) {
            var year = Int(found[2])
            if found[2].count == 2 { year = year.map { $0 + 2000 } }
            return makeDate(day: Int(found[0]), month: Int(found[1]), year: year, calendar: calendar)
        }
        if let found = groups("\\b(\\d{1,2})\\s+([a-z]+)(?:\\s+(\\d{4}))?", in: key),
           let index = monthNames.firstIndex(of: found[1]) {
            if let year = Int(found[2]) {
                return makeDate(day: Int(found[0]), month: index + 1, year: year, calendar: calendar)
            }
            return upcoming(day: Int(found[0]), month: index + 1, today: today, calendar: calendar)
        }
        if let found = groups("^(\\d{1,2})[./](\\d{1,2})(?!\\d|[./]\\d)", in: key) {
            return upcoming(day: Int(found[0]), month: Int(found[1]), today: today, calendar: calendar)
        }
        return nil
    }

    private static func upcoming(day: Int?, month: Int?, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        if let date = makeDate(day: day, month: month, year: year, calendar: calendar),
           date >= calendar.startOfDay(for: today) {
            return date
        }
        return makeDate(day: day, month: month, year: year + 1, calendar: calendar)
    }

    /// Geçersiz tarih (31.02 gibi) nil döner.
    private static func makeDate(day: Int?, month: Int?, year: Int?, calendar: Calendar) -> Date? {
        guard let day, let month, let year,
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let check = calendar.dateComponents([.day, .month, .year], from: date)
        guard check.day == day, check.month == month, check.year == year else { return nil }
        return calendar.startOfDay(for: date)
    }

    /// İlk eşleşmenin yakalama grupları (eşleşmeyen grup boş metin).
    private static func groups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }
}
