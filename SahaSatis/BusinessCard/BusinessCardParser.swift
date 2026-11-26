import Foundation

/// Kartvizit metninden çıkarılan alanlar (hepsi düzeltilebilir tahmindir).
struct BusinessCardFields: Equatable {
    var fullName = ""
    var title = ""
    var company = ""
    /// Asıl telefon (cep numarası varsa o, yoksa ilk faks olmayan numara).
    var phone = ""
    /// Faks olmayan diğer telefonlar.
    var otherPhones: [String] = []
    var email = ""
    var website = ""
    var address = ""
    /// Adresten tahmin edilen şehir/ilçe (bölge listesi + gömülü ilçe kataloğu); bulunamazsa boş.
    var city = ""
    var district = ""
}

/// Kartvizit metnini (OCR satırları) alanlara ayıran kural tabanlı ayrıştırıcı. Saf mantık; kamera/Vision'a bağlı değildir.
///
/// Telefon ve web adresi `NSDataDetector` ile, e-posta düzenli ifadeyle bulunur. Kalan satırlar anahtar sözcüklerle
/// sınıflandırılır: A.Ş./Ltd. Şti./San./Tic. gibi ifadeler firmayı, Müdür/Mühendis/Sorumlu/Uzman/Şef gibi ifadeler unvanı,
/// Mah./Sok./Cad./No: gibi ifadeler adresi işaret eder; kalan "Ad Soyad" biçimli satır kişi adıdır.
enum BusinessCardParser {
    static func parse(text: String, cities: [String] = []) -> BusinessCardFields {
        parse(lines: text.components(separatedBy: .newlines), cities: cities)
    }

    static func parse(lines rawLines: [String], cities: [String] = []) -> BusinessCardFields {
        var fields = BusinessCardFields()
        var phones: [(number: String, isFax: Bool)] = []
        var addressLines: [String] = []
        var candidates: [(text: String, role: Role)] = []

        for line in prepare(rawLines) {
            var work = line

            // E-posta
            let emailRanges = ranges(of: emailRegex, in: work)
            if let first = emailRanges.first, fields.email.isEmpty {
                fields.email = (work as NSString).substring(with: first).lowercased()
            }
            work = blank(work, ranges: emailRanges)

            // Web adresi
            let webRanges = webMatches(in: work)
            if let first = webRanges.first, fields.website.isEmpty {
                fields.website = cleanWebsite((work as NSString).substring(with: first))
            }
            work = blank(work, ranges: webRanges)

            // Adres satırındaki rakamlar telefon sanılmasın. (Etiketler atılır: "E-posta" içindeki "posta" adres sayılmasın;
            // yalnızca harf içeren satırlar adres olabilir: "Tel: 0224 12345" posta kodu sayılmasın.)
            let labelFree = stripLabels(work)
            if labelFree.filter(\.isLetter).count >= 3, isStrongAddress(labelFree, cities: cities) {
                addressLines.append(cleanAddress(work))
                continue
            }

            // Telefon
            let phoneMatches = phoneDetector?
                .matches(in: work, options: [], range: fullRange(work))
                .filter { $0.resultType == .phoneNumber } ?? []
            var previousEnd = 0
            var phoneRanges: [NSRange] = []
            for match in phoneMatches {
                let ns = work as NSString
                let number = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
                let digits = number.filter(\.isNumber).count
                guard (7...15).contains(digits) else { continue }
                let labelStart = min(previousEnd, match.range.location)
                let label = ns.substring(with: NSRange(location: labelStart, length: match.range.location - labelStart))
                phones.append((number, hasFaxLabel(label)))
                phoneRanges.append(match.range)
                previousEnd = match.range.location + match.range.length
            }
            work = blank(work, ranges: phoneRanges)

            let detected = work != line
            let remainder = detected ? stripLabels(work) : line
            guard remainder.filter(\.isLetter).count >= 3 else { continue }

            let role = classify(remainder, cities: cities)
            if role == .address {
                addressLines.append(cleanAddress(remainder))
            } else {
                candidates.append((remainder, role))
            }
        }

        // Telefonlar
        let callable = phones.filter { !$0.isFax }.map(\.number)
        let primary = callable.first { isMobile($0) } ?? callable.first ?? ""
        fields.phone = primary
        fields.otherPhones = callable.filter { $0 != primary }

        // Unvan
        fields.title = candidates.first { $0.role == .title }?.text ?? ""

        // Kişi adı: unvanın hemen üstündeki ad biçimli satır; unvan yoksa ilk ad biçimli satır.
        let nameLike = candidates.indices.filter { candidates[$0].role == .nameLike }
        var nameIndex: Int?
        if let titleIndex = candidates.firstIndex(where: { $0.role == .title }) {
            let before = nameLike.last(where: { $0 < titleIndex })
            nameIndex = before ?? nameLike.first(where: { $0 > titleIndex })
        } else {
            nameIndex = nameLike.first
        }
        if let nameIndex { fields.fullName = properCase(candidates[nameIndex].text) }

        // Firma: yasal ek (A.Ş. vb.) > sektör sözcüğü > ad seçilmeyen ad biçimli satır > diğer satır.
        var companyText = candidates.first(where: { $0.role == .strongCompany })?.text
        if companyText == nil { companyText = candidates.first(where: { $0.role == .weakCompany })?.text }
        if companyText == nil {
            let spare = candidates.indices.first(where: { candidates[$0].role == .nameLike && $0 != nameIndex })
            companyText = spare.map { candidates[$0].text }
        }
        if companyText == nil { companyText = candidates.first(where: { $0.role == .other })?.text }
        fields.company = companyText ?? ""

        // Adres + şehir/ilçe tahmini
        fields.address = addressLines.joined(separator: ", ")
        let location = detectLocation(in: fields.address, cities: cities)
        fields.city = location.city
        fields.district = location.district
        return fields
    }

