import Combine
import Foundation

/// Gün içinde saat:dakika (ör. 09:00). Ayarlarda dakika cinsinden saklanır.
struct TimeOfDay: Equatable, Hashable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    init(minutes: Int) {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        self.init(hour: clamped / 60, minute: clamped % 60)
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    /// Verilen günün bu saatindeki `Date`.
    func date(on day: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}

/// "3, 7, 14" gibi virgüllü gün listesini ayrıştırır/biçimler (teklif takip günleri).
enum DayListFormat {
    /// Rakam olmayan her şey ayraçtır; 1–365 dışı ve tekrarlayan değerler atılır; artan sıralı döner.
    static func parse(_ text: String) -> [Int] {
        let numbers = text
            .split { !$0.isASCII || !$0.isNumber }
            .compactMap { Int($0) }
            .filter { (1...365).contains($0) }
        return Array(Set(numbers)).sorted()
    }

    static func format(_ days: [Int]) -> String {
        days.map(String.init).joined(separator: ", ")
    }
}

/// Kullanıcı ayarları. SPEC: UserDefaults, App Group altında (widget de okuyabilsin).
/// `ObservableObject`: Ayarlar ekranı ve ayara bağlı ekranlar değişiklikte yenilenir; her değişiklik
/// anında UserDefaults'a yazılır. Hiç ayarlanmamış değerler SPEC'teki varsayılanlardır.
final class AppSettings: ObservableObject {
    // MARK: Varsayılanlar (SPEC → Hatırlatma motoru ve ayarlar)

    /// İlk kullanıcının sorumlu bölgesi (SPEC → Amaç ve kapsam). Yeni kullanıcı kendi listesini ayarlar.
    static let defaultCities = [
        "Çanakkale", "Balıkesir", "Bursa", "Bilecik",
        "Yalova", "Eskişehir", "Kütahya", "Afyonkarahisar"
    ]
    static let defaultReminderTime = TimeOfDay(hour: 9)
    static let defaultMorningSummaryTime = TimeOfDay(hour: 8)
    static let defaultEndOfDayTime = TimeOfDay(hour: 18)
    static let defaultQuoteFollowUpDays = [3, 7]
    static let defaultQuoteExpiryWarningDays = 3

    private enum Key {
        static let fullName = "profile.fullName"
        static let jobTitle = "profile.jobTitle"
        static let responsibleCities = "responsibleCities"
        static let reminderTime = "reminders.defaultTimeMinutes"
        static let morningEnabled = "reminders.morningSummary.enabled"
        static let morningTime = "reminders.morningSummary.timeMinutes"
        static let endOfDayEnabled = "reminders.endOfDay.enabled"
        static let endOfDayTime = "reminders.endOfDay.timeMinutes"
        static let weekend = "reminders.weekendNotifications"
        static let freqImportant = "reminders.visitFrequencyDays.important"
        static let freqPromising = "reminders.visitFrequencyDays.promising"
        static let freqWeak = "reminders.visitFrequencyDays.weak"
        static let followUpDays = "reminders.quoteFollowUpDays"
        static let expiryEnabled = "reminders.quoteExpiry.enabled"
        static let expiryDays = "reminders.quoteExpiry.daysBefore"
        static let crmEmail = "export.crmEmail"
    }

    private let defaults: UserDefaults

    // MARK: Profil (giriş gelene kadar yerel kayıt)

    @Published var fullName: String { didSet { defaults.set(fullName, forKey: Key.fullName) } }
    @Published var jobTitle: String { didSet { defaults.set(jobTitle, forKey: Key.jobTitle) } }

    // MARK: Bölge

    /// Sıralı şehir listesi. Boş liste bilinçli bir seçimdir ve boş olarak saklanır;
    /// yalnızca hiç ayarlanmamışsa `defaultCities` kullanılır.
    @Published var responsibleCities: [String] { didSet { defaults.set(responsibleCities, forKey: Key.responsibleCities) } }

    // MARK: Hatırlatmalar

