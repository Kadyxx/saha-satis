import Foundation

/// Ziyaret sıklığı eşikleri ve görevlerin bildirim saati (Ayarlar'dan).
struct VisitFrequencyRules: Equatable, Sendable {
    var importantDays = 30
    var promisingDays = 60
    var weakDays = 120
    var reminderTime = TimeOfDay(hour: 9)

    func days(for rating: CustomerRating) -> Int {
        switch rating {
        case .important: return importantDays
        case .promising: return promisingDays
        case .weak: return weakDays
        }
    }
}

/// Ziyaret sıklığı uyarıları (SPEC → Hatırlatma motoru): her müşteri için en çok TEK açık görev tutulur.
/// Yeni ziyaret girilince `VisitService` açık görevi kapatır; bir sonraki `sync` yeni görevi son ziyarete göre kurar.
///
/// - Vade = referans gün + değerlendirmeye göre eşik gün, hatırlatma saatinde. Referans = son ziyaret
///   (hiç yoksa müşterinin eklenme tarihi) ile en son tamamlanan sıklık görevinin tamamlanma zamanından yeni olanı.
///   Böylece kullanıcı "Tamamlandı" derse görev hemen geri gelmez, sayaç yeniden başlar.
/// - Eşik çoktan geçmişse vade bugünün hatırlatma saatine çekilir (aksi halde ilk açılışta onlarca eski "gecikmiş" çıkardı).
/// - Pasif müşteri için görev tutulmaz (açık olanlar silinir).
/// - Var olan açık görev bir daha değiştirilmez (kullanıcı ertelemiş olabilir); fazlalık kopyalar silinir.
@MainActor
struct VisitFrequencyService {
    static let taskTitle = "Ziyaret zamanı geldi"

    let repositories: Repositories
    let rules: VisitFrequencyRules
    var calendar: Calendar = .current

    func sync(now: Date) throws {
        let customers = try repositories.customers.fetchAll()
        var tasksByCustomer: [UUID: [FollowUpTask]] = [:]
        for task in try repositories.tasks.fetchAll() where task.source == .visitFrequency {
            guard let customerID = task.customer?.id else { continue }
            tasksByCustomer[customerID, default: []].append(task)
        }

        for customer in customers {
            let tasks = tasksByCustomer[customer.id] ?? []
            let open = tasks.filter { !$0.isDone }

            if customer.status == .passive {
                for task in open {
                    try repositories.tasks.delete(task)
                }
                continue
            }
            if !open.isEmpty {
                for duplicate in open.dropFirst() {
                    try repositories.tasks.delete(duplicate)
                }
                continue
            }

            let lastVisit = customer.lastVisitDate ?? customer.createdAt
            let reference = max(lastVisit, tasks.compactMap(\.doneAt).max() ?? .distantPast)
            let due = Self.dueDate(
                reference: reference,
                thresholdDays: rules.days(for: customer.rating),
                reminderTime: rules.reminderTime,
                now: now,
                calendar: calendar
            )
            let task = FollowUpTask(title: Self.taskTitle, dueDate: due, source: .visitFrequency)
            try repositories.tasks.add(task, customer: customer, quote: nil, visit: nil)
        }
    }

    static func dueDate(
        reference: Date,
        thresholdDays: Int,
        reminderTime: TimeOfDay,
        now: Date,
        calendar: Calendar
    ) -> Date {
        let referenceDay = calendar.startOfDay(for: reference)
        let dueDay = calendar.date(byAdding: .day, value: max(thresholdDays, 1), to: referenceDay) ?? referenceDay
        let today = calendar.startOfDay(for: now)
        return reminderTime.date(on: max(dueDay, today), calendar: calendar)
    }
}
