import Foundation

/// "Plana ekle" ile açılan görevlerin ortak adlandırması (sabah özeti planlı ziyaretleri bu önekten sayar).
enum WeekPlanTask {
    static let titlePrefix = "Ziyaret: "

    static func title(for customer: Customer) -> String { titlePrefix + customer.name }

    /// O gün için "Ziyaret: <firma>" görevi ekler (hatırlatma saatinde). Aynı gün aynı müşteri için açık görev varsa eklemez.
    /// - Returns: Eklendiyse true.
    @MainActor
    @discardableResult
    static func add(
        customer: Customer, day: Date, reminderTime: TimeOfDay, repositories: Repositories, calendar: Calendar = .current
    ) throws -> Bool {
        let title = title(for: customer)
        let existing = try repositories.tasks.openTasks(on: day, calendar: calendar)
        if existing.contains(where: { $0.title == title && $0.customer?.id == customer.id }) { return false }
        let task = FollowUpTask(title: title, dueDate: reminderTime.date(on: day, calendar: calendar), source: .manual)
        try repositories.tasks.add(task, customer: customer, quote: nil, visit: nil, opportunity: nil)
        return true
    }

    /// O güne planlanmış (açık) ziyaret görevi olan müşteriler.
    @MainActor
    static func plannedCustomerIDs(on day: Date, repositories: Repositories, calendar: Calendar = .current) throws -> Set<UUID> {
        Set(try repositories.tasks.openTasks(on: day, calendar: calendar)
            .filter { $0.title.hasPrefix(titlePrefix) }
            .compactMap { $0.customer?.id })
    }
}

/// Haftalık şehir planı: gün → şehirler (boş veya birden fazla olabilir). Pazartesi–Cuma gösterilir.
struct WeekPlan: Equatable {
    var cities: [String: [String]] = [:]

    static func key(_ date: Date, calendar: Calendar) -> String {
        ReminderPlanner.dayKey(calendar.startOfDay(for: date), calendar: calendar)
    }

    /// Gösterilen haftanın Pazartesi–Cuma günleri: hafta içinde bu hafta; Cumartesi/Pazar'da gelecek hafta.
    static func displayedWeek(at date: Date, calendar: Calendar) -> [Date] {
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day) // 1 = Pazar … 7 = Cumartesi
        let shiftToMonday: Int
        switch weekday {
        case 7: shiftToMonday = 2
        case 1: shiftToMonday = 1
        default: shiftToMonday = -(weekday - 2)
        }
        let monday = calendar.date(byAdding: .day, value: shiftToMonday, to: day) ?? day
        return (0..<5).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    func cities(on date: Date, calendar: Calendar) -> [String] {
        cities[Self.key(date, calendar: calendar)] ?? []
    }

    mutating func set(_ list: [String], on date: Date, calendar: Calendar) {
        let key = Self.key(date, calendar: calendar)
        if list.isEmpty { cities[key] = nil } else { cities[key] = list }
    }

    /// Önceki haftanın (7 gün önce) atamalarını verilen günlere kopyalar; önceki haftada boş olan gün boşalır.
    mutating func copyPreviousWeek(into week: [Date], calendar: Calendar) {
        for day in week {
            guard let previous = calendar.date(byAdding: .day, value: -7, to: day) else { continue }
            set(cities(on: previous, calendar: calendar), on: day, calendar: calendar)
        }
    }

    func hasPreviousWeek(for week: [Date], calendar: Calendar) -> Bool {
        week.contains { day in
            calendar.date(byAdding: .day, value: -7, to: day).map { !cities(on: $0, calendar: calendar).isEmpty } ?? false
        }
    }

    /// Verilen günden 28+ gün eski kayıtları atar (ayarlarda şişmesin).
    mutating func prune(before date: Date, calendar: Calendar) {
        let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: date)) ?? date
        let cutoffKey = Self.key(cutoff, calendar: calendar)
        cities = cities.filter { $0.key >= cutoffKey }
    }
}

/// Bir müşterinin o gün önerilme nedeni. `priority` küçük olan önce (SPEC sırası).
enum VisitReason: Equatable {
    case overdueTasks(Int)
    /// Gün sayısı: bitişe kalan; negatif = süresi doldu.
    case quoteExpiring(days: Int)
    case visitDue(days: Int)
    case openOpportunity(title: String, count: Int)
    case neverVisited

    var priority: Int {
        switch self {
        case .overdueTasks: return 0
        case .quoteExpiring: return 1
        case .visitDue: return 2
        case .openOpportunity: return 3
        case .neverVisited: return 4
        }
    }

