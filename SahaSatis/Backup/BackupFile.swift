import Foundation

/// Yedek dosyası: tüm veri + ayarlar, tek JSON. İlişkiler `id` ile tutulur.
/// Tarihler `JSONEncoder`'ın varsayılanıyla (2001'den itibaren saniye) kayıpsız yazılır.
/// Modele alan eklenirse buraya da eklenmeli; eski yedekler açılabilsin diye yeni alanlar opsiyonel olmalı.
struct BackupFile: Codable, Equatable, Sendable {
    static let formatID = "sahasatis-backup"
    static let currentVersion = 1

    var format = BackupFile.formatID
    var version = BackupFile.currentVersion
    var createdAt: Date
    var appVersion: String
    var data: BackupData
    var settings: BackupSettings?
}

struct BackupData: Codable, Equatable, Sendable {
    var customers: [CustomerRecord] = []
    var contacts: [ContactRecord] = []
    var visits: [VisitRecord] = []
    var opportunities: [OpportunityRecord] = []
    var quotes: [QuoteRecord] = []
    var quoteItems: [QuoteItemRecord] = []
    var installedProducts: [InstalledProductRecord] = []
    var tasks: [TaskRecord] = []
}

struct CustomerRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var name: String
    var city: String
    var district: String
    var industrialZone: String
    var sector: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var statusRaw: String
    var ratingRaw: String
    var ratingNote: String
    var notes: String
}

struct ContactRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var fullName: String
    var title: String
    var phone: String
    var email: String
    var notes: String
    var isPrimary: Bool
    var customerID: UUID?
}

struct VisitRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var date: Date
    var typeRaw: String
    var transcript: String
    var summary: String
    var topic: String
    var topics: [String]
    var nextStep: String
    var nextStepDate: Date?
    var exportedToCRM: Bool
    var exportedAt: Date?
    var customerID: UUID?
    var contactIDs: [UUID]
    var opportunityID: UUID?
}

struct OpportunityRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var title: String
    var details: String
    var estimatedValue: Double
    var currencyRaw: String
    var stageRaw: String
    var expectedCloseDate: Date?
    var lostReason: String
    var customerID: UUID?
}

struct QuoteRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var quoteNumber: String
    var date: Date
    var validUntil: Date?
    var currencyRaw: String
    var statusRaw: String
    var followUpDays: [Int]
    var notes: String
    var lostReason: String
    var sentAt: Date?
    var customerID: UUID?
    var opportunityID: UUID?
}

struct QuoteItemRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var catalogNumber: String
    var itemDescription: String
    var quantity: Int
    var unitPrice: Double
    var discountPercent: Double
    var position: Int
    var quoteID: UUID?
}

struct InstalledProductRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var catalogNumber: String
    var productFamily: String
    var quantity: Int
    var lifecycleStatusRaw: String
    var notes: String
    var customerID: UUID?
}

struct TaskRecord: Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var ownerUserID: String
    var title: String
    var dueDate: Date
    var isDone: Bool
    var doneAt: Date?
    var sourceRaw: String
    var notificationID: String
    var customerID: UUID?
    var quoteID: UUID?
    var visitID: UUID?
    var opportunityID: UUID?
}

enum BackupError: LocalizedError, Equatable {
    case notABackup
    case newerVersion
    case damaged

    var errorDescription: String? {
        switch self {
        case .notABackup:
            return "Bu dosya bir Saha Satış yedeği değil."
        case .newerVersion:
            return "Yedek, uygulamanın daha yeni bir sürümüyle alınmış. Önce uygulamayı güncelleyin."
        case .damaged:
            return "Yedek dosyası bozuk veya eksik; okunamadı."
        }
    }
}

/// Yedek dosyasını yazar ve okur. Okuma, veriye dokunmadan önce dosyanın tamamını doğrular.
enum BackupCodec {
    private struct Header: Decodable {
        let format: String
        let version: Int
    }

    static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func decode(_ data: Data) throws -> BackupFile {
        guard let header = try? JSONDecoder().decode(Header.self, from: data), header.format == BackupFile.formatID else {
            throw BackupError.notABackup
        }
        guard header.version <= BackupFile.currentVersion else { throw BackupError.newerVersion }
        guard let file = try? JSONDecoder().decode(BackupFile.self, from: data) else { throw BackupError.damaged }
        return file
    }

    /// "SahaSatis-Yedek-2026-11-27-1430.json"
    static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(
            format: "SahaSatis-Yedek-%04d-%02d-%02d-%02d%02d.json",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0
        )
    }
}

/// Bugün ekranındaki yedek uyarısı.
enum BackupReminder: Equatable {
    /// Kayıt var ama hiç yedek alınmamış.
    case never
    /// Son yedek 7 günden eski; kaç takvim günü geçtiği.
    case stale(days: Int)

    static let maxAge: TimeInterval = 7 * 24 * 3600

    static func evaluate(lastBackup: Date?, hasData: Bool, now: Date, calendar: Calendar = .current) -> BackupReminder? {
        guard let lastBackup else { return hasData ? .never : nil }
        guard now.timeIntervalSince(lastBackup) > maxAge else { return nil }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: lastBackup), to: calendar.startOfDay(for: now)
        ).day ?? 7
        return .stale(days: days)
    }

    var message: String {
        switch self {
        case .never: return "Henüz yedek alınmadı"
        case .stale(let days): return "Son yedek \(days) gün önce alındı"
        }
    }
}
