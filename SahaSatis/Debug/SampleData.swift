#if DEBUG
import Foundation

/// Yalnızca test/DEBUG için HAYALİ örnek veri. Gerçek müşteri verisi asla buraya konmaz (repo public).
enum SampleData {
    static let showcaseName = "Örnek Makina A.Ş."

    @MainActor
    static func load(into repositories: Repositories) throws {
        let now = Date()
        func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        // 1) Önemli, mevcut, kurulu bazında üretimi duran ürün var (Migrasyon fırsatı)
        let ornek = Customer(
            name: showcaseName, city: "Bursa", district: "Nilüfer", industrialZone: "Bursa OSB",
            sector: "Makine imalatı", address: "1. Cadde No: 12 Nilüfer / Bursa",
            status: .current, rating: .important,
            ratingNote: "Hat 3 PLC yenilemesi var; yıllık bakım sözleşmesi potansiyeli yüksek.",
            notes: "Satın alma her ayın ilk haftası toplanıyor. Fabrikada çekim zayıf."
        )
        try repositories.customers.add(ornek)
        let ahmet = Contact(fullName: "Ahmet Yılmaz", title: "Bakım Müdürü", phone: "0555 000 00 01", email: "ahmet@example.com")
        let ayse = Contact(fullName: "Ayşe Demir", title: "Satın Alma", phone: "0555 000 00 02", email: "ayse@example.com")
        try repositories.contacts.add(ahmet, to: ornek)
        try repositories.contacts.add(ayse, to: ornek)
        try repositories.installedProducts.add(InstalledProduct(catalogNumber: "1756-L71", productFamily: "ControlLogix", quantity: 2), to: ornek)
        try repositories.installedProducts.add(InstalledProduct(catalogNumber: "PLC-5/40", productFamily: "PLC-5", quantity: 2, lifecycleStatus: .discontinued, notes: "Hat 3 panosunda; yedek parça bulmak zor."), to: ornek)
        try repositories.installedProducts.add(InstalledProduct(catalogNumber: "1747-L542", productFamily: "SLC 500", quantity: 3, lifecycleStatus: .endOfLife, notes: "Hat 2"), to: ornek)

        // Fırsatlar (hayali). İlk fırsatın başlığı `PipelineView`'daki ekran görüntüsü senaryosuyla eşleşmeli.
        func inDays(_ days: Double) -> Date { now.addingTimeInterval(days * 86_400) }
        let hat3 = Opportunity(
            title: "Hat 3 PLC yenileme", details: "Eski PLC-5 tabanlı hattın ControlLogix'e taşınması; işlemci, G/Ç ve HMI.",
            estimatedValue: 480_000, currency: .tl, stage: .quoted, expectedCloseDate: inDays(12)
        )
        try repositories.opportunities.add(hat3, customer: ornek)
        let bakim = Opportunity(
            title: "Bakım sözleşmesi yenileme", estimatedValue: 120_000, currency: .tl, stage: .negotiation, expectedCloseDate: inDays(20)
        )
        try repositories.opportunities.add(bakim, customer: ornek)
        let yedekParca = Opportunity(
            title: "Yedek parça paketi", estimatedValue: 36_000, currency: .tl, stage: .won, expectedCloseDate: inDays(-9)
        )
        try repositories.opportunities.add(yedekParca, customer: ornek)

        // Ziyaret geçmişi (VisitService: sonraki adım tarihi olan ziyaret bağlı takip görevi üretir)
        let visitService = VisitService(repositories: repositories, reminderMinutes: 9 * 60)
        try visitService.save(
            VisitDraft(
                date: daysAgo(80), type: .visit,
                topic: "Bakım sözleşmesi tanıtımı",
                summary: "Yıllık bakım sözleşmesi tanıtıldı. Satın alma süreci ve onay adımları anlatıldı.",
                nextStep: "Bakım sözleşmesi örneği gönderilecek"
            ),
            customer: ornek, contacts: [ayse], existing: nil
        )
        try visitService.save(
            VisitDraft(
                date: daysAgo(34), type: .phone,
                topic: "Yedek parça stoğu",
                summary: "Yedek parça stok durumu soruldu; fiyat listesi e-postayla gönderildi."
            ),
            customer: ornek, contacts: [ahmet], existing: nil
        )
        try visitService.save(
            VisitDraft(
                date: daysAgo(12), type: .visit,
                topic: "Hat 3 PLC yenileme",
                summary: "Hat 3 PLC yenilemesi görüşüldü. Eski denetleyicilerin yedek parça sorunu var; teklif istediler.",
                nextStep: "Hat 3 için teklif hazırlanacak",
                nextStepDate: now.addingTimeInterval(3 * 86_400)
            ),
            customer: ornek, contacts: [ahmet, ayse], opportunity: hat3, existing: nil
        )

        // 2) Potansiyelli, aday müşteri
        let gida = Customer(
            name: "Marmara Gıda San. Tic. Ltd. Şti.", city: "Balıkesir", district: "Bandırma",
            sector: "Gıda", status: .potential, rating: .promising,
            ratingNote: "Yeni dolum hattı yatırımı planlıyorlar."
        )
        try repositories.customers.add(gida)
        try repositories.opportunities.add(
            Opportunity(title: "Dolum hattı otomasyonu", estimatedValue: 12_500, currency: .usd, stage: .qualified, expectedCloseDate: inDays(45)),
            customer: gida
        )
        try repositories.contacts.add(Contact(fullName: "Mehmet Kaya", title: "Fabrika Müdürü", phone: "+90 555 000 00 03"), to: gida)
        try repositories.visits.add(Visit(date: daysAgo(40)), customer: gida, contacts: [], opportunity: nil)

        // 3) Zayıf, uzun süredir ziyaret edilmeyen
        let tekstil = Customer(
            name: "Kuzey Tekstil A.Ş.", city: "Çanakkale", district: "Biga",
            sector: "Tekstil", status: .current, rating: .weak,
            ratingNote: "Küçük hacimli, yedek parça alıyor."
        )
        try repositories.customers.add(tekstil)
        let lost = Opportunity(
            title: "Eski hat revizyonu", estimatedValue: 54_000, currency: .tl, stage: .lost, expectedCloseDate: inDays(-30)
        )
        lost.lostReason = "Rakip fiyatı daha düşük kaldı"
        try repositories.opportunities.add(lost, customer: tekstil)
        try repositories.visits.add(Visit(date: daysAgo(100)), customer: tekstil, contacts: [], opportunity: nil)

        // 4) Önemli, aday, hiç ziyaret edilmemiş
        let seramik = Customer(
            name: "Anadolu Seramik San. A.Ş.", city: "Kütahya", district: "Merkez",
            sector: "Seramik", status: .potential, rating: .important,
            ratingNote: "Fırın otomasyonunu yenilemek istiyorlar."
        )
        try repositories.customers.add(seramik)
        try repositories.opportunities.add(
            Opportunity(title: "Fırın kontrol sistemi", estimatedValue: 85_000, currency: .eur, stage: .lead),
            customer: seramik
        )

        // 5) Zayıf, pasif
        let plastik = Customer(
            name: "Yıldız Plastik Ltd. Şti.", city: "Eskişehir", district: "Odunpazarı",
            sector: "Plastik", status: .passive, rating: .weak
        )
        try repositories.customers.add(plastik)

        // 6) Potansiyelli, mevcut, yakın zamanda ziyaret edilmiş
        let otomotiv = Customer(
            name: "Deniz Otomotiv Yan Sanayi A.Ş.", city: "Yalova", district: "Çiftlikköy",
            sector: "Otomotiv yan sanayi", status: .current, rating: .promising,
            ratingNote: "Robot hücresi için sürücü ihtiyacı çıkabilir."
        )
        try repositories.customers.add(otomotiv)
        try repositories.opportunities.add(
            Opportunity(title: "Robot hücresi sürücüleri", estimatedValue: 9_800, currency: .eur, stage: .qualified, expectedCloseDate: inDays(3)),
            customer: otomotiv
        )
        try repositories.contacts.add(Contact(fullName: "Elif Şahin", title: "Proje Mühendisi", phone: "0555 000 00 04", email: "elif@example.com"), to: otomotiv)
        try repositories.visits.add(Visit(date: daysAgo(3)), customer: otomotiv, contacts: [], opportunity: nil)

        // Teklifler (hayali). T-2026-014 `PipelineView`'daki ekran görüntüsü senaryosuyla eşleşmeli.
        func addQuote(
            _ number: String, _ customer: Customer, opportunity: Opportunity? = nil, status: QuoteStatus,
            currency: Currency = .tl, dateOffset: Double, validOffset: Double?, sentOffset: Double? = nil,
            notes: String = "", lostReason: String = "", items: [(String, String, Int, Double, Double)]
        ) throws {
            let quote = Quote(
                quoteNumber: number, date: inDays(dateOffset), validUntil: validOffset.map { inDays($0) },
                currency: currency, status: status, notes: notes
            )
            quote.sentAt = sentOffset.map { inDays($0) }
            quote.lostReason = lostReason
            try repositories.quotes.add(quote, customer: customer, opportunity: opportunity)
            for (index, row) in items.enumerated() {
                let item = QuoteItem(catalogNumber: row.0, itemDescription: row.1, quantity: row.2, unitPrice: row.3, discountPercent: row.4)
                item.position = index
                try repositories.quoteItems.add(item, to: quote)
            }
        }
        try addQuote(
            "T-2026-014", ornek, opportunity: hat3, status: .sent, dateOffset: -2, validOffset: 2, sentOffset: -2,
            notes: "Teslim süresi 6 hafta; ödeme %50 peşin, kalan teslimde.",
            items: [
                ("1756-L71", "ControlLogix 5571 işlemci", 2, 142_500, 5),
                ("1756-IB16", "16 kanal dijital giriş modülü", 4, 18_750, 0),
                ("1756-OB16E", "16 kanal dijital çıkış modülü", 4, 21_200, 10)
            ]
        )
        try addQuote(
            "T-2026-012", ornek, opportunity: bakim, status: .followUp, dateOffset: -10, validOffset: 20, sentOffset: -9,
            items: [("BAKIM-YIL", "Yıllık bakım sözleşmesi (12 ay)", 1, 120_000, 0)]
        )
        try addQuote(
            "T-2026-015", gida, status: .draft, currency: .usd, dateOffset: 0, validOffset: 30,
            items: [
                ("2080-LC50-48QWB", "Micro850 kompakt denetleyici", 3, 1_450, 0),
                ("2711R-T7T", "PanelView 800 7\" HMI", 2, 1_980, 5)
            ]
        )
        try addQuote(
            "T-2026-009", ornek, opportunity: yedekParca, status: .won, dateOffset: -40, validOffset: -10, sentOffset: -39,
            items: [("YEDEK-PKT", "Yedek parça paketi", 1, 36_000, 0)]
        )
        try addQuote(
            "T-2026-007", tekstil, status: .lost, dateOffset: -45, validOffset: -15, sentOffset: -44,
            lostReason: "Rakip fiyatı daha düşük kaldı",
            items: [("1769-L33ER", "CompactLogix 5370 işlemci", 1, 54_000, 0)]
        )
        try addQuote(
            "T-2026-011", otomotiv, status: .sent, currency: .eur, dateOffset: -12, validOffset: -1, sentOffset: -12,
            items: [("1756-L83E", "ControlLogix 5580 işlemci", 1, 9_800, 0)]
        )
    }

