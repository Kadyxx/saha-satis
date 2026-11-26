import Foundation

/// CSV'den içe aktarılabilen alanlar.
enum ImportField: String, CaseIterable, Hashable, Identifiable {
    case name, city, district, zone, sector, address, phone, email, contact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Firma"
        case .city: return "Şehir"
        case .district: return "İlçe"
        case .zone: return "OSB"
        case .sector: return "Sektör"
        case .address: return "Adres"
        case .phone: return "Telefon"
        case .email: return "E-posta"
        case .contact: return "Yetkili kişi"
        }
    }

    /// Başlık eşleme için bilinen yazımlar (normalize edilmiş: küçük harf, Türkçe karakter ve boşluksuz).
    fileprivate var synonyms: [String] {
        switch self {
        case .name: return ["firma", "firmaadi", "firmaunvani", "unvan", "musteri", "musteriadi", "sirket", "sirketadi", "isim", "ad", "name", "company"]
        case .city: return ["sehir", "il", "city", "province"]
        case .district: return ["ilce", "district"]
        case .zone: return ["osb", "organizesanayibolgesi", "sanayibolgesi", "sanayisitesi", "bolge", "zone"]
        case .sector: return ["sektor", "faaliyetalani", "faaliyet", "sector", "industry"]
        case .address: return ["adres", "acikadres", "address"]
        case .phone: return ["telefon", "tel", "telefonno", "telefonnumarasi", "gsm", "cep", "phone", "mobile"]
        case .email: return ["eposta", "epostaadresi", "mail", "email", "emailadresi"]
        case .contact: return ["yetkili", "yetkilikisi", "yetkilikisiad", "ilgilikisi", "kisi", "irtibat", "irtibatkisisi", "contact", "contactperson"]
        }
    }
}

/// Başlık satırını uygulama alanlarıyla eşler.
enum ColumnMapper {
    /// Başlık karşılaştırma anahtarı: küçük harf, Türkçe karakterler sadeleşmiş, harf/rakam dışı her şey atılmış.
    static func key(_ header: String) -> String {
        DistrictCatalog.normalize(header).filter { $0.isLetter || $0.isNumber }
    }

    /// Alan → sütun indeksi. Her sütun en fazla bir alana, her alan en fazla bir sütuna eşlenir (soldaki kazanır).
    static func autoMap(headers: [String]) -> [ImportField: Int] {
        var mapping: [ImportField: Int] = [:]
        var used = Set<Int>()
        let keys = headers.map(key)
        // Önce tam eşleşme, sonra "içerir" eşleşmesi ("Firma Adı (Ticari)" → firma).
        for exact in [true, false] {
            for field in ImportField.allCases where mapping[field] == nil {
                let found = keys.indices.first { index in
                    guard !used.contains(index), !keys[index].isEmpty else { return false }
                    return field.synonyms.contains { synonym in
                        exact ? keys[index] == synonym : (synonym.count >= 4 && keys[index].contains(synonym))
                    }
                }
                if let found {
                    mapping[field] = found
                    used.insert(found)
                }
            }
        }
        return mapping
    }
}

/// Eşlemeye göre okunmuş tek CSV kaydı.
struct ImportRecord: Equatable {
    /// Dosyadaki satır numarası (başlık 1; ilk veri satırı 2).
    var line: Int
    var name = ""
    var city = ""
    var district = ""
    var zone = ""
    var sector = ""
    var address = ""
    var phone = ""
    var email = ""
    var contact = ""
}

/// Önizlemedeki bir satırın sonucu.
enum ImportOutcome: Equatable {
    case add
    /// Aynı firma + şehir zaten kayıtlı.
    case conflict(existingID: UUID)
    case invalid(String)
}

struct ImportItem: Identifiable, Equatable {
    var record: ImportRecord
    var outcome: ImportOutcome
    var id: Int { record.line }
}