    // MARK: - Satır sınıflandırma

    private enum Role {
        case address, strongCompany, title, weakCompany, nameLike, other
    }

    private static func classify(_ line: String, cities: [String]) -> Role {
        let tokens = tokenize(line)
        if isStrongAddress(line, cities: cities) { return .address }
        if hasLegalSuffix(tokens) { return .strongCompany }
        if isWeakAddress(tokens) { return .address }
        if hasTradeMarker(line, tokens) { return .strongCompany }
        if isTitle(tokens) { return .title }
        if line.contains(where: \.isNumber), looksLikeAddressByDetector(line) { return .address }
        if tokens.contains(where: { weakCompanyWords.contains($0) }) { return .weakCompany }
        if isNameLike(line) { return .nameLike }
        return .other
    }

    private static let strongAddressWords: Set<String> = [
        "mah", "mahallesi", "mahalle", "sok", "sokak", "sk", "cad", "cadde", "cd", "bulvar", "bulvari", "blv",
        "no", "kat", "apt", "apartmani", "daire", "posta", "pk", "blok"
    ]

    private static let legalWords: Set<String> = [
        "as", "ltd", "sti", "limited", "sirketi", "anonim", "holding", "inc", "gmbh", "llc", "corp"
    ]

    private static let weakCompanyWords: Set<String> = [
        "otomasyon", "makina", "makine", "makinalari", "elektrik", "elektronik", "muhendislik", "insaat", "grup", "group",
        "teknoloji", "teknolojileri", "sistemleri", "sistem", "endustri", "endustriyel", "gida", "tekstil", "plastik",
        "metal", "enerji", "otomotiv", "mekatronik", "hidrolik", "pnomatik", "kalip", "yazilim", "lojistik", "yapi",
        "madencilik", "kimya", "ambalaj"
    ]

    private static let titleStems: [String] = [
        "mudur", "muhendis", "sorumlu", "uzman", "sef", "yonetici", "direktor", "koordinator", "teknisyen",
        "temsilci", "danisman", "baskan", "muhasebeci", "operator", "yardimci",
        "manager", "engineer", "director", "specialist", "supervisor", "chief", "executive", "officer",
        "representative", "technician", "coordinator", "consultant", "president", "ceo", "cto", "cfo"
    ]
    private static let titleSuffixes = ["", "i", "u", "si", "su", "lari", "leri"]