    var text: String {
        switch self {
        case .overdueTasks(let n): return "\(n) gecikmiş takip"
        case .quoteExpiring(let days):
            if days < 0 { return "Teklif süresi doldu" }
            return days == 0 ? "Teklif bugün sona eriyor" : "Teklif \(days) gün içinde sona eriyor"
        case .visitDue(let days): return "Ziyaret zamanı geldi (\(days) gün)"
        case .openOpportunity(let title, let count): return count > 1 ? "\(count) açık fırsat" : "Açık fırsat: \(title)"
        case .neverVisited: return "Hiç ziyaret edilmemiş aday"
        }
    }

    var symbol: String {
        switch self {
        case .overdueTasks: return "exclamationmark.circle"
        case .quoteExpiring: return "doc.text"
        case .visitDue: return "clock.badge.exclamationmark"
        case .openOpportunity: return "target"
        case .neverVisited: return "person.badge.plus"
        }
    }
}

struct VisitSuggestion: Identifiable {
    let customer: Customer
    /// Önceliğe göre sıralı; ilki satırı sıralayan "ana" nedendir.
    let reasons: [VisitReason]
    var isPlanned: Bool
    var id: UUID { customer.id }
    var primary: VisitReason { reasons[0] }
}

/// "Önerilen ziyaretler": günün şehir(ler)indeki müşteriler, neden önerildiğiyle ve öncelik sırasıyla:
/// 1) gecikmiş takibi olan, 2) geçerliliği yaklaşan teklifi olan, 3) ziyaret sıklığı aşılan,
/// 4) açık fırsatı olan, 5) hiç ziyaret edilmemiş adaylar. Hiçbir nedeni olmayan müşteri önerilmez; pasifler önerilmez.
/// Aynı öncelikte önemli → potansiyelli → zayıf, sonra ada göre.
@MainActor
enum VisitSuggester {
    private static let turkish = Locale(identifier: "tr_TR")

    static func suggestions(
        cities: [String],
        customers: [Customer],
        regionCities: [String],
        context: RegionContext,
        expiryWarningDays: Int,
        plannedCustomerIDs: Set<UUID>
    ) -> [VisitSuggestion] {
        let wanted = Set(cities.map(DistrictCatalog.normalize))
        let today = context.calendar.startOfDay(for: context.now)

        let result: [VisitSuggestion] = customers.compactMap { customer in
            guard customer.status != .passive else { return nil }
            let city = RegionBuilder.cityName(of: customer, regionCities: regionCities)
            guard wanted.contains(DistrictCatalog.normalize(city)) else { return nil }
            let found = reasons(for: customer, today: today, context: context, expiryWarningDays: expiryWarningDays)
            guard !found.isEmpty else { return nil }
            return VisitSuggestion(customer: customer, reasons: found, isPlanned: plannedCustomerIDs.contains(customer.id))
        }
        return result.sorted { lhs, rhs in
            if lhs.primary.priority != rhs.primary.priority { return lhs.primary.priority < rhs.primary.priority }
            let (l, r) = (ratingRank(lhs.customer.rating), ratingRank(rhs.customer.rating))
            if l != r { return l < r }
            return lhs.customer.name.compare(rhs.customer.name, options: [.caseInsensitive], range: nil, locale: turkish) == .orderedAscending
        }
    }

    static func reasons(for customer: Customer, today: Date, context: RegionContext, expiryWarningDays: Int) -> [VisitReason] {
        var reasons: [VisitReason] = []
        let calendar = context.calendar

        // Sıklık ve geçerlilik uyarısı görevleri kendi nedenleriyle sayıldığından, plan görevleri de kendini
        // beslemesin diye gecikmiş takip sayımına girmez.
        let overdue = (customer.tasks ?? []).filter {
            !$0.isDone && $0.dueDate < today
                && $0.source != .visitFrequency && $0.source != .quoteExpiry
                && !$0.title.hasPrefix(WeekPlanTask.titlePrefix)
        }.count
        if overdue > 0 { reasons.append(.overdueTasks(overdue)) }

        let expiring = (customer.quotes ?? []).compactMap { quote -> Int? in
            guard quote.status.isPending, let valid = quote.validUntil else { return nil }
            let days = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: valid)).day ?? 0
            return days <= expiryWarningDays ? days : nil
        }.min()
        if let expiring { reasons.append(.quoteExpiring(days: expiring)) }

        if context.visitFrequencyExceeded(customer) {
            let reference = customer.lastVisitDate ?? customer.createdAt
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: today).day ?? 0
            reasons.append(.visitDue(days: days))
        }

        let open = (customer.opportunities ?? []).filter { $0.stage.isOpen }
        if let first = open.sorted(by: { $0.title < $1.title }).first {
            reasons.append(.openOpportunity(title: first.title, count: open.count))
        }

        if customer.status == .potential, (customer.visits ?? []).isEmpty {
            reasons.append(.neverVisited)
        }
        return reasons
    }

    private static func ratingRank(_ rating: CustomerRating) -> Int {
        switch rating {
        case .important: return 0
        case .promising: return 1
        case .weak: return 2
        }
    }
}
