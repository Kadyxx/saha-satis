import Foundation

/// Ekran görüntüsü senaryoları için ziyaret formu başlangıç değerleri (hayali metinler).
extension VisitFormSeed {
    /// Dolu ziyaret formu: not, sonraki adım ve takip tarihi, ilk kişi işaretli.
    static let showcaseForm = VisitFormSeed(
        topic: "Hat 3 teklif kapsamı",
        note: "Hat 3 PLC yenilemesi görüşüldü. Bakım müdürü eski denetleyicilerin yedek parça sorununu anlattı; teklif istediler.",
        nextStep: "Hat 3 için teklif hazırlanacak",
        nextStepInDays: 4,
        selectFirstContacts: 1,
        autoStartRecording: false
    )

    /// Sesli kayıt durumu: sahte motor canlı metin gönderir.
    static let showcaseRecording = VisitFormSeed(
        topic: "Hat 3 PLC yenileme",
        note: "Hat 3 PLC yenilemesi görüşüldü.",
        nextStep: "",
        nextStepInDays: nil,
        selectFirstContacts: 1,
        autoStartRecording: true
    )

    /// Ham (dikte edilmiş gibi) not; "Claude ile düzenle" düğmelerine kaydırılır.
    static let showcaseAssistant = VisitFormSeed(
        note: "ahmet beyle görüştük hat üçteki 1756-L61 eskimiş yedek bulamıyorlar L8 serisine geçiş için teklif istediler haftaya göndereceğiz",
        selectFirstContacts: 1,
        scrollToAssistant: true
    )

    /// Şablona uygun cevabın önizlemesi.
    static let showcasePreview: VisitFormSeed = {
        var seed = showcaseAssistant
        seed.pastedReply = """
        Konu: Hat 3 PLC yenileme
        Özet: Hat 3'te kullanılan 1756-L61 denetleyicilerin yedek parça temininde sorun yaşandığı iletilmiştir. ControlLogix L8 serisine geçiş için teklif talep edilmiştir.
        Sonraki adım: Geçiş teklifi hazırlanıp gönderilecek
        Takip tarihi: 04.12.2026
        """
        return seed
    }()

    /// Şablona uymayan cevap: uyarılı önizleme.
    static let showcaseBrokenPreview: VisitFormSeed = {
        var seed = showcaseAssistant
        seed.pastedReply = "Tabii, notu düzenledim: Hat 3'teki 1756-L61 denetleyiciler için geçiş teklifi istendi."
        return seed
    }()
}