enum ConflictPolicy: String, CaseIterable, Identifiable {
    case skip, update
    var id: String { rawValue }
    var title: String { self == .skip ? "Atla" : "Güncelle" }
}

struct ImportCounts: Equatable {
    var add = 0
    var conflict = 0
    var invalid = 0
}

struct ImportResult: Equatable {
    var added = 0
    var updated = 0
    var skipped = 0
}

/// Eşleme + mevcut müşteriler → önizleme planı; plan → kayıtlar.
@MainActor
enum CustomerImporter {
    // MARK: - Okuma

    /// Eşlemeye göre veri satırlarını kayıtlara çevirir (başlık satırı hariç). Değerler kırpılır.
    static func records(rows: [[String]], mapping: [ImportField: Int]) -> [ImportRecord] {
        guard rows.count > 1 else { return [] }
        return rows.dropFirst().enumerated().map { offset, row in
            func value(_ field: ImportField) -> String {
                guard let index = mapping[field], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var record = ImportRecord(line: offset + 2)
            record.name = value(.name).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            record.city = value(.city)
            record.district = value(.district)
            record.zone = value(.zone)
            record.sector = value(.sector)
            record.address = value(.address)
            record.phone = value(.phone)
            record.email = value(.email)
            record.contact = value(.contact)
            return record
        }
    }

    // MARK: - Anahtarlar

    /// Çakışma anahtarı: firma adı + şehir; büyük/küçük harf, Türkçe karakter ve fazla boşluk duyarsız.
    static func conflictKey(name: String, city: String) -> String {
        DistrictCatalog.normalize(name) + "|" + DistrictCatalog.normalize(city)
    }

    /// Şehrin yazımı: bölge listesindeki/katalogdaki resmi ad; yoksa yazıldığı gibi.
    static func cityName(_ raw: String, regionCities: [String]) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = DistrictCatalog.normalize(trimmed)
        if let match = regionCities.first(where: { DistrictCatalog.normalize($0) == key }) { return match }
        return DistrictCatalog.canonicalCity(trimmed) ?? trimmed
    }

