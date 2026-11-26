import Foundation

/// Düzeltilmiş kartvizit alanlarından kayıt üretir. Modelde web adresi alanı olmadığı için web adresi notlara yazılır.
enum BusinessCardImport {
    /// "Yeni müşteri oluştur": müşteri formu bu taslakla açılır (durum Aday).
    static func customerDraft(from fields: BusinessCardFields) -> CustomerDraft {
        var draft = CustomerDraft()
        draft.name = trimmed(fields.company)
        draft.address = trimmed(fields.address)
        draft.city = fields.city
        draft.district = fields.district
        draft.status = .potential
        draft.notes = websiteNote(fields)
        return draft
    }

    /// Karttaki kişi; ad boşsa nil. `includeWebsite`: mevcut müşteriye eklerken web adresi kişi notuna yazılır
    /// (yeni müşteride müşteri notundadır).
    static func contact(from fields: BusinessCardFields, includeWebsite: Bool) -> Contact? {
        let name = trimmed(fields.fullName)
        guard !name.isEmpty else { return nil }
        var notes: [String] = []
        if !fields.otherPhones.isEmpty {
            notes.append("Diğer telefon: " + fields.otherPhones.joined(separator: ", "))
        }
        if includeWebsite {
            let web = websiteNote(fields)
            if !web.isEmpty { notes.append(web) }
        }
        return Contact(
            fullName: name,
            title: trimmed(fields.title),
            phone: trimmed(fields.phone),
            email: trimmed(fields.email),
            notes: notes.joined(separator: "\n")
        )
    }

    private static func websiteNote(_ fields: BusinessCardFields) -> String {
        let site = trimmed(fields.website)
        return site.isEmpty ? "" : "Web: \(site)"
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
