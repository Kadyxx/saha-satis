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

## Düzeltmeler ve Ayarlar ekranı — kararlar

1. **Türkçe büyük harf:** Bölüm başlıklarını sistem otomatik büyük harfe çevirir ve bunu ortam yerel ayarıyla yapar;
   `RootTabView` kökünde `.environment(\.locale, tr_TR)` verildi ("KİŞİLER", "DEĞERLENDİRME"). Ek olarak Info.plist'e
   `CFBundleDevelopmentRegion: tr` ve `CFBundleLocalizations: [tr]` eklendi: sistemin kendi metinleri (Düzenle,
   İptal, Ara…) cihaz dili İngilizce olsa da Türkçe gelir. Tarihler yerel ayara güvenmez: `AppFormat.date` her zaman
   `tr_TR` ("21 Kas 2026").
2. **"Aday":** `CustomerStatus.potential` görünen metni "Aday" (Mevcut / Aday / Pasif); ham değer `potential` aynı,
   veri göçü gerekmez. SPEC güncellendi. Karışmasın diye `OpportunityStage.lead` metni "Aday"dan "Yeni"ye alındı
   (fırsat aşaması; ham değer `lead`). Değerlendirme rozetleri (Önemli / Potansiyelli / Zayıf) aynen kaldı.
3. **Etiketli form alanları:** `FormTextField` (LabeledContent: etiket solda, değer sağda) ve `FormMultilineField`
   (üstte küçük etiket). Müşteri ve kişi formlarında kullanılır.
4. **Ekran görüntüleri tr_TR:** CI uygulamayı `-AppleLanguages "(tr)" -AppleLocale tr_TR` ile başlatır.
5. **Gezinme başlıkları:** `AppAppearance` ile `UINavigationBarAppearance`; büyük ve satır içi başlıklar `textPrimary`
   (`UIColor(named:)` açık/koyu varyantı izler).
6. **Ayarlar:** `Shared/AppSettings.swift` (widget de derleyebilsin diye Shared'a taşındı; widget Info.plist'ine de
   `AppGroupID` eklendi). `ObservableObject` + `@Published`; her değişiklik App Group UserDefaults'a anında yazılır.
   Bölümler: Profil (ad soyad, unvan; yerel), Bölge (şehir ekle/sil/sırala — `EditButton`), Hatırlatmalar (varsayılan
   saat 09:00, sabah özeti aç/kapa + 08:00, gün sonu aç/kapa + 18:00, hafta sonu bildirimleri), Ziyaret sıklığı
   (Önemli 30 / Potansiyelli 60 / Zayıf 120 gün; adım 5, aralık 5–365), Teklifler (takip günleri "3, 7" virgüllü metin;
   geçerlilik uyarısı aç/kapa + 3 gün), Dışa aktarma (CRM e-postası), Hakkında (sürüm).
   - **Hafta sonu bildirimleri varsayılan KAPALI** (SPEC varsayılan vermiyor; sabah özeti "iş günü" ve görevler iş
     gününe kayıyor). Ayarlardan açılır.
   - **Boş şehir listesi bilinçli bir seçimdir** ve boş saklanır; yalnızca hiç ayarlanmamışsa 8 varsayılan şehir gelir
     (son şehri silince 8 şehrin geri gelmesi şaşırtıcı olurdu).
   - Gün sonu hatırlatmasına SPEC'teki "aç/kapa" için anahtar eklendi (istenen yalnızca saatti).
   - Bu ayarlar henüz hiçbir yerde **uygulanmıyor** (hatırlatma motoru yok); yalnızca saklanıyor. Müşteri formu ve filtre
     menüsü şehirleri ayarlardan okur.
7. **Ayarlar ekran görüntüleri:** `settings` (üst), `settingsReminders` (hatırlatmalar bölümüne kaydırılmış),
   `settingsCities` (şehirler alt ekranı), açık/koyu. Örnek veri modunda ayarlar geçici bir UserDefaults kümesinde
   tutulur (gerçek App Group ayarlarına dokunulmaz) ve hayali profil doldurulur.

## Ziyaret kaydı — kararlar

1. **"+ Ziyaret" düğmesi:** `visitButton(customer:onSaved:)` görünüm değiştiricisi (`safeAreaInset`, action rengi,
   onAction yazı). Bugün/Fırsat/Harita yer tutucularına, Müşteriler listesine, Ayarlar ve Şehirler ekranlarına,
   müşteri detayına eklendi. `safeAreaInset` olduğu için liste/ayar satırlarının sağındaki kontrolleri kapatmaz.
   Detaydan açılırsa o müşteri seçili gelir. Bağımlılıklar `AppContext` (EnvironmentObject) ile taşınır.