    private static func isValidEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !text.contains(" ")
    }

    // MARK: - Plan

    /// Her kayıt için sonuç: eklenecek / mevcutla çakışan / hatalı. Dosya içinde aynı firma+şehir tekrar ederse
    /// ilk satır geçerli, sonrakiler hatalı ("Dosyada tekrar") sayılır.
    static func plan(records: [ImportRecord], existing: [Customer], regionCities: [String]) -> [ImportItem] {
        var existingByKey: [String: UUID] = [:]
        for customer in existing {
            let key = conflictKey(name: customer.name, city: cityName(customer.city, regionCities: regionCities))
            if existingByKey[key] == nil { existingByKey[key] = customer.id }
        }
        var seen = Set<String>()
        return records.map { record in
            if record.name.isEmpty { return ImportItem(record: record, outcome: .invalid("Firma adı boş")) }
            if !record.email.isEmpty, !isValidEmail(record.email) {
                return ImportItem(record: record, outcome: .invalid("E-posta geçersiz"))
            }
            let key = conflictKey(name: record.name, city: cityName(record.city, regionCities: regionCities))
            if !seen.insert(key).inserted { return ImportItem(record: record, outcome: .invalid("Dosyada tekrar")) }
            if let id = existingByKey[key] { return ImportItem(record: record, outcome: .conflict(existingID: id)) }
            return ImportItem(record: record, outcome: .add)
        }
    }

    static func counts(_ items: [ImportItem]) -> ImportCounts {
        var counts = ImportCounts()
        for item in items {
            switch item.outcome {
            case .add: counts.add += 1
            case .conflict: counts.conflict += 1
            case .invalid: counts.invalid += 1
            }
        }
        return counts
    }

    // MARK: - Uygulama

    /// Planı kaydeder. Yeni müşteriler "Aday" durumunda ve seçilen değerlendirmeyle eklenir; ilçe şehrin resmi listesiyle
    /// eşleştirilir. Yetkili kişi (veya yalnızca telefon/e-posta) doluysa Contact eklenir. Çakışmalarda politika:
    /// atla ya da güncelle (dolu CSV alanları mevcut alanların üstüne yazılır, boş olanlar dokunmaz).
    @discardableResult
    static func apply(
        _ items: [ImportItem],
        policy: ConflictPolicy,
        rating: CustomerRating,
        regionCities: [String],
        repositories: Repositories
    ) throws -> ImportResult {
        var result = ImportResult()
        for item in items {
            let record = item.record
            switch item.outcome {
            case .invalid:
                continue
            case .add:
                let city = cityName(record.city, regionCities: regionCities)
                let customer = Customer(
                    name: record.name, city: city,
                    district: DistrictCatalog.displayName(record.district, city: city),
                    industrialZone: record.zone, sector: record.sector, address: record.address,
                    status: .potential, rating: rating
                )
                try repositories.customers.add(customer)
                try addContactIfNeeded(record, to: customer, repositories: repositories)
                result.added += 1
            case .conflict(let id):
                guard policy == .update, let customer = try repositories.customers.customer(id: id) else {
                    result.skipped += 1
                    continue
                }
                if !record.city.isEmpty { customer.city = cityName(record.city, regionCities: regionCities) }
                if !record.district.isEmpty {
                    customer.district = DistrictCatalog.displayName(record.district, city: customer.city)
                }
                if !record.zone.isEmpty { customer.industrialZone = record.zone }
                if !record.sector.isEmpty { customer.sector = record.sector }
                if !record.address.isEmpty { customer.address = record.address }
                try repositories.customers.update(customer)
                try addContactIfNeeded(record, to: customer, repositories: repositories)
                result.updated += 1
            }
        }
        return result
    }

    /// Yetkili kişi doluysa kişi ekler (aynı adlı kişi varsa yenisini eklemez, boş telefon/e-postasını doldurur).
    /// Kişi adı yok ama telefon/e-posta varsa firmanın genel iletişimi olarak "Genel" adlı kişi eklenir.
    private static func addContactIfNeeded(_ record: ImportRecord, to customer: Customer, repositories: Repositories) throws {
        guard !record.contact.isEmpty || !record.phone.isEmpty || !record.email.isEmpty else { return }
        let fullName = record.contact.isEmpty ? "Genel" : record.contact
        let existing = try repositories.contacts.contacts(for: customer)
        if let same = existing.first(where: { DistrictCatalog.normalize($0.fullName) == DistrictCatalog.normalize(fullName) }) {
            if same.phone.isEmpty { same.phone = record.phone }
            if same.email.isEmpty { same.email = record.email }
            try repositories.contacts.update(same)
        } else {
            try repositories.contacts.add(
                Contact(fullName: fullName, phone: record.phone, email: record.email), to: customer
            )
        }
    }
}

/// "Örnek CSV şablonu": Türkçe Excel'de doğrudan açılır (UTF-8 + BOM, `;` ayraç).
enum CustomerCSVTemplate {
    static let headers = ["Firma", "Şehir", "İlçe", "OSB", "Sektör", "Adres", "Telefon", "E-posta", "Yetkili kişi"]
    static let sampleRows = [
        ["Örnek Metal Sanayi A.Ş.", "Bursa", "Nilüfer", "Bursa OSB", "Metal işleme", "1. Cadde No: 5", "0555 000 00 10", "info@ornek-metal.example", "Ali Veli"],
        ["Örnek Gıda Ltd. Şti.", "Balıkesir", "Bandırma", "", "Gıda", "", "", "", ""]
    ]

    static var text: String {
        ([headers] + sampleRows).map { $0.map(escape).joined(separator: ";") }.joined(separator: "\r\n") + "\r\n"
    }

    static var data: Data { Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8) }

    /// Paylaşılacak geçici dosya.
    static func writeFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("musteri-sablonu.csv")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == ";" || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
