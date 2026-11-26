import XCTest
@testable import SahaSatis

/// Kartvizit ayrıştırma kuralları (hayali örnek kartvizit metinleri; numara ve adresler uydurmadır).
final class BusinessCardParserTests: XCTestCase {
    private let cities = ["Bursa", "Balıkesir", "Eskişehir"]

    private func parse(_ text: String) -> BusinessCardFields {
        BusinessCardParser.parse(text: text, cities: cities)
    }

    func testFullTurkishCard() {
        let fields = parse("""
        ÖRNEK MAKİNA SAN. VE TİC. A.Ş.
        ZEYNEP KARACA
        Satın Alma Uzmanı
        Tel: +90 224 000 00 10
        GSM: +90 532 000 00 11
        zeynep.karaca@example.com
        www.example.com
        Örnek OSB Mah. 1. Cad. No: 5
        16140 Nilüfer / BURSA
        """)
        XCTAssertEqual(fields.company, "ÖRNEK MAKİNA SAN. VE TİC. A.Ş.")
        XCTAssertEqual(fields.fullName, "Zeynep Karaca")
        XCTAssertEqual(fields.title, "Satın Alma Uzmanı")
        XCTAssertEqual(fields.phone, "+90 532 000 00 11", "Cep numarası tercih edilir")
        XCTAssertEqual(fields.otherPhones, ["+90 224 000 00 10"])
        XCTAssertEqual(fields.email, "zeynep.karaca@example.com")
        XCTAssertEqual(fields.website, "www.example.com")
        XCTAssertEqual(fields.address, "Örnek OSB Mah. 1. Cad. No: 5, 16140 Nilüfer / BURSA")
        XCTAssertEqual(fields.city, "Bursa")
        XCTAssertEqual(fields.district, "Nilüfer")
    }

    func testLtdCompanyAndManagerTitle() {
        let fields = parse("""
        Hayal Otomasyon Ltd. Şti.
        Deniz Aydın
        Bakım Müdürü
        M: 0533 000 00 22
        deniz.aydin@example.org
        """)
        XCTAssertEqual(fields.company, "Hayal Otomasyon Ltd. Şti.")
        XCTAssertEqual(fields.fullName, "Deniz Aydın")
        XCTAssertEqual(fields.title, "Bakım Müdürü")
        XCTAssertEqual(fields.phone, "0533 000 00 22")
        XCTAssertEqual(fields.email, "deniz.aydin@example.org")
        XCTAssertEqual(fields.address, "")
    }

    func testEmailLabelIsNotTreatedAsAddress() {
        let fields = parse("""
        Ali Veli
        E-posta: ALI.VELI@Example.com
        """)
        XCTAssertEqual(fields.email, "ali.veli@example.com")
        XCTAssertEqual(fields.address, "")
        XCTAssertEqual(fields.fullName, "Ali Veli")
    }

    func testFaxIsNotUsedAsPhone() {
        let fields = parse("""
        Ece Demir
        Faks: 0224 000 00 31
        Tel: 0224 000 00 30
        """)
        XCTAssertEqual(fields.phone, "0224 000 00 30")
        XCTAssertEqual(fields.otherPhones, [])
    }

    func testTitleKeywords() {
        for title in ["Satış Mühendisi", "Üretim Sorumlusu", "Planlama Uzmanı", "Bakım Şefi", "Genel Müdür Yardımcısı", "Sales Manager"] {
            let fields = parse("""
            Can Yıldız
            \(title)
            """)
            XCTAssertEqual(fields.title, title)
            XCTAssertEqual(fields.fullName, "Can Yıldız", title)
        }
    }

    func testCompanyMarkers() {
        for company in ["Deneme Metal Sanayi", "Deneme Gıda Tic. Ltd. Şti.", "DENEME PLASTİK A. Ş.", "Deneme San. ve Tic."] {
            let fields = parse("""
            Can Yıldız
            \(company)
            """)
            XCTAssertEqual(fields.company, company)
            XCTAssertEqual(fields.fullName, "Can Yıldız", company)
        }
    }

    /// "Mühendislik" firma sözcüğüdür, unvan değildir.
    func testEngineeringCompanyIsNotATitle() {
        let fields = parse("""
        Deneme Mühendislik
        Seda Kurt
        Proje Mühendisi
        """)
        XCTAssertEqual(fields.company, "Deneme Mühendislik")
        XCTAssertEqual(fields.fullName, "Seda Kurt")
        XCTAssertEqual(fields.title, "Proje Mühendisi")
    }

