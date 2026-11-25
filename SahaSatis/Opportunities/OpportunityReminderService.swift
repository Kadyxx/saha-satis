import Foundation

/// Fırsat kapanış hatırlatması ayarları (Ayarlar → Fırsatlar) ve görev saati.
struct OpportunityReminderRules: Equatable, Sendable {
    var enabled = true
    var daysBefore = 7
    var reminderTime = TimeOfDay(hour: 9)
}

/// Fırsatın beklenen kapanış tarihinden X gün önce bir hatırlatma görevi (`TaskSource.opportunityClose`) kurar
/// (SPEC → Hatırlatma motoru → "Fırsat kapanış tarihi"). Bildirimler görevlerden üretildiği için ayrıca bildirim
/// kodu gerekmez; görev silinince bildirim de bir sonraki hesaplamada kalkar.
///
/// - Hatırlatma yalnızca **açık** aşamalardaki (Yeni, Nitelikli, Teklif verildi, Pazarlık), kapanış tarihi olan ve
///   ayarı açık fırsatlar için vardır; Kazanıldı/Kaybedildi olunca bekleyen hatırlatma silinir.
/// - Vade = kapanış günü − X gün, hatırlatma saatinde. O gün çoktan geçmişse (kapanışa X günden az kaldıysa)
///   bugünün hatırlatma saatine çekilir; **kapanış günü de geçmişse** hatırlatma kurulmaz.
/// - `sync` (her hatırlatma hesaplamasında çalışır) eksik hatırlatmayı kurar, geçersizleri siler, **var olan açık
///   hatırlatmaya dokunmaz** (kullanıcı ertelemiş olabilir). `refresh` (fırsat kaydedilince/aşaması değişince)
///   var olanı da günceller. Kullanıcı hatırlatmayı tamamladıysa aynı vade için yenisi kurulmaz.
@MainActor
struct OpportunityReminderService {
    static let titlePrefix = "Fırsat kapanışı yaklaşıyor"

    let repositories: Repositories
    let rules: OpportunityReminderRules
    var calendar: Calendar = .current

    /// Kapanış tarihi bilinen tüm fırsatları eşitler: eksik hatırlatmaları kurar, geçersizleri siler.
    func sync(now: Date) throws {
        var byOpportunity: [UUID: [FollowUpTask]] = [:]
        for task in try repositories.tasks.fetchAll() where task.source == .opportunityClose {
            guard let id = task.opportunity?.id else { continue }
            byOpportunity[id, default: []].append(task)
        }
        for opportunity in try repositories.opportunities.fetchAll() {
            try reconcile(opportunity, tasks: byOpportunity[opportunity.id] ?? [], now: now, updateExisting: false)
        }
    }

    /// Tek fırsat: hatırlatmayı gerekirse kurar, günceller veya siler.
    func refresh(_ opportunity: Opportunity, now: Date = Date()) throws {
        let tasks = try repositories.tasks.fetchAll()
            .filter { $0.source == .opportunityClose && $0.opportunity?.id == opportunity.id }
        try reconcile(opportunity, tasks: tasks, now: now, updateExisting: true)
    }

    // MARK: - Mantık

    private func reconcile(_ opportunity: Opportunity, tasks: [FollowUpTask], now: Date, updateExisting: Bool) throws {
        let open = tasks.filter { !$0.isDone }
        guard let due = Self.dueDate(for: opportunity, rules: rules, now: now, calendar: calendar) else {
            for task in open { try repositories.tasks.delete(task) }
            return
        }

        let title = Self.title(for: opportunity)
        if let first = open.first {
            for duplicate in open.dropFirst() { try repositories.tasks.delete(duplicate) }
            guard updateExisting else { return }
            var changed = false
            if first.title != title { first.title = title; changed = true }
            if first.dueDate != due { first.dueDate = due; changed = true }
            if first.customer?.id != opportunity.customer?.id { first.customer = opportunity.customer; changed = true }
            if changed { try repositories.tasks.update(first) }
        } else if !tasks.contains(where: { $0.dueDate == due }) {
            let task = FollowUpTask(title: title, dueDate: due, source: .opportunityClose)
            try repositories.tasks.add(task, customer: opportunity.customer, quote: nil, visit: nil, opportunity: opportunity)
        }
    }

    /// Hatırlatmanın vadesi; hatırlatma gerekmiyorsa `nil`.
    static func dueDate(for opportunity: Opportunity, rules: OpportunityReminderRules, now: Date, calendar: Calendar) -> Date? {
        guard rules.enabled, opportunity.stage.isOpen, let close = opportunity.expectedCloseDate else { return nil }
        return dueDate(closeDate: close, daysBefore: rules.daysBefore, reminderTime: rules.reminderTime, now: now, calendar: calendar)
    }

    static func dueDate(closeDate: Date, daysBefore: Int, reminderTime: TimeOfDay, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        let closeDay = calendar.startOfDay(for: closeDate)
        guard closeDay >= today else { return nil }
        let dueDay = calendar.date(byAdding: .day, value: -max(daysBefore, 0), to: closeDay) ?? closeDay
        return reminderTime.date(on: max(dueDay, today), calendar: calendar)
    }

    static func title(for opportunity: Opportunity) -> String {
        let name = VisitText.singleLine(opportunity.title)
        let base = name.isEmpty ? titlePrefix : "\(titlePrefix): \(name)"
        guard let close = opportunity.expectedCloseDate else { return base }
        return "\(base) (\(AppFormat.date(close)))"
    }
}

extension AppSettings {
    var opportunityReminderRules: OpportunityReminderRules {
        OpportunityReminderRules(
            enabled: opportunityCloseReminderEnabled,
            daysBefore: opportunityCloseReminderDays,
            reminderTime: defaultReminderTime
        )
    }
}
