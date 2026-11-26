import XCTest
@testable import SahaSatis

final class CSVParserTests: XCTestCase {
    func testDetectsSemicolonAndCommaDelimiters() {
        XCTAssertEqual(CSVParser.detectDelimiter("Firma;Şehir;İlçe\nA;B;C"), ";")
        XCTAssertEqual(CSVParser.detectDelimiter("Firma,Şehir,İlçe\nA,B,C"), ",")
        XCTAssertEqual(CSVParser.detectDelimiter("Firma\tŞehir\nA\tB"), "\t")
        XCTAssertEqual(CSVParser.detectDelimiter("Firma"), ";", "Belirsizse Türkçe Excel varsayılanı")
    }

    func testDelimiterInsideQuotesIsIgnoredWhenDetecting() {
        XCTAssertEqual(CSVParser.detectDelimiter("\"Firma, Adı\";Şehir\nA;B"), ";")
    }

    func testParsesQuotedFieldsEscapesAndCRLF() {
        let text = "Firma;Not\r\n\"A; Ltd.\";\"Dedi ki \"\"merhaba\"\"\"\r\n\r\nB;\"iki\nsatır\"\r\n"
        let rows = CSVParser.parse(text, delimiter: ";")
        XCTAssertEqual(rows, [["Firma", "Not"], ["A; Ltd.", "Dedi ki \"merhaba\""], ["B", "iki\nsatır"]])
    }

    func testDecodesUTF8WithBOM() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("Şehir;İlçe".utf8)
        XCTAssertEqual(CSVParser.decode(data), "Şehir;İlçe")
    }

    func testDecodesWindows1254() throws {
        let text = "Şehir;İlçe;Ğ;ı"
        let data = try XCTUnwrap(text.data(using: .windowsCP1254))
        XCTAssertNil(String(data: data, encoding: .utf8), "Geçerli UTF-8 değil")
        XCTAssertEqual(CSVParser.decode(data), text)
    }

    func testSessionFromWindows1254SemicolonFile() throws {
        let csv = "Firma Adı;İl;İlçe\nÇelik Sanayi;Bursa;Nilüfer\n"
        let session = try XCTUnwrap(ImportSession.make(fileName: "x.csv", data: XCTUnwrap(csv.data(using: .windowsCP1254))))
        XCTAssertEqual(session.delimiter, ";")
        XCTAssertEqual(session.rows[1][0], "Çelik Sanayi")
    }

    func testTemplateRoundTrips() throws {
        let session = try XCTUnwrap(ImportSession.make(fileName: "t.csv", data: CustomerCSVTemplate.data))
        XCTAssertEqual(session.headers, CustomerCSVTemplate.headers)
        XCTAssertEqual(session.rows.count, 1 + CustomerCSVTemplate.sampleRows.count)
        XCTAssertEqual(ColumnMapper.autoMap(headers: session.headers).count, ImportField.allCases.count)
    }
}

final class ColumnMapperTests: XCTestCase {
    func testMapsSimilarTurkishHeaders() {
        let headers = ["Firma Adı", "İl", "İlçe", "Organize Sanayi Bölgesi", "Sektör", "Açık Adres", "Telefon No", "E-Posta", "Yetkili Kişi"]
        let map = ColumnMapper.autoMap(headers: headers)
        XCTAssertEqual(map[.name], 0)
        XCTAssertEqual(map[.city], 1)
        XCTAssertEqual(map[.district], 2)
        XCTAssertEqual(map[.zone], 3)
        XCTAssertEqual(map[.sector], 4)
        XCTAssertEqual(map[.address], 5)
        XCTAssertEqual(map[.phone], 6)
        XCTAssertEqual(map[.email], 7)
        XCTAssertEqual(map[.contact], 8)
    }

    func testIsCaseAndCharacterInsensitiveAndLeavesUnknownUnmapped() {
        let map = ColumnMapper.autoMap(headers: ["FIRMA UNVANI", "SEHIR", "Bilinmeyen", "osb"])
        XCTAssertEqual(map[.name], 0)
        XCTAssertEqual(map[.city], 1)
        XCTAssertEqual(map[.zone], 3)
        XCTAssertNil(map[.phone])
    }

    func testEachColumnMapsToOneFieldOnly() {
        let map = ColumnMapper.autoMap(headers: ["Firma", "Firma Adı"])
        XCTAssertEqual(map[.name], 0)
        XCTAssertEqual(Set(map.values).count, map.count)
    }
}

@MainActor
final class CustomerImporterTests: XCTestCase {
    private func records(_ csv: String) -> [ImportRecord] {
        let rows = CSVParser.parse(csv, delimiter: CSVParser.detectDelimiter(csv))
        return CustomerImporter.records(rows: rows, mapping: ColumnMapper.autoMap(headers: rows[0]))
    }

    private let cities = AppSettings.defaultCities

    func testConflictIgnoresCaseAndTurkishCharacters() throws {
        let env = try TestEnv()
        try env.makeCustomer("Örnek Çelik A.Ş.", city: "Bursa")
        let items = CustomerImporter.plan(
            records: records("Firma;Şehir\nORNEK CELIK A.S.;bursa\nÖrnek Çelik A.Ş.;Balıkesir\n"),
            existing: try env.repos.customers.fetchAll(), regionCities: cities
        )
        // "A.Ş." ile "A.S." farklı harfler değil; yalnızca Ş→S ve nokta aynı kaldığı için eşleşir.
        XCTAssertEqual(items[0].outcome, .conflict(existingID: try env.repos.customers.fetchAll()[0].id))
        XCTAssertEqual(items[1].outcome, .add, "Aynı ad başka şehirde çakışma değil")
    }