    /// Firmada işaret sözcüğü yoksa: unvanın üstündeki satır ad, öteki ad biçimli satır firma sayılır.
    func testCompanyWithoutMarkerUsesRemainingLine() {
        let fields = parse("""
        Mavi Deniz
        Kerem Aksoy
        Satış Uzmanı
        """)
        XCTAssertEqual(fields.fullName, "Kerem Aksoy")
        XCTAssertEqual(fields.company, "Mavi Deniz")
    }

    func testSeparatorsSplitOneLine() {
        let fields = parse("Seda Kurt | Proje Mühendisi")
        XCTAssertEqual(fields.fullName, "Seda Kurt")
        XCTAssertEqual(fields.title, "Proje Mühendisi")
    }

    func testEmptyText() {
        XCTAssertEqual(parse(""), BusinessCardFields())
    }

    func testMobileDetection() {
        XCTAssertTrue(BusinessCardParser.isMobile("0532 000 00 11"))
        XCTAssertTrue(BusinessCardParser.isMobile("+90 (532) 000 00 11"))
        XCTAssertFalse(BusinessCardParser.isMobile("0224 000 00 10"))
    }

    func testLocationDetectionPrefersLastCity() {
        let location = BusinessCardParser.detectLocation(in: "Balıkesir Cad. No: 1 Nilufer Bursa", cities: cities)
        XCTAssertEqual(location.city, "Bursa")
        XCTAssertEqual(location.district, "Nilüfer")
    }
}

@MainActor
final class BusinessCardMatcherTests: XCTestCase {
    func testMatchingIgnoresCaseAndTurkishCharacters() throws {
        let env = try TestEnv()
        let customer = try env.makeCustomer("Örnek Makina A.Ş.")
        try env.makeCustomer("Başka Firma Ltd. Şti.")
        let all = try env.repos.customers.fetchAll()

        for company in ["ÖRNEK MAKİNA A.Ş.", "ornek makina a.s.", "ÖRNEK MAKİNA SAN. VE TİC. A.Ş.", "Örnek Makina"] {
            XCTAssertEqual(BusinessCardMatcher.match(company: company, in: all)?.id, customer.id, company)
        }
    }

    func testNoMatch() throws {
        let env = try TestEnv()
        try env.makeCustomer("Örnek Makina A.Ş.")
        let all = try env.repos.customers.fetchAll()
        XCTAssertNil(BusinessCardMatcher.match(company: "Hayal Otomasyon Ltd. Şti.", in: all))
        XCTAssertNil(BusinessCardMatcher.match(company: "", in: all))
        XCTAssertNil(BusinessCardMatcher.match(company: "A.Ş.", in: all))
    }

    func testCustomerDraftIsPrefilledAsProspect() {
        var fields = BusinessCardFields()
        fields.company = " Hayal Otomasyon Ltd. Şti. "
        fields.website = "www.example.org"
        fields.address = "Deneme Sok. No: 8"
        fields.city = "Bursa"
        fields.district = "Osmangazi"
        let draft = BusinessCardImport.customerDraft(from: fields)
        XCTAssertEqual(draft.name, "Hayal Otomasyon Ltd. Şti.")
        XCTAssertEqual(draft.status, .potential)
        XCTAssertEqual(draft.city, "Bursa")
        XCTAssertEqual(draft.district, "Osmangazi")
        XCTAssertEqual(draft.address, "Deneme Sok. No: 8")
        XCTAssertEqual(draft.notes, "Web: www.example.org")
    }

    func testContactFromFields() throws {
        var fields = BusinessCardFields()
        XCTAssertNil(BusinessCardImport.contact(from: fields, includeWebsite: true))
        fields.fullName = "Deniz Aydın"
        fields.title = "Bakım Müdürü"
        fields.phone = "0533 000 00 22"
        fields.otherPhones = ["0224 000 00 10"]
        fields.website = "www.example.org"

        let env = try TestEnv()
        let customer = try env.makeCustomer()
        let contact = try XCTUnwrap(BusinessCardImport.contact(from: fields, includeWebsite: true))
        try env.repos.contacts.add(contact, to: customer)

        let saved = try XCTUnwrap(try env.repos.contacts.contacts(for: customer).first)
        XCTAssertEqual(saved.fullName, "Deniz Aydın")
        XCTAssertEqual(saved.title, "Bakım Müdürü")
        XCTAssertEqual(saved.phone, "0533 000 00 22")
        XCTAssertEqual(saved.notes, "Diğer telefon: 0224 000 00 10\nWeb: www.example.org")
    }
}
