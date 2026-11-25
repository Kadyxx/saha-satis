import Foundation
import WidgetKit

/// Uygulamada görev, ziyaret veya teklif değişince (`appDataDidChange`) widget zaman çizelgelerini yeniler
/// (SPEC → Widget'lar). Art arda kayıtlar tek yenilemede birleşir.
@MainActor
final class WidgetReloader {
    private let reload: () -> Void
    private let delay: Duration
    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?

    init(delay: Duration = .milliseconds(300), reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.delay = delay
        self.reload = reload
    }

    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .appDataDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleReload() }
        }
    }

    func reloadNow() {
        pending?.cancel()
        reload()
    }

    private func scheduleReload() {
        pending?.cancel()
        pending = Task { [weak self] in
            guard let delay = self?.delay else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }
}