    func testInvalidRowsAndFileDuplicates() throws {
        let env = try TestEnv()
        let items = CustomerImporter.plan(
            records: records("Firma;Şehir;E-posta\n;Bursa;\nA Ltd.;Bursa;kotu\nB Ltd.;Bursa;b@example.com\nb ltd.;BURSA;\n"),
            existing: [], regionCities: cities
        )
        XCTAssertEqual(items.map(\.outcome), [
            .invalid("Firma adı boş"), .invalid("E-posta geçersiz"), .add, .invalid("Dosyada tekrar")
        ])
        XCTAssertEqual(CustomerImporter.counts(items), ImportCounts(add: 1, conflict: 0, invalid: 3))
        _ = env
    }

    func testApplyAddsProspectsWithRatingContactAndMatchedDistrict() throws {
        let env = try TestEnv()
        let items = CustomerImporter.plan(
            records: records("Firma;İl;İlçe;Yetkili;Telefon\nYeni Döküm;bursa;nilufer;Veli Kaya;0555 000 00 21\nKişisiz;Balıkesir;Orta Mah.;;\n"),
            existing: [], regionCities: cities
        )
        let result = try CustomerImporter.apply(items, policy: .skip, rating: .important, regionCities: cities, repositories: env.repos)
        XCTAssertEqual(result, ImportResult(added: 2, updated: 0, skipped: 0))

        let all = try env.repos.customers.fetchAll()
        let first = try XCTUnwrap(all.first { $0.name == "Yeni Döküm" })
        XCTAssertEqual(first.city, "Bursa")
        XCTAssertEqual(first.district, "Nilüfer")
        XCTAssertEqual(first.status, .potential)
        XCTAssertEqual(first.rating, .important)
        let contacts = try env.repos.contacts.contacts(for: first)
        XCTAssertEqual(contacts.map(\.fullName), ["Veli Kaya"])
        XCTAssertEqual(contacts.first?.phone, "0555 000 00 21")

        let second = try XCTUnwrap(all.first { $0.name == "Kişisiz" })
        XCTAssertEqual(second.district, "Orta Mah.", "Eşleşmeyen ilçe olduğu gibi kalır")
        XCTAssertTrue(try env.repos.contacts.contacts(for: second).isEmpty)
    }

    func testConflictSkipLeavesExistingUntouched() throws {
        let env = try TestEnv()
        let existing = try env.makeCustomer("Örnek A.Ş.", city: "Bursa")
        let items = CustomerImporter.plan(
            records: records("Firma;Şehir;Sektör\nÖrnek A.Ş.;Bursa;Yeni sektör\n"),
            existing: [existing], regionCities: cities
        )
        let result = try CustomerImporter.apply(items, policy: .skip, rating: .weak, regionCities: cities, repositories: env.repos)
        XCTAssertEqual(result, ImportResult(added: 0, updated: 0, skipped: 1))
        XCTAssertEqual(existing.sector, "")
        XCTAssertEqual(try env.repos.customers.fetchAll().count, 1)
    }

    func testConflictUpdateFillsOnlyNonEmptyFieldsAndKeepsStatus() throws {
        let env = try TestEnv()
        let existing = try env.makeCustomer("Örnek A.Ş.", city: "Bursa", status: .current, rating: .important)
        existing.sector = "Eski sektör"
        let items = CustomerImporter.plan(
            records: records("Firma;Şehir;İlçe;Sektör;Yetkili\nörnek a.ş.;Bursa;Nilufer;;Ayşe Demir\n"),
            existing: [existing], regionCities: cities
        )
        let result = try CustomerImporter.apply(items, policy: .update, rating: .weak, regionCities: cities, repositories: env.repos)
        XCTAssertEqual(result, ImportResult(added: 0, updated: 1, skipped: 0))
        XCTAssertEqual(existing.district, "Nilüfer")
        XCTAssertEqual(existing.sector, "Eski sektör", "Boş CSV alanı mevcut değeri silmez")
        XCTAssertEqual(existing.status, .current)
        XCTAssertEqual(existing.rating, .important, "Seçilen değerlendirme yalnızca yeni müşterilere uygulanır")
        XCTAssertEqual(try env.repos.contacts.contacts(for: existing).map(\.fullName), ["Ayşe Demir"])
    }

    func testPhoneWithoutContactNameCreatesGeneralContact() throws {
        let env = try TestEnv()
        let items = CustomerImporter.plan(records: records("Firma;Şehir;Telefon\nX Ltd.;Bursa;0555 000 00 99\n"), existing: [], regionCities: cities)
        try CustomerImporter.apply(items, policy: .skip, rating: .promising, regionCities: cities, repositories: env.repos)
        let customer = try XCTUnwrap(try env.repos.customers.fetchAll().first)
        XCTAssertEqual(try env.repos.contacts.contacts(for: customer).map(\.fullName), ["Genel"])
    }
}