    /// Bugün ekranı görüntüleri için: gecikmiş / bugün / yarın takipleri ve bugünkü ziyaretler (hayali).
    /// `load(into:)` çağrıldıktan sonra kullanılır; yalnızca `-DebugScene today|todayForm` ile yüklenir.
    @MainActor
    static func loadTodayShowcase(into repositories: Repositories, now: Date = Date(), calendar: Calendar = .current) throws {
        let customers = try repositories.customers.fetchAll()
        func customer(_ name: String) -> Customer? { customers.first { $0.name == name } }
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }
        func task(_ title: String, _ due: Date, _ source: TaskSource, _ customerName: String) throws {
            try repositories.tasks.add(
                FollowUpTask(title: title, dueDate: due, source: source),
                customer: customer(customerName), quote: nil, visit: nil
            )
        }

        let ornek = "Örnek Makina A.Ş."
        let marmara = "Marmara Gıda San. Tic. Ltd. Şti."
        let kuzey = "Kuzey Tekstil A.Ş."
        let anadolu = "Anadolu Seramik San. A.Ş."
        let deniz = "Deniz Otomotiv Yan Sanayi A.Ş."

        // Gecikmiş
        try task("Bakım sözleşmesi örneğini gönder", at(-2, 9), .visitNextStep, ornek)
        try task("Fiyat listesi güncellemesini ilet", at(-1, 14), .manual, marmara)
        // Bugün
        try task(VisitFrequencyService.taskTitle, at(0, 9), .visitFrequency, anadolu)
        try task("Hat 3 teklifini hazırla", at(0, 10, 30), .manual, ornek)
        try task("Satın alma ile telefon görüşmesi", at(0, 16), .manual, deniz)
        // Yarın
        try task("Numune ürün listesini gönder", at(1, 9), .manual, marmara)
        try task("Kuzey Tekstil'i ara", at(1, 11), .manual, kuzey)

