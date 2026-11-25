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

## Ana gezinme ve müşteri ekranları — kararlar

1. **Sekmeler:** Bugün, Müşteriler, Fırsat/Teklif, Harita, Ayarlar (`RootTabView`). Müşteriler dışındakiler
   `PlaceholderView` (boş ekran + kısa açıklama). Seçili/metin vurgusu `Theme.brandText`; `AccentColor` brand
   olarak kaldı ama küçük yazıda açık zeminde kontrast kuralı gereği `.tint(Theme.brandText)` verilir.
2. **Bölge şehirleri:** `AppSettings.responsibleCities` (UserDefaults, App Group paylaşımlı; grup kimliği
   Info.plist'teki `AppGroupID` anahtarından). Varsayılan SPEC'teki 8 şehir; sabit enum yok. Ayarlar ekranı
   henüz yok, liste şimdilik koddan/ileride Ayarlar'dan değişir. Müşterinin mevcut şehri listede yoksa formda
   seçenek olarak korunur; filtre menüsü bölge şehirleri + verideki diğer şehirleri gösterir.
3. **Liste durumu:** `CustomerListModel` (@Observable) yalnızca `CustomerRepository` kullanır. Sıralama: ada göre,
   son ziyaret yeni→eski, son ziyaret eski→yeni. Arama Türkçe büyük/küçük harf duyarsız.
4. **Detay tek kaydırılabilir liste:** SPEC "sekmeler" diyor (Kişiler, Geçmiş, Fırsatlar, Kurulu baz, Notlar);
   ilk sürümde sekme yerine alt alta bölümler yaptım (daha az kod, derleme riski düşük). Ziyaret geçmişi ve
   Fırsatlar boş başlık; Kurulu baz kayıt varsa listelenir (ekleme arayüzü yok). Migrasyon etiketi detay üst
   kartında.
5. **Kişi bağlantıları:** `ContactLink` — telefon `tel:`, e-posta `mailto:`, WhatsApp `https://wa.me/<ulke-kodlu>`.
   Numara Türkiye varsayımıyla uluslararası biçime çevrilir (0555… → 90555…, +/00 önekli olduğu gibi).
   Kişi satırında sola kaydırma: Sil; sağa kaydırma: Düzenle. Birden çok düğme tek satırda olduğu için
   `.buttonStyle(.borderless)` kullanıldı.
6. **Müşteri silme:** detaydan menüyle, onay sorulur. Silinmiş modele ekran hâlâ bakmasın diye liste ekranı önce
   detaydan çıkar, 0,6 sn sonra siler.
7. **Örnek veri ve ekran görüntüleri:** hayali 6 firma `SampleData` içinde, yalnızca `#if DEBUG`. Uygulama
   `-DebugSampleData` argümanıyla açılırsa bellek içi depo + örnek veri kullanır (diske yazılmaz);
   `-DebugScene customers|detail|form` ilgili ekranı açar. Release derlemesinde bu seçenekler hep kapalıdır.
   CI bu ekranların açık ve koyu görüntülerini `screen-<ekran>-<mod>.png` olarak artifact'e koyar.
   (ImageRenderer List/NavigationStack'i düzgün çizemediği için gerçek simülatör ekran görüntüsü yöntemi seçildi.)
8. **Bilinçli olarak yapılmayanlar:** "+ Ziyaret" hızlı butonu, Ayarlar ekranı (şehir listesi düzenleme),
   Bugün ekranı, ziyaret/fırsat/kurulu baz ekleme arayüzleri, CSV içe aktarma.

## Durum günlüğü

- Palet (Color Set, `Theme.swift`, ikon) tamamlandı ve CI'da yeşil.
- Veri katmanı tamamlandı, CI yeşil (41 test). **Deneme 1 başarısız oldu:** `.gitignore`'daki `data/` kuralı
  Windows'ta büyük/küçük harf duyarsız eşleşip `SahaSatis/Data/` klasörünü yutmuştu (dosyalar hiç push edilmedi,
  `Persistence` bulunamadı). Kural `/data/` ve `/customer-data/` olarak kök dizine daraltıldı. Deneme 2 yeşil.
  Ders: yeni klasör eklerken `git status` / `git ls-files` ile dosyaların gerçekten izlendiği kontrol edilmeli.
- CI runner'ı `macos-15-intel`: arm64 macOS havuzunda kapasite olmadığı için (iş 15+ dk atanamadı) geçildi.
  Arm64 kapasitesi düzelirse `macos-15`'e dönülebilir.
- Ana gezinme ve müşteri ekranları tamamlandı, CI ilk denemede yeşil (52 test; 12 ekran görüntüsü artifact'te:
  `screen-{customers,detail,form}-{light,dark}.png`, `app*.png`, `widget-*.png`). Görüntüler elle incelendi:
  renkler, rozetler, kişi düğmeleri ve Türkçe karakterler doğru. Not: simülatörün yereli İngilizce olduğu için
  "Son ziyaret" tarihi `Nov 21, 2026` biçiminde görünüyor; Türkçe cihazda yerel biçimle gösterilir.
- Bu noktada duruldu; sıradaki iş için yeni talimat bekleniyor.
