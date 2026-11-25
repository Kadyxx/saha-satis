import Foundation

/// Uygulama genelinde Türkçe biçimlendirme (cihaz bölgesinden bağımsız; arayüz dili Türkçe).
enum AppFormat {
    static let locale = Locale(identifier: "tr_TR")

    /// "21 Kas 2026"
    static func date(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMy")
        return formatter.string(from: date)
    }

    /// "14:30"
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter.string(from: date)
    }

    /// "27 Kas Cum"
    static func shortDay(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
        return formatter.string(from: date)
    }

    /// "480.000 ₺" (kuruşsuz, Türkçe binlik ayracı)
    static func money(_ amount: Double, currency: Currency) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: amount)) ?? "\(Int(amount))"
        return "\(number) \(currency.symbol)"
    }

    /// "21 Kas 2026 14:30"
    static func dateTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMyHHmm")
        return formatter.string(from: date)
    }
}

enum AppInfo {
    /// "0.1.0 (1)"
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