    /// Küçük harf, Türkçe karakter ve noktalama duyarsız sözcükler ("A.Ş." → ["a", "s"]).
    private static func tokenize(_ line: String) -> [String] {
        DistrictCatalog.normalize(line.replacingOccurrences(of: ".", with: " "))
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func hasLegalSuffix(_ tokens: [String]) -> Bool {
        if tokens.contains(where: { legalWords.contains($0) }) { return true }
        // "A. Ş." / "A.Ş." → ardışık "a", "s"
        for index in tokens.indices.dropLast() where tokens[index] == "a" && tokens[index + 1] == "s" { return true }
        return false
    }

    /// "Sanayi", "Ticaret" açık işaretlerdir; "San." / "Tic." kısaltmaları soyadla karışabileceği için yalnızca noktalı
    /// yazıldıklarında ya da satır en az 3 sözcükse sayılır.
    private static func hasTradeMarker(_ line: String, _ tokens: [String]) -> Bool {
        if tokens.contains("sanayi") || tokens.contains("sanayii") || tokens.contains("ticaret") { return true }
        guard tokens.contains("san") || tokens.contains("tic") else { return false }
        return tokens.count >= 3 || line.range(of: "(?i)\\b(san|tic)\\.", options: .regularExpression) != nil
    }

    private static func isStrongAddress(_ line: String, cities: [String]) -> Bool {
        let tokens = tokenize(line)
        if tokens.contains(where: { strongAddressWords.contains($0) }) { return true }
        if line.range(of: "\\b\\d{5}\\b", options: .regularExpression) != nil { return true }
        if line.contains("/"), tokens.contains(where: { isKnownCity($0, cities: cities) }) { return true }
        return false
    }

    private static func isWeakAddress(_ tokens: [String]) -> Bool {
        tokens.contains("osb") || tokens.contains("organize") || tokens.contains("sitesi")
            || tokens.contains("bolgesi") || tokens.contains("mevkii") || tokens.contains("mevki")
    }

    private static func isTitle(_ tokens: [String]) -> Bool {
        tokens.contains { token in
            titleStems.contains { stem in titleSuffixes.contains { token == stem + $0 } }
        }
    }

    private static func isKnownCity(_ normalizedToken: String, cities: [String]) -> Bool {
        if DistrictCatalog.canonicalCity(normalizedToken) != nil { return true }
        return cities.contains { DistrictCatalog.normalize($0) == normalizedToken }
    }

    /// "Ad Soyad" biçimi: 2–4 sözcük, her biri büyük harfle başlar, rakam yok.
    private static func isNameLike(_ line: String) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        guard (2...4).contains(words.count) else { return false }
        guard line.filter(\.isLetter).count >= 4 else { return false }
        for word in words {
            guard let first = word.first, first.isLetter, first.isUppercase else { return false }
            let allowed = word.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" || $0 == "'" || $0 == "’" }
            if !allowed { return false }
        }
        return true
    }

    private static func properCase(_ name: String) -> String {
        let turkish = Locale(identifier: "tr_TR")
        let letters = name.filter(\.isLetter)
        guard !letters.isEmpty, name == name.uppercased(with: turkish) else { return name }
        return name.lowercased(with: turkish).capitalized(with: turkish)
    }

    // MARK: - Telefon

    private static func hasFaxLabel(_ label: String) -> Bool {
        let lower = label.lowercased()
        if lower.contains("fax") || lower.contains("faks") { return true }
        return lower.range(of: "(^|\\s)f\\s*[:.]?\\s*$", options: .regularExpression) != nil
    }

    /// Türkiye cep numarası: 5XX ile başlayan 10 hane (0 veya 90 önekiyle).
    static func isMobile(_ number: String) -> Bool {
        var digits = number.filter(\.isNumber)
        if digits.count == 12, digits.hasPrefix("90") { digits.removeFirst(2) }
        if digits.count == 11, digits.hasPrefix("0") { digits.removeFirst() }
        return digits.count == 10 && digits.hasPrefix("5")
    }

    // MARK: - Web

    private static func webMatches(in text: String) -> [NSRange] {
        let ns = text as NSString
        var found = (linkDetector?.matches(in: text, options: [], range: fullRange(text)) ?? [])
            .filter { $0.resultType == .link }
            .map(\.range)
            .filter { looksLikeWeb(ns.substring(with: $0)) }
        if found.isEmpty {
            found = ranges(of: wwwRegex, in: text)
        }
        return found
    }

    private static func looksLikeWeb(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("@") { return false }
        if lower.contains("www.") || lower.hasPrefix("http") { return true }
        return lower.range(
            of: "\\.(com|net|org|biz|info|eu|io|tr|de)(\\.[a-z]{2})?(/.*)?$", options: .regularExpression
        ) != nil
    }

    private static func cleanWebsite(_ raw: String) -> String {
        var site = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:|"))
        for prefix in ["https://", "http://"] where site.lowercased().hasPrefix(prefix) {
            site.removeFirst(prefix.count)
        }
        while site.hasSuffix("/") { site.removeLast() }
        return site
    }

    // MARK: - Adres

    private static func cleanAddress(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "(?i)^(adres|address|adr)\\s*[:.]\\s*", options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;|"))
    }

