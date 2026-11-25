import Foundation
@testable import SahaSatis

/// Sistem bildirim merkezi yerine geçen sahte planlayıcı: `replaceAll` çağrılarını kaydeder.
@MainActor
final class MockNotificationScheduler: NotificationScheduling {
    var state: NotificationAuthorization
    var grantsOnRequest: Bool
    private(set) var requestCount = 0
    /// Her `replaceAll` çağrısının listesi.
    private(set) var calls: [[PlannedNotification]] = []

    init(state: NotificationAuthorization = .authorized, grantsOnRequest: Bool = true) {
        self.state = state
        self.grantsOnRequest = grantsOnRequest
    }

    var lastPlan: [PlannedNotification] { calls.last ?? [] }

    func authorization() async -> NotificationAuthorization { state }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        if grantsOnRequest { state = .authorized }
        return grantsOnRequest
    }

    func replaceAll(with notifications: [PlannedNotification]) async {
        calls.append(notifications)
    }
}
