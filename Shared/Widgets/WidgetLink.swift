import Foundation

/// Widget'tan uygulamaya derin bağlantılar: `sahasatis://task/<uuid>`, `sahasatis://today`, `sahasatis://visit/new`.
/// Şema `project.yml` içindeki `CFBundleURLTypes` ile kayıtlıdır.
enum WidgetLink: Equatable {
    case task(UUID)
    case today
    case newVisit

    static let scheme = "sahasatis"

    var url: URL {
        switch self {
        case .task(let id): return URL(string: "\(Self.scheme)://task/\(id.uuidString)")!
        case .today: return URL(string: "\(Self.scheme)://today")!
        case .newVisit: return URL(string: "\(Self.scheme)://visit/new")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "task":
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            self = .task(id)
        case "today":
            self = .today
        case "visit":
            guard url.lastPathComponent == "new" else { return nil }
            self = .newVisit
        default:
            return nil
        }
    }
}
