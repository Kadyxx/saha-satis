import Foundation
import Observation

/// Bugün ekranındaki takip grupları (SPEC → Bugün): gecikmiş, bugün, yarın.
/// Yalnızca açık görevler; her grup vadeye göre artan sıralıdır. Gruplama gün bazlıdır:
/// bugün saati geçmiş bir görev hâlâ "Bugün"dür, "Gecikmiş" ancak vade günü geçince olur.
struct TodaySections {
    var overdue: [FollowUpTask] = []
    var today: [FollowUpTask] = []
    var tomorrow: [FollowUpTask] = []

    var isEmpty: Bool { overdue.isEmpty && today.isEmpty && tomorrow.isEmpty }

    static func make(from tasks: [FollowUpTask], now: Date, calendar: Calendar) -> TodaySections {
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let dayAfterStart = calendar.date(byAdding: .day, value: 2, to: todayStart) ?? tomorrowStart

        var sections = TodaySections()
        for task in tasks.filter({ !$0.isDone }).sorted(by: { $0.dueDate < $1.dueDate }) {
            if task.dueDate < todayStart {
                sections.overdue.append(task)
            } else if task.dueDate < tomorrowStart {
                sections.today.append(task)
            } else if task.dueDate < dayAfterStart {
                sections.tomorrow.append(task)
            }
        }
        return sections
    }
}

/// Bugün ekranının durumu. Veriye yalnızca repository'ler üzerinden erişir.
@MainActor
@Observable
final class TodayModel {
    private let repositories: Repositories
    private let calendar: Calendar

    private(set) var sections = TodaySections()
    /// Bugün yapılan ziyaretler, yeniden eskiye.
    private(set) var visitsToday: [Visit] = []
    var errorMessage: String?

    init(repositories: Repositories, calendar: Calendar = .current) {
        self.repositories = repositories
        self.calendar = calendar
    }

    /// "CRM'e aktarılmadı" sayısı: bugünkü ziyaretlerden henüz aktarılmamış olanlar.
    var unexportedCount: Int {
        visitsToday.filter { !$0.exportedToCRM }.count
    }

    func reload(now: Date = Date()) {
        do {
            sections = TodaySections.make(from: try repositories.tasks.openTasks(), now: now, calendar: calendar)
            visitsToday = try repositories.visits.visits(on: now, calendar: calendar)
        } catch {
            errorMessage = "Bugün ekranı yüklenemedi: \(error.localizedDescription)"
        }
    }

    func complete(_ task: FollowUpTask) {
        perform { try TaskActionService(repositories: repositories, calendar: calendar).complete(task) }
    }

    func postpone(_ task: FollowUpTask, _ option: PostponeOption) {
        perform { try TaskActionService(repositories: repositories, calendar: calendar).postpone(task, option) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = "İşlem kaydedilemedi: \(error.localizedDescription)"
        }
        reload()
    }
}
