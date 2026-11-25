import Foundation

/// Görev üzerindeki kullanıcı işlemleri: Bugün ekranındaki kaydırma, bildirim aksiyonları.
@MainActor
struct TaskActionService {
    let repositories: Repositories
    var calendar: Calendar = .current
    var now: () -> Date = { Date() }

    func complete(_ task: FollowUpTask) throws {
        try repositories.tasks.complete(task, at: now())
    }

    func postpone(_ task: FollowUpTask, _ option: PostponeOption) throws {
        let newDate = PostponeRule.newDueDate(
            current: task.dueDate,
            option: option,
            now: now(),
            calendar: calendar
        )
        try repositories.tasks.postpone(task, to: newDate)
    }
}
