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
}
