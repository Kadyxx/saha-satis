import Foundation

/// Ziyaret formunun ürettiği değerler.
struct VisitDraft: Equatable {
    var date = Date()
    var type: VisitType = .visit
    /// Konu (tek satır, isteğe bağlı).
    var topic = ""
    /// Düzenlenmiş görüşme notu (`Visit.summary`).
    var summary = ""
    /// Ham ses metni (`Visit.transcript`); yalnızca sesli not kullanıldıysa dolu.
    var transcript = ""
    var nextStep = ""
    /// Seçilirse bağlı bir `FollowUpTask` (source: `visitNextStep`) oluşur.
    var nextStepDate: Date?
}

/// Ziyaret kaydetme iş kuralları (Repository'lerin üstünde):
/// - yeni ziyaret `exportedToCRM = false` başlar,
/// - `nextStepDate` seçilirse bağlı takip görevi oluşur / güncellenir / kaldırılır,
/// - yeni ziyaret girilince müşterinin açık "ziyaret sıklığı" görevi kapanır (SPEC → Hatırlatma motoru).
/// Müşterinin son ziyaret tarihi `Customer.lastVisitDate` ile ziyaretlerden hesaplanır.
@MainActor
struct VisitService {
    let repositories: Repositories
    /// Tarihli görevlerin bildirim saati, gün başından itibaren dakika (Ayarlar → hatırlatma saati; varsayılan 09:00).
    let reminderMinutes: Int
    var calendar: Calendar = .current

    @discardableResult
    func save(_ draft: VisitDraft, customer: Customer, contacts: [Contact], existing: Visit?) throws -> Visit {
        let visit: Visit
        if let existing {
            visit = existing
            apply(draft, to: visit)
            visit.contacts = contacts
            try repositories.visits.update(visit)
        } else {
            visit = Visit()
            apply(draft, to: visit)
            try repositories.visits.add(visit, customer: customer, contacts: contacts, opportunity: nil)
            try closeVisitFrequencyTasks(for: customer)
        }
        try syncNextStepTask(for: visit, customer: customer, draft: draft)
        return visit
    }

    /// Ziyareti ve ondan doğan henüz tamamlanmamış sonraki-adım görevini siler.
    func delete(_ visit: Visit) throws {
        if let customer = visit.customer {
            for task in try nextStepTasks(for: visit, customer: customer) where !task.isDone {
                try repositories.tasks.delete(task)
            }
        }
        try repositories.visits.delete(visit)
    }

    // MARK: - Yardımcılar

    private func apply(_ draft: VisitDraft, to visit: Visit) {
        visit.date = draft.date
        visit.type = draft.type
        visit.transcript = draft.transcript
        visit.summary = draft.summary
        visit.topic = draft.topic
        visit.nextStep = draft.nextStep
        visit.nextStepDate = draft.nextStepDate
    }

    private func nextStepTasks(for visit: Visit, customer: Customer) throws -> [FollowUpTask] {
        try repositories.tasks.tasks(for: customer)
            .filter { $0.visit?.id == visit.id && $0.source == .visitNextStep }
    }

    private func dueDate(for day: Date) -> Date {
        calendar.date(
            bySettingHour: reminderMinutes / 60,
            minute: reminderMinutes % 60,
            second: 0,
            of: day
        ) ?? day
    }

    private func syncNextStepTask(for visit: Visit, customer: Customer, draft: VisitDraft) throws {
        let all = try nextStepTasks(for: visit, customer: customer)
        let open = all.filter { !$0.isDone }

        guard let day = draft.nextStepDate else {
            for task in open {
                try repositories.tasks.delete(task)
            }
            return
        }

        let trimmed = draft.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Sonraki adım" : trimmed
        let due = dueDate(for: day)

        if let task = open.first {
            task.title = title
            task.dueDate = due
            try repositories.tasks.update(task)
            for duplicate in open.dropFirst() {
                try repositories.tasks.delete(duplicate)
            }
        } else if all.isEmpty {
            let task = FollowUpTask(title: title, dueDate: due, source: .visitNextStep)
            try repositories.tasks.add(task, customer: customer, quote: nil, visit: visit)
        }
        // Yalnızca tamamlanmış görev varsa: kullanıcı zaten yapmış; yeniden açılmaz.
    }

    private func closeVisitFrequencyTasks(for customer: Customer) throws {
        let pending = try repositories.tasks.tasks(for: customer)
            .filter { $0.source == .visitFrequency && !$0.isDone }
        for task in pending {
            try repositories.tasks.complete(task, at: Date())
        }
    }
}
