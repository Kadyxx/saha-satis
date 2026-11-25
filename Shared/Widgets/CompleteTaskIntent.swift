import AppIntents
import Foundation

/// Ana ekran widget'ındaki onay kutusu: uygulamayı açmadan görevi tamamlar.
/// Hem uygulama hem widget hedefinde derlenir (widget düğmesi `Button(intent:)` ile kullanır).
struct CompleteTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Takibi tamamla"

    @Parameter(title: "Görev")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskID) {
            WidgetTaskCompleter.completeInStore(taskID: id)
        }
        return .result()
    }
}