        // Bugünkü ziyaretler: biri CRM'e aktarılmış, ikisi aktarılmamış (dışa aktarma ekranları da bunları kullanır)
        if let c = customer(deniz) {
            let exported = Visit(
                date: at(0, 8, 30), type: .visit,
                summary: "Robot hücresi sürücü ihtiyacı görüşüldü."
            )
            try repositories.visits.add(exported, customer: c, contacts: c.contacts ?? [], opportunity: nil)
            try repositories.visits.markExported([exported], at: now)
        }
        if let c = customer(ornek) {
            try repositories.visits.add(
                Visit(
                    date: at(0, 11, 15), type: .phone,
                    summary: "Teklif kapsamı telefonda netleştirildi.\nHat 3 için 2 adet ControlLogix işlemci ve G/Ç modülleri istendi.\nTeslim süresi ve bakım sözleşmesi ayrıca konuşulacak.",
                    topic: "Hat 3 teklif kapsamı",
                    nextStep: "Hat 3 için teklif hazırlanacak",
                    nextStepDate: at(3, 9)
                ),
                customer: c, contacts: c.contacts ?? [], opportunity: nil
            )
        }
        if let c = customer(marmara) {
            try repositories.visits.add(
                Visit(
                    date: at(0, 13, 45), type: .visit,
                    summary: "Dolum hattı yatırımı için yerinde keşif yapıldı.",
                    nextStep: "Numune ürün listesi gönderilecek",
                    nextStepDate: at(1, 9)
                ),
                customer: c, contacts: c.contacts ?? [], opportunity: nil
            )
        }
    }

    /// Bölge ekranı görüntüleri için: Bursa'da ilçelere, OSB'lere ve OSB'siz müşterilere yayılmış ek hayali müşteriler
    /// (bekleyen teklif, gecikmiş takip, ziyaret sıklığı aşımı, migrasyon fırsatı). `load(into:)` sonrası kullanılır;
    /// yalnızca `-DebugScene region|regionCity|regionDistrict` ile yüklenir (diğer görüntüler/testler değişmez).
    @MainActor
    static func loadRegionShowcase(into repositories: Repositories, now: Date = Date()) throws {
        func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

        func add(
            _ name: String, city: String, district: String, zone: String = "", sector: String,
            status: CustomerStatus, rating: CustomerRating, lastVisitDaysAgo: Double? = nil, createdDaysAgo: Double = 10
        ) throws -> Customer {
            let customer = Customer(
                name: name, city: city, district: district, industrialZone: zone, sector: sector,
                status: status, rating: rating
            )
            customer.createdAt = daysAgo(createdDaysAgo)
            try repositories.customers.add(customer)
            if let lastVisitDaysAgo {
                try repositories.visits.add(Visit(date: daysAgo(lastVisitDaysAgo)), customer: customer, contacts: [], opportunity: nil)
            }
            return customer
        }
        func pendingQuote(_ number: String, _ customer: Customer) throws {
            let quote = Quote(
                quoteNumber: number, date: daysAgo(6), validUntil: daysAgo(-24), currency: .tl, status: .sent
            )
            quote.sentAt = daysAgo(6)
            try repositories.quotes.add(quote, customer: customer, opportunity: nil)
        }
        func overdueTask(_ title: String, _ customer: Customer, daysLate: Double) throws {
            try repositories.tasks.add(
                FollowUpTask(title: title, dueDate: daysAgo(daysLate), source: .manual),
                customer: customer, quote: nil, visit: nil
            )
        }

        // Bursa / Nilüfer (OSB'li ve OSB'siz) — "Örnek Makina A.Ş." (Bursa OSB) zaten örnek veride var
        let kablo = try add("Ege Kablo San. A.Ş.", city: "Bursa", district: "Nilüfer", zone: "Bursa OSB", sector: "Kablo",
                            status: .current, rating: .promising, lastVisitDaysAgo: 70)
        try pendingQuote("T-2026-021", kablo)
        try overdueTask("Fiyat listesini gönder", kablo, daysLate: 2)
        _ = try add("Nilüfer Boya Fabrikası Ltd. Şti.", city: "Bursa", district: "Nilüfer", sector: "Kimya",
                    status: .potential, rating: .weak, createdDaysAgo: 130)
        _ = try add("Görükle Elektrik Pano San.", city: "Bursa", district: "Nilüfer", sector: "Elektrik pano",
                    status: .potential, rating: .promising, lastVisitDaysAgo: 8)

        // Bursa / Osmangazi, Kestel, İnegöl
        let hidrolik = try add("Uludağ Hidrolik San. Tic. A.Ş.", city: "Bursa", district: "Osmangazi", zone: "Demirtaş OSB",
                               sector: "Hidrolik", status: .current, rating: .important, lastVisitDaysAgo: 5)
        try repositories.installedProducts.add(
            InstalledProduct(catalogNumber: "SLC 5/04", productFamily: "SLC 500", lifecycleStatus: .endOfLife), to: hidrolik
        )
        try overdueTask("Bakım sözleşmesi görüşmesi", hidrolik, daysLate: 4)
        _ = try add("Kestel Döküm A.Ş.", city: "Bursa", district: "Kestel", sector: "Döküm",
                    status: .potential, rating: .promising, lastVisitDaysAgo: 20)
        let mobilya = try add("İnegöl Mobilya Makineleri Ltd. Şti.", city: "Bursa", district: "İnegöl", zone: "İnegöl OSB",
                              sector: "Ahşap makineleri", status: .current, rating: .weak, lastVisitDaysAgo: 40)
        try pendingQuote("T-2026-022", mobilya)

        // Diğer şehirlerden birkaç müşteri (şehir listesi sayıları için)
        _ = try add("Edremit Zeytinyağı Gıda A.Ş.", city: "Balıkesir", district: "Edremit", sector: "Gıda",
                    status: .potential, rating: .promising, lastVisitDaysAgo: 15)
        _ = try add("Tepebaşı Elektronik San.", city: "Eskişehir", district: "Tepebaşı", zone: "Eskişehir OSB", sector: "Elektronik",
                    status: .current, rating: .important, lastVisitDaysAgo: 25)
    }
}
#endif

#if DEBUG
extension SampleData {
    /// İçe aktarma ekran görüntüleri için hayali CSV (Türkçe Excel biçimi: `;` ayraç). Bir satır mevcut müşteriyle
    /// çakışır, bir satır hatalıdır.
    static let importCSV = """
    Firma Adı;İl;İlçe;OSB;Sektör;Adres;Telefon;E-posta;Yetkili
    Örnek Makina A.Ş.;Bursa;Nilüfer;Bursa OSB;Makine imalatı;;;;
    Örnek Döküm Ltd.;bursa;nilufer;Bursa OSB;Döküm;;0555 000 00 21;dokum@example.com;Veli Kaya
    Örnek Ambalaj A.Ş.;Balıkesir;Bandırma;;Ambalaj;;0555 000 00 22;;Zeynep Ak
    Örnek Cam San.;Eskişehir;Tepebasi;Eskişehir OSB;Cam;;;;
    Örnek Kimya A.Ş.;Çanakkale;Biga;;Kimya;;;;Can Er
    ;Bursa;Osmangazi;;Boş firma;;;;
    Örnek Mobilya Ltd.;Bilecik;Bozüyük;;Mobilya;;;mobilya-example;
    """
}
#endif