    @Published var defaultReminderTime: TimeOfDay {
        didSet { defaults.set(defaultReminderTime.minutesSinceMidnight, forKey: Key.reminderTime) }
    }
    @Published var morningSummaryEnabled: Bool { didSet { defaults.set(morningSummaryEnabled, forKey: Key.morningEnabled) } }
    @Published var morningSummaryTime: TimeOfDay {
        didSet { defaults.set(morningSummaryTime.minutesSinceMidnight, forKey: Key.morningTime) }
    }
    @Published var endOfDayReminderEnabled: Bool { didSet { defaults.set(endOfDayReminderEnabled, forKey: Key.endOfDayEnabled) } }
    @Published var endOfDayReminderTime: TimeOfDay {
        didSet { defaults.set(endOfDayReminderTime.minutesSinceMidnight, forKey: Key.endOfDayTime) }
    }
    @Published var weekendNotificationsEnabled: Bool { didSet { defaults.set(weekendNotificationsEnabled, forKey: Key.weekend) } }

    @Published var visitFrequencyImportantDays: Int { didSet { defaults.set(visitFrequencyImportantDays, forKey: Key.freqImportant) } }
    @Published var visitFrequencyPromisingDays: Int { didSet { defaults.set(visitFrequencyPromisingDays, forKey: Key.freqPromising) } }
    @Published var visitFrequencyWeakDays: Int { didSet { defaults.set(visitFrequencyWeakDays, forKey: Key.freqWeak) } }

    /// Teklif gönderiminden kaç gün sonra takip hatırlatılacağı (varsayılan 3 ve 7).
    @Published var quoteFollowUpDays: [Int] { didSet { defaults.set(quoteFollowUpDays, forKey: Key.followUpDays) } }
    @Published var quoteExpiryWarningEnabled: Bool { didSet { defaults.set(quoteExpiryWarningEnabled, forKey: Key.expiryEnabled) } }
    @Published var quoteExpiryWarningDays: Int { didSet { defaults.set(quoteExpiryWarningDays, forKey: Key.expiryDays) } }

    // MARK: Dışa aktarma

    @Published var crmEmail: String { didSet { defaults.set(crmEmail, forKey: Key.crmEmail) } }

    // MARK: Başlatma

    init(defaults: UserDefaults = AppSettings.sharedDefaults) {
        self.defaults = defaults

        func time(_ key: String, _ fallback: TimeOfDay) -> TimeOfDay {
            (defaults.object(forKey: key) as? Int).map { TimeOfDay(minutes: $0) } ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            (defaults.object(forKey: key) as? Bool) ?? fallback
        }
        func number(_ key: String, _ fallback: Int) -> Int {
            (defaults.object(forKey: key) as? Int) ?? fallback
        }

        fullName = defaults.string(forKey: Key.fullName) ?? ""
        jobTitle = defaults.string(forKey: Key.jobTitle) ?? ""
        responsibleCities = defaults.stringArray(forKey: Key.responsibleCities) ?? Self.defaultCities
        defaultReminderTime = time(Key.reminderTime, Self.defaultReminderTime)
        morningSummaryEnabled = flag(Key.morningEnabled, true)
        morningSummaryTime = time(Key.morningTime, Self.defaultMorningSummaryTime)
        endOfDayReminderEnabled = flag(Key.endOfDayEnabled, true)
        endOfDayReminderTime = time(Key.endOfDayTime, Self.defaultEndOfDayTime)
        // Varsayılan kapalı: sabah özeti "her iş günü" ve görevler iş günlerine kayar (SPEC); açmak kullanıcıya bırakıldı.
        weekendNotificationsEnabled = flag(Key.weekend, false)
        visitFrequencyImportantDays = number(Key.freqImportant, 30)
        visitFrequencyPromisingDays = number(Key.freqPromising, 60)
        visitFrequencyWeakDays = number(Key.freqWeak, 120)
        quoteFollowUpDays = (defaults.array(forKey: Key.followUpDays) as? [Int]) ?? Self.defaultQuoteFollowUpDays
        quoteExpiryWarningEnabled = flag(Key.expiryEnabled, true)
        quoteExpiryWarningDays = number(Key.expiryDays, Self.defaultQuoteExpiryWarningDays)
        crmEmail = defaults.string(forKey: Key.crmEmail) ?? ""
    }

    /// App Group paylaşımlı UserDefaults. Grup kimliği Info.plist'teki `AppGroupID` anahtarından gelir
    /// (project.yml → APP_GROUP_ID; uygulama ve widget'ta tanımlı); bulunamazsa standart UserDefaults.
    static var sharedDefaults: UserDefaults {
        if let groupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String,
           !groupID.isEmpty,
           let shared = UserDefaults(suiteName: groupID) {
            return shared
        }
        return .standard
    }
}