    private static func looksLikeAddressByDetector(_ line: String) -> Bool {
        guard let matches = addressDetector?.matches(in: line, options: [], range: fullRange(line)) else { return false }
        return matches.contains { $0.resultType == .address }
    }

    /// Adres metninden şehir (son geçen) ve o şehre ait ilçe tahmini.
    static func detectLocation(in address: String, cities: [String]) -> (city: String, district: String) {
        let words = address.split(whereSeparator: { !$0.isLetter }).map(String.init)
        var city = ""
        for word in words {
            if let official = DistrictCatalog.canonicalCity(word) {
                city = official
            } else if let own = cities.first(where: { DistrictCatalog.normalize($0) == DistrictCatalog.normalize(word) }) {
                city = own
            }
        }
        var district = ""
        if !city.isEmpty {
            for word in words {
                if let official = DistrictCatalog.match(word, city: city) { district = official }
            }
        }
        return (city, district)
    }

    // MARK: - Metin yardımcıları

    /// Satırları kırpar, "|" ve "•" ile ayrılmış parçaları ayrı satır yapar, boşları atar.
    private static func prepare(_ rawLines: [String]) -> [String] {
        rawLines
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: "|•")) }
            .map { $0.replacingOccurrences(of: "\t", with: " ") }
            .map { $0.split(whereSeparator: { $0 == " " }).joined(separator: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// "Tel:", "Mobil", "E-posta", "T:" gibi etiketleri ve baştaki/sondaki işaretleri atar.
    private static func stripLabels(_ text: String) -> String {
        var result = text
        let patterns = [
            "(?i)\\b(tel|telefon|gsm|mobil|mobile|cep|faks|fax|e-?posta|e-?mail|mail|web|website|www|phone)\\b\\.?\\s*:?",
            "(?i)(^|\\s)[tmfew]\\s*[:.]\\s*"
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return result
            .split(separator: " ").joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-|/•·,;.\t"))
    }

    private static func fullRange(_ text: String) -> NSRange {
        NSRange(location: 0, length: (text as NSString).length)
    }

    private static func ranges(of regex: NSRegularExpression, in text: String) -> [NSRange] {
        regex.matches(in: text, options: [], range: fullRange(text)).map(\.range)
    }

    private static func blank(_ text: String, ranges: [NSRange]) -> String {
        var result = text
        for range in ranges.sorted(by: { $0.location > $1.location }) {
            result = (result as NSString).replacingCharacters(in: range, with: " ")
        }
        return result
    }

    // MARK: - Düzenli ifadeler ve dedektörler

    private static let emailRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "[A-Za-z0-9._%+\\-]+@[A-Za-z0-9\\-]+(?:\\.[A-Za-z0-9\\-]+)*\\.[A-Za-z]{2,}")
    }()

    private static let wwwRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: "(?i)\\bwww\\.[a-z0-9\\-]+(?:\\.[a-z0-9\\-]+)+(?:/\\S*)?")
    }()

    private static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let addressDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
}

/// Kartvizitteki firmayı mevcut müşterilerle eşleştirir (büyük/küçük harf ve Türkçe karakter duyarsız).
enum BusinessCardMatcher {
    /// Karşılaştırmada atılan yasal ek / bağlaç sözcükleri ("Örnek Makina San. ve Tic. A.Ş." ≈ "Örnek Makina").
    private static let legalTokens: Set<String> = [
        "as", "ltd", "sti", "san", "tic", "limited", "sirketi", "anonim", "sanayi", "sanayii", "ticaret", "ve", "a", "s"
    ]

    static func key(_ company: String) -> String {
        DistrictCatalog.normalize(company.replacingOccurrences(of: ".", with: " "))
    }

    /// Yasal ekler atılmış anahtar.
    static func coreKey(_ company: String) -> String {
        key(company)
            .split(separator: " ")
            .map(String.init)
            .filter { !legalTokens.contains($0) }
            .joined(separator: " ")
    }

    /// Önce tam (normalize) eşleşme, sonra yasal eksiz eşleşme. Firma adı boşsa nil.
    static func match(company: String, in customers: [Customer]) -> Customer? {
        let exact = key(company)
        guard !exact.isEmpty else { return nil }
        if let found = customers.first(where: { key($0.name) == exact }) { return found }
        let core = coreKey(company)
        guard !core.isEmpty else { return nil }
        return customers.first { coreKey($0.name) == core }
    }
}
