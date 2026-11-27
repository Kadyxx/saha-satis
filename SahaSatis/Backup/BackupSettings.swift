import Foundation

/// Yedekteki ayarlar. Alanlar opsiyonel: yedekte olmayan ayar geri yüklemede değişmez.
/// Son yedek tarihi cihaza ait olduğu için yedeğe girmez.
struct BackupSettings: Codable, Equatable, Sendable {
    var fullName: String?
    var jobTitle: String?
    var responsibleCities: [String]?
    var reminderMinutes: Int?
    var morningSummaryEnabled: Bool?
    var morningSummaryMinutes: Int?
    var endOfDayEnabled: Bool?
    var endOfDayMinutes: Int?
    var weekendNotificationsEnabled: Bool?
    var visitFrequencyImportantDays: Int?
    var visitFrequencyPromisingDays: Int?
    var visitFrequencyWeakDays: Int?
    var quoteFollowUpDays: [Int]?
    var quoteExpiryWarningEnabled: Bool?
    var quoteExpiryWarningDays: Int?
    var opportunityCloseReminderEnabled: Bool?
    var opportunityCloseReminderDays: Int?
    var defaultCurrencyRaw: String?
    var crmEmail: String?
    var cityPlan: [String: [String]]?
    var productFamilies: [ProductFamily]?
    var claudeInstruction: String?
}

extension BackupSettings {
    init(_ settings: AppSettings) {
        fullName = settings.fullName
        jobTitle = settings.jobTitle
        responsibleCities = settings.responsibleCities
        reminderMinutes = settings.defaultReminderTime.minutesSinceMidnight
        morningSummaryEnabled = settings.morningSummaryEnabled
        morningSummaryMinutes = settings.morningSummaryTime.minutesSinceMidnight
        endOfDayEnabled = settings.endOfDayReminderEnabled
        endOfDayMinutes = settings.endOfDayReminderTime.minutesSinceMidnight
        weekendNotificationsEnabled = settings.weekendNotificationsEnabled
        visitFrequencyImportantDays = settings.visitFrequencyImportantDays
        visitFrequencyPromisingDays = settings.visitFrequencyPromisingDays
        visitFrequencyWeakDays = settings.visitFrequencyWeakDays
        quoteFollowUpDays = settings.quoteFollowUpDays
        quoteExpiryWarningEnabled = settings.quoteExpiryWarningEnabled
        quoteExpiryWarningDays = settings.quoteExpiryWarningDays
        opportunityCloseReminderEnabled = settings.opportunityCloseReminderEnabled
        opportunityCloseReminderDays = settings.opportunityCloseReminderDays
        defaultCurrencyRaw = settings.defaultCurrency.rawValue
        crmEmail = settings.crmEmail
        cityPlan = settings.cityPlan
        productFamilies = settings.productFamilies
        // Varsayılan talimat yazılmaz: ileride iyileşen varsayılan eski yedekle ezilmesin.
        claudeInstruction = settings.claudeInstruction == AppSettings.defaultClaudeInstruction
            ? nil : settings.claudeInstruction
    }

    func apply(to settings: AppSettings) {
        if let fullName { settings.fullName = fullName }
        if let jobTitle { settings.jobTitle = jobTitle }
        if let responsibleCities { settings.responsibleCities = responsibleCities }
        if let reminderMinutes { settings.defaultReminderTime = TimeOfDay(minutes: reminderMinutes) }
        if let morningSummaryEnabled { settings.morningSummaryEnabled = morningSummaryEnabled }
        if let morningSummaryMinutes { settings.morningSummaryTime = TimeOfDay(minutes: morningSummaryMinutes) }
        if let endOfDayEnabled { settings.endOfDayReminderEnabled = endOfDayEnabled }
        if let endOfDayMinutes { settings.endOfDayReminderTime = TimeOfDay(minutes: endOfDayMinutes) }
        if let weekendNotificationsEnabled { settings.weekendNotificationsEnabled = weekendNotificationsEnabled }
        if let visitFrequencyImportantDays { settings.visitFrequencyImportantDays = visitFrequencyImportantDays }
        if let visitFrequencyPromisingDays { settings.visitFrequencyPromisingDays = visitFrequencyPromisingDays }
        if let visitFrequencyWeakDays { settings.visitFrequencyWeakDays = visitFrequencyWeakDays }
        if let quoteFollowUpDays { settings.quoteFollowUpDays = quoteFollowUpDays }
        if let quoteExpiryWarningEnabled { settings.quoteExpiryWarningEnabled = quoteExpiryWarningEnabled }
        if let quoteExpiryWarningDays { settings.quoteExpiryWarningDays = quoteExpiryWarningDays }
        if let opportunityCloseReminderEnabled {
            settings.opportunityCloseReminderEnabled = opportunityCloseReminderEnabled
        }
        if let opportunityCloseReminderDays { settings.opportunityCloseReminderDays = opportunityCloseReminderDays }
        if let currency = defaultCurrencyRaw.flatMap(Currency.init(rawValue:)) { settings.defaultCurrency = currency }
        if let crmEmail { settings.crmEmail = crmEmail }
        if let cityPlan { settings.cityPlan = cityPlan }
        if let productFamilies { settings.productFamilies = productFamilies }
        settings.claudeInstruction = claudeInstruction ?? AppSettings.defaultClaudeInstruction
    }
}
