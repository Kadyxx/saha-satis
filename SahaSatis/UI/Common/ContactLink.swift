import Foundation

/// Telefon / e-posta / WhatsApp bağlantıları. Numaralar Türkiye varsayımıyla uluslararası biçime çevrilir.
enum ContactLink {
    private static func parse(_ raw: String) -> (hasPlus: Bool, digits: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = String(trimmed.filter { $0.isASCII && $0.isNumber })
        return (trimmed.hasPrefix("+"), digits)
    }

    /// `tel:` bağlantısı.
    static func dialURL(_ raw: String) -> URL? {
        let parsed = parse(raw)
        guard !parsed.digits.isEmpty else { return nil }
        return URL(string: "tel:" + (parsed.hasPlus ? "+" : "") + parsed.digits)
    }

    /// WhatsApp için ülke kodlu, yalnızca rakamlardan oluşan numara (ör. 905551234567).
    static func internationalNumber(_ raw: String) -> String? {
        let parsed = parse(raw)
        let digits = parsed.digits
        guard !digits.isEmpty else { return nil }
        if parsed.hasPlus { return digits }
        if digits.hasPrefix("00") { return String(digits.dropFirst(2)) }
        if digits.hasPrefix("0") { return "90" + digits.dropFirst() }
        if digits.count == 10 { return "90" + digits }
        return digits
    }

    static func whatsAppURL(_ raw: String) -> URL? {
        guard let number = internationalNumber(raw) else { return nil }
        return URL(string: "https://wa.me/\(number)")
    }

    static func mailURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.contains(" ") else { return nil }
        return URL(string: "mailto:\(trimmed)")
    }
}
