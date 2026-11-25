import Foundation

/// Sorumlu bölgedeki şehirlerin resmi ilçe listeleri (uygulamaya gömülü) ve ilçe adı eşleştirme.
/// Listede olmayan şehirlerde (kullanıcının sonradan eklediği) ilçe serbest metindir.
///
/// Merkez ilçesi "Merkez" adını taşıyan şehirlerde (Çanakkale, Bilecik, Yalova, Kütahya, Afyonkarahisar) listede
/// "Merkez" yazar; büyükşehirlerde (Balıkesir, Bursa) ve Eskişehir'de merkez ilçeler adlarıyla yer alır.
enum DistrictCatalog {
    /// Şehir (resmi yazım) → ilçeler (Türkçe alfabetik).
    static let byCity: [String: [String]] = [
        "Çanakkale": [
            "Ayvacık", "Bayramiç", "Biga", "Bozcaada", "Çan", "Eceabat", "Ezine", "Gelibolu", "Gökçeada",
            "Lapseki", "Merkez", "Yenice"
        ],
        "Balıkesir": [
            "Altıeylül", "Ayvalık", "Balya", "Bandırma", "Bigadiç", "Burhaniye", "Dursunbey", "Edremit", "Erdek",
            "Gömeç", "Gönen", "Havran", "İvrindi", "Karesi", "Kepsut", "Manyas", "Marmara", "Savaştepe",
            "Sındırgı", "Susurluk"
        ],
        "Bursa": [
            "Büyükorhan", "Gemlik", "Gürsu", "Harmancık", "İnegöl", "İznik", "Karacabey", "Keles", "Kestel",
            "Mudanya", "Mustafakemalpaşa", "Nilüfer", "Orhaneli", "Orhangazi", "Osmangazi", "Yenişehir", "Yıldırım"
        ],
        "Bilecik": [
            "Bozüyük", "Gölpazarı", "İnhisar", "Merkez", "Osmaneli", "Pazaryeri", "Söğüt", "Yenipazar"
        ],
        "Yalova": [
            "Altınova", "Armutlu", "Çınarcık", "Çiftlikköy", "Merkez", "Termal"
        ],
        "Eskişehir": [
            "Alpu", "Beylikova", "Çifteler", "Günyüzü", "Han", "İnönü", "Mahmudiye", "Mihalgazi", "Mihalıççık",
            "Odunpazarı", "Sarıcakaya", "Seyitgazi", "Sivrihisar", "Tepebaşı"
        ],
        "Kütahya": [
            "Altıntaş", "Aslanapa", "Çavdarhisar", "Domaniç", "Dumlupınar", "Emet", "Gediz", "Hisarcık", "Merkez",
            "Pazarlar", "Simav", "Şaphane", "Tavşanlı"
        ],
        "Afyonkarahisar": [
            "Başmakçı", "Bayat", "Bolvadin", "Çay", "Çobanlar", "Dazkırı", "Dinar", "Emirdağ", "Evciler", "Hocalar",
            "İhsaniye", "İscehisar", "Kızılören", "Merkez", "Sandıklı", "Sinanpaşa", "Sultandağı", "Şuhut"
        ]
    ]

    /// Şehrin bilinen kısa yazımları → resmi ad.
    private static let cityAliases: [String: String] = ["afyon": "Afyonkarahisar"]

    private static let turkish = Locale(identifier: "tr_TR")

    /// Büyük/küçük harf, Türkçe karakter (ı/i, ğ, ü, ş, ö, ç) ve aksan duyarsız karşılaştırma anahtarı:
    /// "Nilufer", "NİLÜFER", " nilüfer " → "nilufer"; "Çınarcık" ve "Cinarcik" → "cinarcik".
    static func normalize(_ text: String) -> String {
        var lowered = text.lowercased(with: turkish)
        for (from, to) in [("ı", "i"), ("ğ", "g"), ("ü", "u"), ("ş", "s"), ("ö", "o"), ("ç", "c")] {
            lowered = lowered.replacingOccurrences(of: from, with: to)
        }
        let folded = lowered.folding(options: .diacriticInsensitive, locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Şehrin resmi adı (katalogdaki yazım); katalogda yoksa nil.
    static func canonicalCity(_ city: String) -> String? {
        let key = normalize(city)
        if let alias = cityAliases[key] { return alias }
        return byCity.keys.first { normalize($0) == key }
    }

    /// Şehrin ilçe listesi; şehir katalogda yoksa nil (ilçe serbest metin).
    static func districts(forCity city: String) -> [String]? {
        canonicalCity(city).flatMap { byCity[$0] }
    }

    /// Yazılan ilçeyi şehrin listesindeki resmi yazımla eşleştirir ("Nilufer" → "Nilüfer"). Şehir katalogda yoksa
    /// veya eşleşme yoksa nil.
    static func match(_ district: String, city: String) -> String? {
        let key = normalize(district)
        guard !key.isEmpty, let list = districts(forCity: city) else { return nil }
        return list.first { normalize($0) == key }
    }

    /// Gösterim/gruplama için ilçe adı: eşleşirse resmi yazım, aksi halde yazıldığı gibi (kenarları kırpılmış).
    static func displayName(_ district: String, city: String) -> String {
        let trimmed = district.trimmingCharacters(in: .whitespacesAndNewlines)
        return match(trimmed, city: city) ?? trimmed
    }
}

/// Mevcut müşteri kayıtlarındaki ilçe değerlerini şehrin resmi listesiyle eşleştirir. Eşleşmeyenler olduğu gibi kalır.
/// Tekrar çalıştırmak zararsızdır (yalnızca farklı yazılmış değerler değişir).
@MainActor
enum DistrictMigration {
    /// - Returns: Güncellenen müşteri sayısı.
    @discardableResult
    static func run(customers repository: CustomerRepository) throws -> Int {
        var changed = 0
        for customer in try repository.fetchAll() {
            guard let official = DistrictCatalog.match(customer.district, city: customer.city),
                  official != customer.district else { continue }
            customer.district = official
            try repository.update(customer)
            changed += 1
        }
        return changed
    }
}
