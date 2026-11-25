import Foundation

/// Teklif hatırlatma ayarları (Ayarlar → Teklifler) ve görev saati.
struct QuoteReminderRules: Equatable, Sendable {
    /// Teklife özel gün listesi boşsa kullanılan varsayılan takip günleri.
    var defaultFollowUpDays = [3, 7]
    var expiryEnabled = true
    var expiryDaysBefore = 3
    var reminderTime = TimeOfDay(hour: 9)
}

extension AppSettings {
    var quoteReminderRules: QuoteReminderRules {
        QuoteReminderRules(
            defaultFollowUpDays: quoteFollowUpDays,
            expiryEnabled: quoteExpiryWarningEnabled,
            expiryDaysBefore: quoteExpiryWarningDays,
            reminderTime: defaultReminderTime
        )
    }
}

/// Teklif takip görevleri (`quoteFollowUp`) ve geçerlilik uyarısı (`quoteExpiry`) üretir
/// (SPEC → Hatırlatma motoru). Bildirimler görevlerden üretildiği için ayrıca bildirim kodu yoktur.
///
/// - Yalnızca **bekleyen** tekliflerde (Gönderildi, Takipte) görev vardır; Taslak, Kazanıldı, Kaybedildi olunca bekleyen
///   tüm görevler silinir.
/// - **Takip**: gönderim günü (`sentAt`) + gün listesi (teklife özelse o, boşsa ayarlardaki varsayılan), hatırlatma
///   saatinde. Geçmişte kalan günler için görev kurulmaz.
/// - **Geçerlilik uyarısı**: `validUntil` − X gün, hatırlatma saatinde; X günden az kaldıysa bugünün hatırlatma saatine
///   çekilir; geçerlilik günü geçmişse kurulmaz. Ayar kapalıysa yok.
/// - `refresh` kullanıcı işlemlerinde çalışır (durum değişimi, gün listesi, form kaydı); `sync` her hatırlatma
///   hesaplamasında çalışır: eksiği kurar (takip için yalnızca hiç takip görevi yoksa), geçersizi siler, **var olan açık
///   göreve dokunmaz** (kullanıcı ertelemiş olabilir). Tamamlanan görev aynı vade için yeniden kurulmaz.
@MainActor
struct QuoteReminderService {
    let repositories: Repositories
    let rules: QuoteReminderRules
    var calendar: Calendar = .current

    func sync(now: Date) throws {
        var byQuote: [UUID: [FollowUpTask]] = [:]
        for task in try repositories.tasks.fetchAll() where task.source == .quoteFollowUp || task.source == .quoteExpiry {
            guard let id = task.quote?.id else { continue }
            byQuote[id, default: []].append(task)
        }
        for quote in try repositories.quotes.fetchAll() {
            try reconcile(quote, tasks: byQuote[quote.id] ?? [], now: now, replaceFollowUps: false, updateExisting: false)
        }
    }

    /// - Parameters:
    ///   - replaceFollowUps: açık takip görevlerini silip günlere göre yeniden kurar (gönderilince, gün listesi değişince).
    ///   - updateExisting: var olan açık geçerlilik uyarısını yeni tarihe/başlığa günceller (form kaydı, gönderim).
    func refresh(_ quote: Quote, now: Date = Date(), replaceFollowUps: Bool = false, updateExisting: Bool = false) throws {
        let tasks = try repositories.tasks.fetchAll().filter {
            ($0.source == .quoteFollowUp || $0.source == .quoteExpiry) && $0.quote?.id == quote.id
        }
        try reconcile(quote, tasks: tasks, now: now, replaceFollowUps: replaceFollowUps, updateExisting: updateExisting)
    }

    // MARK: - Mantık

    private func reconcile(_ quote: Quote, tasks: [FollowUpTask], now: Date, replaceFollowUps: Bool, updateExisting: Bool) throws {
        guard quote.status.isPending else {
            for task in tasks where !task.isDone { try repositories.tasks.delete(task) }
            return
        }
        try reconcileFollowUps(quote, tasks: tasks.filter { $0.source == .quoteFollowUp }, now: now, replace: replaceFollowUps)
        try reconcileExpiry(quote, tasks: tasks.filter { $0.source == .quoteExpiry }, now: now, updateExisting: updateExisting)
    }

