import Foundation

extension AppSettings {
    /// Planlayıcının okuduğu ayarlar.
    var reminderSnapshot: ReminderSettingsSnapshot {
        ReminderSettingsSnapshot(
            morningSummaryEnabled: morningSummaryEnabled,
            morningSummaryTime: morningSummaryTime,
            endOfDayEnabled: endOfDayReminderEnabled,
            endOfDayTime: endOfDayReminderTime,
            weekendNotifications: weekendNotificationsEnabled
        )
    }

    /// Ziyaret sıklığı eşikleri (değerlendirme başına gün) ve görev saati.
    var visitFrequencyRules: VisitFrequencyRules {
        VisitFrequencyRules(
            importantDays: visitFrequencyImportantDays,
            promisingDays: visitFrequencyPromisingDays,
            weakDays: visitFrequencyWeakDays,
            reminderTime: defaultReminderTime
        )
    }
}