2. **Ziyaret formu** (`VisitFormView` + `VisitFormModel`): müşteri (seçici), görüşülen kişiler (işaretleme),
   tip (segmentli: Yüz yüze / Telefon / Online), tarih+saat (varsayılan şimdi), sesli not, görüşme notu,
   sonraki adım + isteğe bağlı takip tarihi. Müşteri yalnızca yeni kayıtta seçilebilir; düzenlemede sabit.
   **Müşteri seçici:** en son ziyaret edilenler üstte + arama. SPEC "konuma en yakınlar üstte" diyor; konum izni ve
   müşteri koordinatları henüz olmadığı için (Harita fazı) konum sıralaması yapılmadı.
3. **Sesli not mimarisi:** `SpeechEngine` protokolü → `AppleSpeechEngine` (Speech, `tr-TR`, AVAudioEngine) ve
   `MockSpeechEngine` (testler + DEBUG ekran görüntüleri). `VoiceNoteController` durum makinesi: idle / recording /
   paused / permissionDenied / unavailable / failed. Duraklat = oturumu kapat + canlı metni nota ekle; Devam = yeni
   oturum. Uzun kayıtlar (tanıyıcı ~1 dk'da oturumu bitirir): oturum kendiliğinden bitince metin nota eklenir ve yeni
   oturum açılır (SPEC "uzun kayıtlar parçalanarak işlenir"); art arda 3 anlık bitişte döngüye girmemek için durur.
   Canlı metin kayıt sırasında ayrı satırda gösterilir, duraklatma/bitirme/parça sonunda **görüşme notuna eklenir**;
   not her zaman elle düzenlenebilir. Ham ses metni `Visit.transcript`'e (parçaların birleşimi, notu düzenlesen
   değişmez), düzenlenmiş not `Visit.summary`'ye yazılır.
4. **İzinler:** Info.plist'e Türkçe `NSMicrophoneUsageDescription` ve `NSSpeechRecognitionUsageDescription`.
   İzin verilmezse/tanıyıcı yoksa uygulama bir mesaj ve "İzinleri Ayarlar'dan aç" düğmesi gösterir; not alanı her
   zaman klavyeyle kullanılabilir. **Gerçek mikrofon/konuşma tanıma yalnızca gerçek iPhone'da denenebilir** (CI'da
   mock); `AppleSpeechEngine` bu yüzden elle test edilmeli (özellikle izin akışı ve 1 dk üstü kayıt).
5. **Takip görevi:** `VisitService` (iş kuralı katmanı). `nextStepDate` seçilirse `FollowUpTask`
   (source `visitNextStep`, müşteri + ziyarete bağlı) oluşur; başlık = sonraki adım metni (boşsa "Sonraki adım");
   vade = seçilen gün + Ayarlar'daki hatırlatma saati (varsayılan 09:00, form açılışındaki değer). Düzenlemede aynı
   görev güncellenir (çoğalmaz); tarih kaldırılırsa açık görev silinir; tamamlanmış görev korunur ve yeniden
   açılmaz. Ziyaret silinirse açık sonraki-adım görevi de silinir.
6. **Yeni ziyaret girilince** müşterinin açık `visitFrequency` görevi kapanır (SPEC). Bu türden görev üreten
   hatırlatma motoru henüz yok; kural hazır ve testli.
7. **Son ziyaret tarihi** `Customer.lastVisitDate` hesaplanan özellik olduğu için kayıtla kendiliğinden güncel;
   liste `onSaved` ile yenilenir.
8. **Ziyaret geçmişi** (müşteri detayı): yeniden eskiye; satırda tarih-saat, tip, not özeti (3 satır), sonraki adım
   ve kişiler. Satıra dokunmak düzenleme formunu açar (ayrı bir salt-okunur detay ekranı yapılmadı: tek ekran hem
   detay hem düzenleme). Sola kaydırıp Sil: onay sorulur.
9. **Kapsam dışı bırakılanlar:** ziyareti fırsata bağlama / yeni fırsat açma (SPEC adım 4), "Yapay zekâ ile düzenle"
   (Faz 4), gün sonu e-posta dışa aktarma (`exportedToCRM` alanı `false` başlıyor, akış sonraki adım).
10. **Ekran görüntüsü senaryoları (DEBUG):** `visitForm` (dolu form), `visitRecording` (sahte motor canlı metin
    gönderir: "Dinleniyor…" + Duraklat/Bitir), `visitHistory` (detay, ziyaret geçmişine kaydırılmış). Örnek veride
    Örnek Makina için 3 ziyaret (80/34/12 gün önce) ve 1 bağlı takip görevi var.

## Durum günlüğü (devam)

- Düzeltmeler + Ayarlar ekranı: CI ilk denemede yeşil (60 test), görüntüler elle incelendi.
- Ziyaret kaydı: CI ilk denemede yeşil (87 test; 24 ekran görüntüsü, `screen-visit*`). Ekranlar elle incelendi.
  **Elle denenmesi gerekenler (gerçek iPhone):** mikrofon/konuşma tanıma izin akışı, Türkçe canlı metin, duraklat/devam,
  1 dakikayı aşan kayıt (otomatik parçalama), izin reddedilince klavyeyle yazma.
- Bu noktada duruldu; sıradaki iş için yeni talimat bekleniyor.