    private func reconcileFollowUps(_ quote: Quote, tasks: [FollowUpTask], now: Date, replace: Bool) throws {
        let desired = Self.followUpSchedule(for: quote, rules: rules, now: now, calendar: calendar)
        if replace {
            for task in tasks where !task.isDone { try repositories.tasks.delete(task) }
            for item in desired where !tasks.contains(where: { $0.isDone && $0.dueDate == item.due }) {
                try addFollowUp(item, for: quote)
            }
        } else if tasks.isEmpty {
            for item in desired { try addFollowUp(item, for: quote) }
        }
    }

    private func addFollowUp(_ item: (day: Int, due: Date), for quote: Quote) throws {
        let task = FollowUpTask(title: Self.followUpTitle(for: quote, day: item.day), dueDate: item.due, source: .quoteFollowUp)
        try repositories.tasks.add(task, customer: quote.customer, quote: quote, visit: nil)
    }

    private func reconcileExpiry(_ quote: Quote, tasks: [FollowUpTask], now: Date, updateExisting: Bool) throws {
        let open = tasks.filter { !$0.isDone }
        guard let due = Self.expiryDue(for: quote, rules: rules, now: now, calendar: calendar) else {
            for task in open { try repositories.tasks.delete(task) }
            return
        }
        let title = Self.expiryTitle(for: quote)
        if let first = open.first {
            for duplicate in open.dropFirst() { try repositories.tasks.delete(duplicate) }
            guard updateExisting else { return }
            var changed = false
            if first.title != title { first.title = title; changed = true }
            if first.dueDate != due { first.dueDate = due; changed = true }
            if changed { try repositories.tasks.update(first) }
        } else if !tasks.contains(where: { $0.dueDate == due }) {
            let task = FollowUpTask(title: title, dueDate: due, source: .quoteExpiry)
            try repositories.tasks.add(task, customer: quote.customer, quote: quote, visit: nil)
        }
    }

    // MARK: - Saf hesaplar (testle denenir)

    /// Takip günleri: gönderim günü + N gün, hatırlatma saatinde; bugünden önceki günler atlanır.
    static func followUpSchedule(for quote: Quote, rules: QuoteReminderRules, now: Date, calendar: Calendar) -> [(day: Int, due: Date)] {
        let base = calendar.startOfDay(for: quote.sentAt ?? now)
        let today = calendar.startOfDay(for: now)
        return quote.effectiveFollowUpDays(defaultDays: rules.defaultFollowUpDays).compactMap { days in
            guard let day = calendar.date(byAdding: .day, value: days, to: base), day >= today else { return nil }
            return (days, rules.reminderTime.date(on: day, calendar: calendar))
        }
    }

    /// Geçerlilik uyarısının vadesi; uyarı gerekmiyorsa `nil`.
    static func expiryDue(for quote: Quote, rules: QuoteReminderRules, now: Date, calendar: Calendar) -> Date? {
        guard rules.expiryEnabled, quote.status.isPending, let valid = quote.validUntil else { return nil }
        let today = calendar.startOfDay(for: now)
        let validDay = calendar.startOfDay(for: valid)
        guard validDay >= today else { return nil }
        let dueDay = calendar.date(byAdding: .day, value: -max(rules.expiryDaysBefore, 0), to: validDay) ?? validDay
        return rules.reminderTime.date(on: max(dueDay, today), calendar: calendar)
    }

    static func followUpTitle(for quote: Quote, day: Int) -> String {
        let number = VisitText.singleLine(quote.quoteNumber)
        return number.isEmpty ? "Teklif takibi · \(day). gün" : "Teklif takibi: \(number) · \(day). gün"
    }

    static func expiryTitle(for quote: Quote) -> String {
        let number = VisitText.singleLine(quote.quoteNumber)
        let base = number.isEmpty ? "Teklif geçerliliği bitiyor" : "Teklif geçerliliği bitiyor: \(number)"
        guard let valid = quote.validUntil else { return base }
        return "\(base) (\(AppFormat.date(valid)))"
    }
}
