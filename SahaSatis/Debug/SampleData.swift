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
        try repositories.installedProducts.add(InstalledProduct(catalogNumber: "PLC-5/40", productFamily: "PLC-5", lifecycleStatus: .discontinued), to: ornek)

        // Ziyaret geçmişi (VisitService: sonraki adım tarihi olan ziyaret bağlı takip görevi üretir)
        let visitService = VisitService(repositories: repositories, reminderMinutes: 9 * 60)
        try visitService.save(
            VisitDraft(
                date: daysAgo(80), type: .visit,
                summary: "Yıllık bakım sözleşmesi tanıtıldı. Satın alma süreci ve onay adımları anlatıldı.",
                nextStep: "Bakım sözleşmesi örneği gönderilecek"
            ),
            customer: ornek, contacts: [ayse], existing: nil
        )
        try visitService.save(
            VisitDraft(
                date: daysAgo(34), type: .phone,
                summary: "Yedek parça stok durumu soruldu; fiyat listesi e-postayla gönderildi."
            ),
            customer: ornek, contacts: [ahmet], existing: nil
        )
        try visitService.save(
            VisitDraft(
                date: daysAgo(12), type: .visit,
                summary: "Hat 3 PLC yenilemesi görüşüldü. Eski denetleyicilerin yedek parça sorunu var; teklif istediler.",
                nextStep: "Hat 3 için teklif hazırlanacak",
                nextStepDate: now.addingTimeInterval(3 * 86_400)
            ),
            customer: ornek, contacts: [ahmet, ayse], existing: nil
        )

        // 2) Potansiyelli, aday müşteri
        let gida = Customer(
            name: "Marmara Gıda San. Tic. Ltd. Şti.", city: "Balıkesir", district: "Bandırma",
            sector: "Gıda", status: .potential, rating: .promising,
            ratingNote: "Yeni dolum hattı yatırımı planlıyorlar."
        )
        try repositories.customers.add(gida)
        try repositories.contacts.add(Contact(fullName: "Mehmet Kaya", title: "Fabrika Müdürü", phone: "+90 555 000 00 03"), to: gida)
        try repositories.visits.add(Visit(date: daysAgo(40)), customer: gida, contacts: [], opportunity: nil)

        // 3) Zayıf, uzun süredir ziyaret edilmeyen
        let tekstil = Customer(
            name: "Kuzey Tekstil A.Ş.", city: "Çanakkale", district: "Biga",
            sector: "Tekstil", status: .current, rating: .weak,
            ratingNote: "Küçük hacimli, yedek parça alıyor."
        )
        try repositories.customers.add(tekstil)
        try repositories.visits.add(Visit(date: daysAgo(100)), customer: tekstil, contacts: [], opportunity: nil)

        // 4) Önemli, aday, hiç ziyaret edilmemiş
        let seramik = Customer(
            name: "Anadolu Seramik San. A.Ş.", city: "Kütahya", district: "Merkez",
            sector: "Seramik", status: .potential, rating: .important,
            ratingNote: "Fırın otomasyonunu yenilemek istiyorlar."
        )
        try repositories.customers.add(seramik)

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
        try repositories.contacts.add(Contact(fullName: "Elif Şahin", title: "Proje Mühendisi", phone: "0555 000 00 04", email: "elif@example.com"), to: otomotiv)
        try repositories.visits.add(Visit(date: daysAgo(3)), customer: otomotiv, contacts: [], opportunity: nil)
    }
}
#endif
