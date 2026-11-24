# Geliştirme notları

Gözetimsiz çalışma sırasında verilen kararlar ve durum. Kararlar `docs/SPEC.md` ile çelişirse SPEC geçerlidir;
buradakiler SPEC'in boş bıraktığı yerlerdir.

## Veri katmanı (Faz 1 ön hazırlık) — kararlar

**Kapsam:** 8 SwiftData modeli (`Customer`, `Contact`, `Visit`, `Opportunity`, `Quote`, `QuoteItem`,
`InstalledProduct`, `FollowUpTask`), her biri için `Repository` protokolü + SwiftData uygulaması ve birim testleri.
Giriş (Sign in with Apple), iCloud senkronu, ekranlar ve hatırlatma motoru **yapılmadı**.

1. **iCloud kapalı.** `Persistence.makeContainer` içinde `cloudKitDatabase: .none` açıkça verilir. Uygulamada iCloud
   yetkisi tanımlı olduğu için bu satır olmazsa SwiftData `.automatic` ile CloudKit'e bağlanmaya çalışırdı.
   Senkron açılırken tek değişiklik bu satırdır (ve Apple hesabı/iCloud container'ı hazır olmalı).
2. **Modeller uygulama hedefinde, widget'ta değil.** Modeller `SahaSatis/Data/` altında. Widget aynı depoyu
   okuyacağı zaman (widget'ları yapma adımı) modeller ortak bir yere (`Shared/` veya framework hedefi) taşınmalı.
   Şimdilik `Shared/` içine koymadım: test hedefi de `Shared/`'ı derlediği için `@Model` sınıfları iki modülde
   çift tanımlanır ve SwiftData/ObjC çalışma zamanında çakışma uyarısı verirdi.
3. **App Group deposu:** `ModelConfiguration` `groupContainer: .automatic` kullanır; imzalı derlemede App Group
   konteynerine yazar, imzasız simülatör derlemesinde varsayılan konuma düşer. Hesap gelince ek ayar gerekmez.
4. **CloudKit uyumu:** tüm özellikler varsayılan değerli veya opsiyonel, `unique` yok, tüm ilişkiler opsiyonel ve
   ters ilişkili. Enum'lar ham `String` (`statusRaw` vb.) olarak saklanır, modeller üzerinde hesaplanan
   `status`/`rating`/... özellikleri vardır.
5. **Silme kuralları:** müşteri silinince kişi, ziyaret, fırsat, teklif, kurulu baz ve görevleri de silinir (cascade).
   Teklif silinince kalemleri ve takipleri silinir. Fırsat silinince teklif/ziyaretler kalır (nullify). Kişi silinince
   ziyaret kalır. Ziyaret silinince ondan doğan görevler kalır (nullify).
6. **Hesaplanan alanlar saklanmaz:** `Customer.lastVisitDate`, `Quote.totalAmount`, `QuoteItem.lineTotal` hesaplanan
   özelliklerdir (SPEC: "hesaplanan"); bayatlama riski yok. Veri hacmi küçük olduğu için sorgular bellekte
   filtrelenir/sıralanır (Predicate yerine); büyürse indekslenir.
7. **Para:** `Double`. `Decimal`'ın CloudKit eşlemesinden emin olmadığım için seçmedim. Tutarlar kuruş hassasiyeti
   gerektirecek duruma gelirse tamsayı kuruş (`Int`) düşünülmeli.
8. **Alan adları:** `description` NSObject ile çakıştığı için `Opportunity.details` ve `QuoteItem.itemDescription`.
   `QuoteItem.quantity` ve `InstalledProduct.quantity` `Int`. `Quote.followUpDays` `[Int]`, boşsa ayarlardaki
   varsayılan kullanılır (`effectiveFollowUpDays(defaultDays:)`).
9. **`ownerUserID`:** her modelde var, varsayılan boş. Repository'ler kayıt eklerken boşsa kendi `ownerUserID`
   değerini damgalar (şimdilik boş; giriş gelince Apple kullanıcı kimliği verilecek).
10. **Repository'ler `@MainActor`** ve `@Model` nesnelerini döndürür (ayrı DTO yok). Faz 5'te sunucuya geçilirse
    protokoller aynı kalıp uygulaması değişir; gerekirse DTO katmanı o zaman eklenir.
11. **Türkçe arama:** müşteri araması `tr_TR` yereliyle büyük/küçük harf ve aksan duyarsızdır.
12. **Bilinçli olarak yapılmayanlar** (sonraki adımlar): ziyarette `nextStepDate` → otomatik `FollowUpTask`
    üretimi, teklif durumu değişince bekleyen takipleri iptal akışı (altyapı hazır: `cancelOpenTasks(for:)`),
    ziyaret girilince `visitFrequency` görevini kapatma, `ReminderScheduler`, ayarlar (`AppSettings`).
    Bunlar iş kuralı/servis katmanıdır, veri katmanının parçası değil.

## Durum günlüğü

- Palet (Color Set, `Theme.swift`, ikon) tamamlandı ve CI'da yeşil.
