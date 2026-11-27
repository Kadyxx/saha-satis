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

## Bugün ekranı ve hatırlatma motoru — kararlar

**CI:** `build.yml` yalnızca `main` push'unda ve pull request'te çalışıyordu; bu branch'e push CI tetiklemiyordu.
`push` artık `[main, 'claude/**']`. (Aynı commit hem push hem PR'da çalışabilir; `concurrency` ref başına olduğu için
ikisi de koşar, kabul ettim.)

1. **Katmanlar.** Saf mantık ayrı, sistem katmanı ince: `ReminderPlanner` (Foundation'dan başka bağımlılığı yok:
   görev anlık görüntüleri + ayar anlık görüntüsü + `now` + `Calendar` → `[PlannedNotification]`), `ReminderScheduler`
   (SwiftData'dan okur, planlayıcıyı çağırır, sonucu `NotificationScheduling`'e verir), `SystemNotificationScheduler`
   (`UNUserNotificationCenter`), `NullNotificationScheduler` (DEBUG), `MockNotificationScheduler` (testler).
2. **Tetikleyiciler.** (a) uygulama açılışı (`RootTabView.task` → `start()`: izin iste, dinlemeye başla, hesapla),
   (b) sahneye dönüş (`scenePhase == .active`), (c) **her veri değişikliği**: repository'lerin 25 `context.save()`
   çağrısı `context.saveAndNotify()` oldu; kayıttan sonra `.appDataDidChange` yayınlanır, motor 500 ms bekleyip tek
   hesaplama yapar (art arda kayıtlar birleşir), (d) ayar değişikliği (`AppSettings.objectWillChange`),
   (e) `BGAppRefreshTask`: `.backgroundTask(.appRefresh)` sahne değiştiricisi; istek uygulama arka plana giderken ve
   her çalışmanın sonunda bir sonraki sabah 05:00'e kurulur. `Info.plist`: `UIBackgroundModes: fetch`,
   `BGTaskSchedulerPermittedIdentifiers: <bundle id>.refresh`. **Sistem çalıştırmayı garanti etmez, simülatörde hiç
   çalışmaz**; asıl tetikleyiciler a–d, günlük yenileme yedektir. Bir hesaplamanın kendi yazdığı görevler yeni bir
   hesaplamayı tetikler; ikinci hesaplama bir şey yazmadığı için döngü orada biter (ziyaret sıklığı eşitlemesi
   değişmezdir). Hesaplamalar `inFlight` ile sıraya girer (iki `replaceAll` iç içe geçmesin).
3. **64 sınırı.** Her seferinde bekleyen TÜM bildirimler silinir; görev bildirimleri + sabah özetleri + gün sonu
   tek listede zamana göre sıralanıp ilk 64'ü planlanır (`ReminderPlanner.maxPendingNotifications`).
   Kimlikler kararlıdır (`task.<uuid>`, `summary.2026-11-25`, `endofday.2026-11-25`); bu yüzden
   `FollowUpTask.notificationID` alanına **yazılmıyor** (her hesaplamada tüm görevlere yazmak CloudKit'te gürültü
   olurdu). Alan şimdilik kullanılmıyor.
4. **Geçmişte kalan** görevlerin (vade saati geçmiş) kendi bildirimi planlanmaz; gecikmişler sabah özetinde sayılır.
5. **Sabah özeti** önümüzdeki 7 gün için, **yalnızca söylenecek bir şeyi olan** iş günleri için planlanır. Bildirim
   içeriği önceden hesaplanmak zorunda olduğundan (tekrarlı bildirim dinamik metin taşıyamaz) metin planlama anındaki
   veriden gelir: "Bugün 3 takip, 2 gecikmiş". Sayım ham vade gününe göredir (hafta sonu kaydırması sayımı
   değiştirmez), bu yüzden Bugün ekranıyla aynı sonucu verir. İleri günlerdeki "gecikmiş", o gün öncesi vadeli ve hâlâ
   açık görevlerdir; görev tamamlanınca yeniden hesaplama bunu düzeltir.
6. **Gün sonu hatırlatması** yalnızca **bugün** için planlanır (aktarılmamış ziyaret sayısı önceden bilinemez): bugün
   aktarılmamış ziyaret varsa ve saat geçmediyse. Ziyaret kaydedilince / aktarılınca yeniden hesaplama eklenir/kaldırır.
   Önceki günlerin aktarılmamış ziyaretleri şimdilik ne ekranda ne hatırlatmada sayılıyor (SPEC "Bugün yapılan
   ziyaretler" diyor); gün sonu e-posta akışı yapılırken yeniden bakılmalı.
7. **Hafta sonu.** Kapalıyken (varsayılan) Cumartesi/Pazar'a düşen görevin **bildirimi** Pazartesi'ye kayar, saat
   korunur. Görevin kendisi (`dueDate`) değiştirilmez; Bugün ekranı ham tarihe göre gruplar, yani Cumartesi görevi
   Pazartesi sabahı "Gecikmiş"te görünür ve aynı sabah bildirimi gelir. Sabah özeti ve gün sonu da hafta sonu atlanır.
   Hafta günü kontrolü `Calendar.component(.weekday)` ile (1 = Pazar, 7 = Cumartesi), bölgeye bağlı `isDateInWeekend` değil.
8. **Ziyaret sıklığı (`VisitFrequencyService`).** Her hesaplamadan önce çalışır, müşteri başına en çok bir açık görev:
   - Vade = referans günü + değerlendirme eşiği (Ayarlar: 30/60/120), hatırlatma saatinde. Referans = son ziyaret
     (yoksa müşterinin eklenme tarihi) ile en son tamamlanan sıklık görevinin `doneAt`'inden yeni olan. Böylece
     "Tamamlandı" denince görev hemen geri gelmez, sayaç yeniden başlar.
   - Eşik çoktan geçmişse vade **bugünün hatırlatma saatine çekilir** (ilk açılışta yüzlerce eski "gecikmiş" olmasın).
   - **Pasif müşteride görev tutulmaz** (SPEC söylemiyor; pasif müşteriyi ziyaret etmek istenmez), açık olanlar silinir.
   - Var olan açık görev **bir daha değiştirilmez** (kullanıcı ertelemiş olabilir). Sonuç: değerlendirme veya eşik
     sonradan değişirse mevcut açık görevin tarihi eski eşiğe göre kalır; sonraki görev yeni eşikle kurulur.
   - Başlık "Ziyaret zamanı geldi", müşteri adı satırda/bildirim başlığında. Yeni ziyaret girilince `VisitService`
     açık görevi kapatır (önceden vardı); bir sonraki hesaplama yenisini ziyaret tarihinden kurar. Geriye dönük tarihli
     ziyarette kapanış `doneAt = şimdi` olduğundan referans ziyaret tarihinden biraz ileri kayabilir (en çok o kadar gün).
9. **Bugün ekranı.** Gruplar gün bazlı: vadesi bugün olan görev saati geçse de "Bugün"; "Gecikmiş" vade günü geçince.
   Yarından sonrası listelenmez. Üstte bugünkü ziyaretler (tür, saat, aktarıldı/aktarılmadı simgesi) ve "N ziyaret
   CRM'e aktarılmadı" satırı. Satıra dokunmak müşteri detayını açar (`AppContext.open(customer:)` → Müşteriler sekmesi).
   Sola kaydırma: Tamamlandı (tam kaydırma) ve Ertele. Ertele bir `confirmationDialog` açar (1 gün, 3 gün, 1 hafta,
   Tarih seç…); `Menu` swipe action içinde güvenilir olmadığı için kullanılmadı. Kaydırma düğmesi yazıları sistemin
   beyazı: turkuaz/turuncu zeminde palet kuralı (`onBrand`/`onAction`) uygulanamıyor — **elle bakılmalı**.
   Sağ üstte "+" ile manuel takip formu (başlık, isteğe bağlı müşteri, tarih+saat; varsayılan bir sonraki hatırlatma
   saati). İzin reddedilmişse listenin başında "Bildirimler kapalı" uyarısı ve Ayarlar bağlantısı.
10. **Ertele kuralı (`PostponeRule`).** Görevin saati korunur, yalnızca gün değişir. `N gün`: gecikmiş/bugünkü
    görevler bugünden, ileri tarihli görevler kendi gününden sayar (yoksa gecikmiş görev "1 gün" ile hâlâ geçmişte
    kalırdı). "Tarih seç": seçilen gün. Bildirimdeki "Yarına ertele" = `N gün (1)`.
11. **Bildirim aksiyonları.** Kategori `task`: "Tamamlandı", "Yarına ertele" (uygulamayı açmaz). Sabah özeti ve gün sonu
    aksiyonsuz. Bildirime dokununca: görevin müşterisi varsa Müşteriler sekmesinde detay, yoksa Bugün.
    `NotificationResponder` uygulama açıkken de afiş gösterir (`willPresent`). Temsilci `UNUserNotificationCenter`'da
    zayıf tutulduğu için `AppContext` saklar.
12. **İzin.** İlk açılışta bir kez istenir (`.alert, .sound`; rozet yok). Reddedilirse yeniden sorulmaz, Bugün'de uyarı.
13. **DEBUG / CI.** `-DebugSampleData` veya `-DebugNoNotifications` ile bildirim izni istenmez ve sisteme hiçbir şey
    planlanmaz (izin penceresi ekran görüntüsünü kapatırdı). CI'daki düz `app.png` açılışına ve test şemasına
    (`commandLineArguments`) `-DebugNoNotifications` verildi. Yeni senaryolar: `today`, `todayForm`;
    `SampleData.loadTodayShowcase` yalnızca bunlarda yüklenir (hayali: 2 gecikmiş, 3 bugün, 2 yarın takibi; 3 bugünkü
    ziyaret, biri aktarılmış). Görüntüler: `screen-today-{light,dark}.png`, `screen-todayForm-{light,dark}.png`.
14. **Bilinçli olarak yapılmayanlar:** teklif takip/geçerlilik ve fırsat kapanış görevlerini üreten kurallar (Faz 2),
    "Ziyaretleri CRM için gönder" akışı, widget'ların `reloadAllTimelines()` çağrısı (`appDataDidChange` bunun için de
    uygun tek nokta), görev bazında bildirim saati değiştirme (görev saati formda değiştirilebiliyor, mevcut görevin
    saatini düzenleme ekranı yok), Bugün'den görev silme/düzenleme.

**Elle denenmesi gerekenler (gerçek iPhone):** izin penceresi, bildirimin doğru saatte gelmesi, bildirimdeki
Tamamlandı / Yarına ertele aksiyonları (uygulama kapalıyken de), bildirime dokununca müşteri detayının açılması,
hafta sonu kaydırma, kaydırma düğmesi görünümü, `BGAppRefreshTask` (Xcode'dan `e -l objc -- (void)[[BGTaskScheduler
sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"<bundle id>.refresh"]` ile tetiklenebilir; Xcode kullanılamadığı
için yalnızca ertesi sabah bildirimlerin güncel olup olmadığına bakılabilir).

## Widget'lar ve kaydırma düğmesi düzeltmesi — kararlar

**Kaydırma düğmesi yazı rengi.** `swipeActions` düğmelerinde sistem yazıyı/simgeyi hep beyaz çizer; yalnızca zemin
(`.tint`) verilebilir (bildiğim kadarıyla; cihazda denenemedi). Bu yüzden `onBrand`/`onAction` yazı rengi yerine
SPEC'in yedek yolu uygulandı: zemin iki modda da koyu tonlara çekildi. Yeni Color Set'ler `swipeDone` (#2F6265, beyazla
≈ 6,9:1) ve `swipePostpone` (#A63A12, beyazla ≈ 6,5:1); iki modda aynı değer (zemin zaten koyu, mod farkı gerekmiyor).
SPEC palet tablosuna eklendi; yalnızca `TodayView`'daki kaydırma düğmelerinde kullanılır.

**Widget'lar** (`Merhaba` widget'ı kaldırıldı):

1. **Ortak kod `Shared/` altına taşındı.** Widget aynı SwiftData deposunu okuyacağı için `SahaSatis/Data` →
   `Shared/Data` (modeller, repository'ler, `Persistence`), ayrıca `AppFormat` ve yeni `Shared/Widgets/`. Hem uygulama hem
   widget hedefi `Shared`'ı derler. Önceki NOTES'taki "modeller uygulama hedefinde" kararı bununla değişti.
2. **Test hedefi artık `Shared`'ı derlemiyor** (`project.yml`). Önceden `@Model` olmayan Shared tipleri (`TimeOfDay`,
   `AppSettings`) testlerde iki modülde tanımlıydı (CI'da çakışma hatası verdi); `@Model` sınıfları da aynı şekilde
   çift tanımlanırsa SwiftData çalışma zamanında çakışırdı. Testler `@testable import SahaSatis` ile uygulamadaki tek
   kopyayı kullanır. Ekran görüntüsü testleri de buna geçti.
3. **Veri akışı.** `WidgetDataLoader` depodan `WidgetData` (değer tipleri: açık görevler, bekleyen teklif sayısı ve
   para birimi başına toplam, aktarılmamış ziyaret sayısı) okur; `WidgetSnapshot.make(data:at:calendar:)` verilen an için
   gecikmiş/bugün/hafta/sıradaki işi hesaplar. Görünümler yalnızca `WidgetSnapshot` alır; bu yüzden testlerde ve ekran
   görüntülerinde SwiftData gerekmez. Sınıflandırma gün bazlıdır (uygulamadaki Bugün ekranıyla aynı kural).
   **Bekleyen teklif** = durumu "Gönderildi" veya "Takipte". **Aktarılmamış ziyaret sayısı tüm günleri** sayar (Bugün
   ekranı ve gün sonu hatırlatması yalnızca bugünü sayar); widget'ın amacı unutulanı göstermek.
4. **Zaman çizelgesi** (`TasksProvider`, dört widget ortak): şu an + 24 saat içinde (gece yarısına kadar) her görev
   saatinde bir giriş (en çok 20) + gece yarısı; politika `.after(gece yarısı)`. Uygulama `appDataDidChange` ile
   (`WidgetReloader`, 300 ms birleştirir) ve açılışta `reloadAllTimelines()` çağırır; kayıt yapan her ekran buna
   otomatik dahil (repository kaydı). Galeri/önizleme `WidgetData.sample` (hayali) gösterir.
5. **Bugünün takipleri (systemMedium):** başlık, gecikmiş sayısı, en çok 4 satır (önce gecikmişler), fazlası "+N takip
   daha", boşsa "Bugün için takip yok". Satır tek satır ("başlık · müşteri", sağda saat/"Gecikmiş") çünkü iki satırlı 4
   satır 169 pt'ye sığmıyor. Onay kutusu `Button(intent: CompleteTaskIntent)`; satıra dokunmak `sahasatis://task/<id>`.
6. **Haftalık görünüm (systemLarge):** üstte "+ Ziyaret" (`sahasatis://visit/new`), bekleyen teklif sayısı + toplamlar,
   aktarılmamış ziyaret sayısı; altında gecikmişler ve bugün + 6 günün (yalnızca görevi olan günler) görevleri, en çok
   9 satır + "+N takip daha". Görev satırlarında da onay kutusu var.
7. **Sıradaki iş (accessoryRectangular):** en yakın açık görev ("Müşteri – başlık", zaman); gecikmişse ⚠ simgesi.
   **Bekleyen iş sayısı (accessoryCircular):** gecikmiş + bugün. Kilit ekranı widget'ları sistem tarafından tek renge
   boyandığı için palet rengi yok, sistem stilleri (`primary`) kullanıldı; "paleti kullan" yalnızca ana ekran
   widget'ları için geçerli.
8. **`CompleteTaskIntent`** hem uygulama hem widget hedefinde derlenir. Gerçek depoda görevi tamamlar, bekleyen yerel
   bildirimini silmeyi dener (`task.<uuid>`), `reloadAllTimelines()` çağırır. **Bilinmeyenler (cihazda denenmeli):**
   intent'in widget mi uygulama sürecinde çalıştığı; uygulama arka plandan dönünce widget'tan tamamlanan görevin
   (SwiftData uzak değişiklik birleştirmesi) Bugün ekranında hemen görünüp görünmediği; bildirimin silinmesi widget
   sürecinde işe yarıyor mu. Yaramazsa, tamamlanmış görevin bildirimi uygulama bir sonraki açılışta/günlük yenilemede
   yeniden hesaplanana kadar gelebilir.
9. **Derin bağlantılar.** Şema `sahasatis` (`CFBundleURLTypes`): `task/<uuid>` (müşterisi varsa müşteri detayı, yoksa
   Bugün — ayrı bir görev detay ekranı yok; bildirime dokunmayla aynı davranış), `today`, `visit/new` (uygulama
   düzeyinde ziyaret formu sheet'i, `AppContext.presentVisitForm`). Ayrıştırma `WidgetLink` (testli).
10. **App Group:** simülatörde/CI'da imzasız derlemede uygulama ve widget varsayılan konumları farklıdır, yani veri
    paylaşımı **yalnızca imzalı cihaz derlemesinde** çalışır (`ModelConfiguration` varsayılan `groupContainer: .automatic`).
    Gerçek paylaşım ancak Apple Developer hesabı ve App Group tanımlanınca doğrulanabilir.
11. **Ekran görüntüleri:** `widget-today-medium[-empty][-dark]`, `widget-week-large[-dark]`, `widget-next-rect[-empty][-dark]`,
    `widget-count-circular[-dark]` (test hedefi `ImageRenderer` ile, hayali örnek veri). Gerçek widget zeminini
    (`containerBackground`) ve kilit ekranı boyamasını taklit eder; birebir sistem görünümü değildir.
12. **Bilinçli olarak yapılmayanlar:** widget yapılandırması (hepsi `StaticConfiguration`), küçük (`systemSmall`)
    widget, teklif tutarlarının tek para birimine çevrilmesi (para birimi başına ayrı gösterilir), tamamlanan görevin
    widget'ta animasyonla kaybolması (sistem zaman çizelgesini yeniler).

## Gün sonu dışa aktarma — kararlar

1. **Akış.** Bugün ekranındaki "Ziyaretleri CRM için gönder" düğmesi (bugünkü ziyaretler bölümünde, ziyaret olmasa da
   görünür; başka bir günü seçip gönderebilmek için) bir sheet açar: **seçim → önizleme → gönderim**
   (`VisitExportFlowView`). Seçimde gün seçici (varsayılan bugün, gelecek seçilemez), "Aktarılmış ziyaretleri de göster"
   anahtarı ve onay daireli ziyaret listesi var; **aktarılmamışlar baştan seçili**, aktarılmışlar ("Aktarıldı" etiketli)
   listelenirse seçili gelmez, tek tek işaretlenip yeniden gönderilebilir. Gün değişince seçim o günün aktarılmamışlarına
   sıfırlanır; anahtar açılıp kapanınca seçim korunur (listeden çıkan seçimden düşer).
2. **Metin (`VisitReportFormatter`, saf mantık).** SPEC şablonu birebir: `=== ZIYARET n ===` (SPEC'te "İ" yok, aynen
   bırakıldı), Tarih, Firma, Şehir / İlçe, Görüşülen, Ziyaret tipi, Konu, Görüşme notu, Sonraki adım, Takip tarihi.
   - Tarih **gg.aa.yyyy**, takvimin saat dilimiyle (cihaz yerelinden bağımsız). Konu "Ziyaret Raporu – 24.11.2026"
     (tire: en dash U+2013).
   - **Boş alanın satırı atlanmaz, değeri "-" olur** (CRM'e alan alan yapıştırırken sıra şaşmasın). Boş not da
     "Görüşme notu:" altında "-".
   - Tek satırlık alanlarda satır sonları/art arda boşluklar tek boşluğa iner; **yalnızca görüşme notu çok satırlıdır**
     (satır sonları korunur, satır sonu boşlukları, baştaki/sondaki boş satırlar ve CRLF temizlenir).
   - Görüşülen: "Ad Soyad (Unvan), Ad Soyad"; adı boş kişi atlanır; sıra: birincil kişi önce, sonra ada göre.
   - Şehir / İlçe: ikisi doluysa "Bursa / Nilüfer", biri doluysa yalnızca o.
   - **Konu**: ziyaretin `topics` alanı (Faz 4'te yapay zekâ doldurur), boşsa bağlı fırsatın başlığı, o da yoksa "-".
     Ziyaret formunda "konu" girişi yok; şimdilik çoğu ziyarette "-" çıkar.
   - Görüşme notu `Visit.summary`'den gelir; ham ses metni (`transcript`) rapora girmez.
   - Bloklar seçili ziyaretlerin **eskiden yeniye** sırasıyla numaralanır ve aralarında bir boş satır bulunur.
3. **Önizleme.** Alıcı ve konu kartı (CRM adresi boşsa uyarı), her ziyaret için ayrı kart + "Kopyala" (1,5 sn
   "Kopyalandı"), altta "Gönder", "Tümünü kopyala", "Aktarıldı olarak işaretle" (onay sorar).
4. **Gönderim.** `MFMailComposeViewController` (alıcı Ayarlar'daki CRM e-postası, konu ve metin hazır). Mail hesabı yoksa
   (`canSendMail() == false`, simülatörde de böyle) **sistem paylaşım menüsü** açılır; konu `UIActivityItemSource` ile
   iletilir (Mail seçilirse konu dolu gelir).
5. **"Aktarıldı" ne zaman olur.** Yalnızca mail sonucu **`.sent`** ise (veya giden kutusuna alındıysa; taslak kaydetme ve
   iptal sayılmaz) ya da kullanıcı **"Aktarıldı olarak işaretle"** derse. **Paylaşım menüsü ve "Kopyala" otomatik
   işaretlemez** (kopyalamanın CRM'e yapıştırıldığını bilemeyiz; kullanıcı işaretler). Seçili ziyaretler
   `exportedToCRM = true`, `exportedAt = şimdi` olur; zaten aktarılmış olanlar yeniden gönderilince `exportedAt` yeni
   zamanla güncellenir. Kayıt `appDataDidChange` yayınladığı için Bugün ekranındaki "CRM'e aktarılmadı" sayısı, gün sonu
   hatırlatması (aktarılmamış kalmadıysa kalkar) ve widget'taki sayı kendiliğinden güncellenir (testle doğrulandı).
6. **Yapılmayanlar:** SPEC "Şablon ayarlardan değiştirilebilir" diyor; şablon düzenleme ayarı yapılmadı, yalnızca varsayılan
   şablon var (CRM zaten belirli bir biçime bağlı değil). Ziyaret formuna "Konu" alanı eklenmedi. Mail ekine dosya yok.
7. **Ekran görüntüleri (DEBUG):** `export` (seçim) ve `exportPreview` (önizleme), açık/koyu; örnek veride bugün 3 ziyaret
   (1'i aktarılmış, 2'si seçili) ve 2 kişili/çok satırlı notlu bir ziyaret var. Gönderim adımı (mail/paylaşım) görüntüde yok.
   **Elle denenmesi gerekenler (gerçek iPhone):** mail yazma ekranının dolu gelmesi, `.sent` sonrası işaretleme, mail
   hesabı yokken paylaşım menüsü, panoya kopyalanan metnin Windows'ta CRM'e yapıştırılması (satır sonları, Türkçe karakter).

## Ziyaret "Konu" alanı — kararlar

1. **Veri.** `Visit.topic: String` (varsayılan boş; hafif şema geçişi, CloudKit uyumlu). Mevcut `Visit.topics: [String]`
   (Faz 4'te yapay zekânın dolduracağı çoklu konu) **değişmedi ve artık hiçbir yerde okunmuyor**; Konu alanıyla
   karışmasın diye ayrı tutuldu. Formda kaydederken satır sonları/art arda boşluklar tek boşluğa indirilir (tek satır).
2. **Form.** "Konu" bölümü kişilerin altında: tek satır `FormTextField`, isteğe bağlı (boş olsa da kaydedilir).
   Altında "Önceki konular": **aynı müşterinin son 5 farklı konusu**, en yeni önce; boşlar ve büyük/küçük harf farkıyla
   tekrar edenler atlanır; formda zaten yazılı olan metin ve **düzenlenen ziyaretin kendi konusu önerilmez**; müşteri
   değişince öneriler yenilenir. Dokununca alana yazılır (üzerine yazar).
3. **Başlık kuralı** (`Visit.displayTitle`): konu; boşsa notun ilk dolu satırı; ikisi de yoksa başlık yok ve satır eski
   görünüme (tarih başlık) döner. Başlık notun ilk satırından geldiyse altta o satır tekrarlanmaz (`noteBelowTitle`).
   Dikte edilen not tek uzun paragraf olabildiğinden böyle bir ziyarette başlık 2 satırda kesilir. Başlık yalnızca
   müşteri detayındaki ziyaret geçmişi satırında gösteriliyor (müşteri detayı ve geçmiş aynı satırı kullanıyor);
   Bugün ekranı ve dışa aktarma seçim satırları değişmedi.
4. **Dışa aktarma.** "Konu" satırı yalnızca `Visit.topic`'ten gelir. Önceki karar (ziyaretin `topics` alanı, yoksa bağlı
   fırsatın başlığı) **kaldırıldı**: boş konu "-" olarak çıkar, sürpriz yok. Eski kayıtlarda Konu boş olacağı için
   geçmiş ziyaretler "-" ile gider; elle düzenlenebilir.
5. **SPEC.** "Şablon ayarlardan değiştirilebilir" ifadesi ve "Diğer ayarlar"daki "dışa aktarma şablonu" çıkarıldı
   (kullanıcı kararı: şablon düzenleme gerekmiyor). Veri modeli tablosuna `topic`, ziyaret kaydı adımlarına Konu eklendi.
6. **Ekran görüntüleri:** `screen-visitForm-*` / `screen-visitRecording-*` (Konu alanı + öneriler; örnek veride Örnek
   Makina'nın üç geçmiş konusu öneri çıkar) ve `screen-visitHistory-*` (konu başlıklı satırlar) CI'da yenilenir.

## Faz 2 — Fırsatlar — kararlar

1. **Aşama adı "Aday" değil "Yeni".** İstekte ilk aşama "Aday" yazıyordu; ama müşteri durumu zaten "Aday"
   (Mevcut / Aday / Pasif) ve karışmasın diye `OpportunityStage.lead` metni daha önce "Yeni" yapılmıştı (bkz. "Düzeltmeler
   ve Ayarlar ekranı" 2. madde). Aynı kararı korudum: Yeni, Nitelikli, Teklif verildi, Pazarlık, Kazanıldı, Kaybedildi.
   İstenirse tek satırlık değişiklik (`Enums.swift` → `OpportunityStage.title`). SPEC'e aşama adları eklendi.
2. **Sekme.** Fırsat/Teklif: üstte Fırsatlar / Teklifler seçici. Teklifler şimdilik "bir sonraki adımda" açıklamalı boş ekran.
   Fırsatlar aşama sırasıyla gruplanır; **boş gruplar gizlenir**. Başlık: "Teklif verildi (3)" + altında para birimi
   başına toplam ("480.000 ₺ · 12.500 $"; TL, USD, EUR sırası, tutarı 0 olanlar toplama girmez). Başlığa dokununca grup
   açılır/kapanır; **Kazanıldı ve Kaybedildi varsayılan kapalı** (kapalı grupta yalnızca başlık görünür). `Section(isExpanded:)`
   yalnızca kenar çubuğu stilinde çalıştığı için başlık düğmeyle elle yapıldı. Grup içi sıra: beklenen kapanış tarihi
   yakın olan önce, tarihsizler sonda, eşitlikte başlığa göre (Türkçe). Açık fırsatın kapanış günü geçtiyse tarih kırmızı.
3. **Form.** Müşteri (yeni kayıtta seçilir, düzenlemede sabit), başlık, açıklama, tahmini tutar, para birimi (TL/USD/EUR
   segmenti; yeni fırsatta **Ayarlar'daki varsayılan**, düzenlemede kayıtlı olan), aşama, beklenen kapanış tarihi
   (anahtarla; açılınca iki hafta sonrası önerilir). **Kaybedildi seçilince "Kayıp sebebi" alanı çıkar; isteğe bağlıdır**
   (boş bırakılabilir). Tutar metni `AmountParser` ile okunur: "1.250,50", "1250.5", "1.250" (binlik) hepsi kabul;
   boş = 0; ayrıştırılamayan tutarda alan kırmızı ve kaydet kapalı. Tarih gün başına yuvarlanır.
4. **Detay.** Başlık + müşteri bağlantısı (müşteri sekmesinde açar), tutar, kapanış, kayıp sebebi; aşama menüsü
   (Kaybedildi seçilince sebep sorulur, "Vazgeç" mümkün); açık kapanış hatırlatması varsa tarihi; bağlı ziyaretler
   (dokununca ziyaret düzenlenir); bağlı teklifler (şimdilik boş açıklama, teklif varsa numara + durum). Düzenle / Sil menüsü
   (sil: onay; bağlı ziyaretler silinmez, bağlantısı kalkar; hatırlatma görevi de silinir). Silme, müşteri silmedeki gibi
   önce ekrandan çıkıp 0,6 sn sonra yapılır.
5. **Müşteri detayı.** "Fırsatlar" bölümü doldu (aşama sırasıyla, aşama rozetli satırlar; dokununca fırsat detayı) ve
   "+ Fırsat ekle" (müşteri seçili gelir).
6. **Ziyaret formu.** Müşteri seçilince "Fırsat" bölümü: Bağlama / müşterinin **açık** fırsatları / "Yeni fırsat aç…"
   (başlık yazılır; kaydedince müşteri için "Yeni" aşamasında, Ayarlar'daki para biriminde fırsat açılır ve ziyarete
   bağlanır). Düzenlemede ziyaretin zaten bağlı olduğu fırsat kapalı olsa da listelenir; "Bağlama" ile bağ kaldırılır.
   Müşteri değişince seçim sıfırlanır. "Yeni fırsat aç" seçiliyken başlık boşsa kaydet kapalı.
7. **Kapanış hatırlatması (`OpportunityReminderService`).** Yeni `TaskSource.opportunityClose`; `FollowUpTask.opportunity`
   ilişkisi eklendi (`Opportunity.tasks`, silinince görevleri de silinir). Kurallar:
   - Yalnızca **açık** aşamada, kapanış tarihi olan ve ayarı açık fırsat için; vade = kapanış günü − X gün, hatırlatma
     saatinde. X = Ayarlar → Fırsatlar → "Kapanıştan N gün önce" (varsayılan 7, 1–60) ve aç/kapa anahtarı.
   - Kapanışa X günden az kaldıysa vade **bugünün hatırlatma saatine çekilir**; kapanış günü geçmişse hatırlatma kurulmaz.
   - Başlık "Fırsat kapanışı yaklaşıyor: <başlık> (<tarih>)"; bildirim başlığı müşteri adı.
   - **Kazanıldı/Kaybedildi olunca bekleyen hatırlatma silinir**; açık aşamaya dönülürse (tarih gelecekteyse) yeniden kurulur.
   - İki yol: `refresh(fırsat)` (form kaydı ve aşama değişimi: var olanı günceller) ve `sync` (**her hatırlatma
     hesaplamasında**, yani `ReminderScheduler`'ın içinde: eksikleri kurar, geçersizleri siler, **var olan açık
     hatırlatmaya dokunmaz** — kullanıcı ertelemiş olabilir). Tamamlanan hatırlatma aynı vade için yeniden kurulmaz.
     Ayarlardaki gün sayısı değişince mevcut açık hatırlatmaların tarihi değişmez (yalnızca yeni kurulanlar etkilenir).
8. **Ayarlar.** Yeni "Fırsatlar" bölümü: varsayılan para birimi (TL/USD/EUR; SPEC "Diğer ayarlar"da vardı, daha önce
   yoktu), kapanış hatırlatması anahtarı ve gün sayısı. Yeni `AppSettings` alanları App Group UserDefaults'ta.
9. **Veri.** Şema değişikliği: `FollowUpTask.opportunity?` ve `Opportunity.tasks?` (opsiyonel ilişki, hafif geçiş).
   `FollowUpTaskRepository.add` artık `opportunity:` alan beşli sürümü gerçekler; eski dört parametreli çağrı bir
   uzantıyla duruyor. Yeni `cancelOpenTasks(for: Opportunity)`.
10. **Ekran görüntüleri (DEBUG):** `opportunities` (liste), `opportunityDetail`, `opportunityForm` (açık fırsat düzenleme),
    `opportunityLost` (kayıp fırsat düzenleme: kayıp sebebi alanı), açık/koyu; ayrıca `detail` (müşteri detayında dolu Fırsatlar)
    ve `visitForm` (Fırsat bölümü) yenilenir. Örnek veri hayali: 7 fırsat, 5 aşama; ilk fırsat bir ziyarete bağlı.
11. **Yapılmayanlar:** teklifler (Faz 2'nin sonraki adımı), fırsat arama/filtre, görev saatini fırsat bazında değiştirme,
    kazanıldı olunca teklif/fırsat otomasyonu, widget'ta fırsat.
    **Elle denenmesi gerekenler:** grup başlığına dokunarak açma/kapama, Kaybedildi seçince sebep penceresi, tutar
    klavyesi (`.decimalPad` Türkçe cihazda virgül verir), ziyaret formundaki fırsat seçici.

## Faz 2 — Teklifler — kararlar

1. **Veri.** `Quote.lostReason` ("Kaybedildi'de sebep sorulsun" için; SPEC'te yoktu) ve `Quote.sentAt` (takip günleri
   gönderim anından sayılır; teklif tarihi gönderim tarihi değildir), `QuoteItem.position` (kalem sırası; `Quote.sortedItems`
   ve `items(for:)` önce `position`'a, eşitlikte eklenme sırasına göre). Hepsi varsayılan değerli, hafif şema geçişi.
   `QuoteItem.lineTotal` ve `Quote.totalAmount` artık **kuruşa yuvarlı** (`Money.rounded`): ekrandaki satır toplamlarının
   toplamı genel toplamla tutsun. `Quote.subtotalAmount` iskontosuz toplam. Tutarlar ekranda **iki kuruş haneli**
   (`AppFormat.moneyExact`, "1.250,50 ₺"); fırsat/özet gibi yerlerde eskisi gibi kuruşsuz.
2. **Durumlar.** Taslak → Gönderildi → Takipte → Kazanıldı / Kaybedildi; durum detaydan menüyle seçilir (yeni teklif Taslak
   açılır). **Gönderildi ve Takipte "bekleyen"dir** (`QuoteStatus.isPending`): takip/uyarı görevleri, listede geçerlilik
   vurgusu ve widget'taki bekleyen teklif sayısı yalnızca bunlar için. "Takipte"ye geçiş görev üretmez/değiştirmez
   (Gönderildi'de kurulanlar sürer); Taslak'tan doğrudan Takipte'ye geçilirse de ilk bekleyen geçiş sayıldığı için görevler kurulur.
3. **Takip görevleri (`QuoteReminderService`, `TaskSource.quoteFollowUp`).** Bekleyen duruma **ilk** geçişte `sentAt = şimdi`,
   görevler = gönderim günü + gün listesi, hatırlatma saatinde. Gün listesi: teklifin `followUpDays`'i doluysa o, boşsa
   Ayarlar'daki (varsayılan 3 ve 7). Geçmişte kalan günler için görev kurulmaz. Başlık "Teklif takibi: <no> · 3. gün";
   bildirim başlığı müşteri adı. Kazanıldı / Kaybedildi / Taslak olunca **bekleyen tüm takip ve uyarı görevleri silinir**
   (tamamlananlar geçmişte kalır); Kaybedildi/Kazanıldı'dan bekleyen duruma dönülürse `sentAt` yenilenir ve görevler yeniden kurulur;
   Taslak'a dönünce `sentAt` temizlenir (yeniden gönderilince sayaç baştan).
4. **Geçerlilik uyarısı (`TaskSource.quoteExpiry`).** `validUntil` − X gün (Ayarlar → Teklifler, varsayılan 3, aç/kapa),
   hatırlatma saatinde; X günden az kaldıysa bugüne çekilir; geçerlilik günü geçmişse veya tarih yoksa kurulmaz. Yalnızca
   bekleyen tekliflerde. Form kaydında tarih değişirse açık uyarı yeni tarihe taşınır.
5. **Tazeleme kuralları** (fırsat hatırlatmasıyla aynı mantık): kullanıcı işlemlerinde `refresh` (durum değişimi, gün listesi
   değişimi, form kaydı), her hatırlatma hesaplamasında `sync` (**eksiği kurar, geçersizi siler, var olan açık göreve
   dokunmaz**; kullanıcı ertelemiş olabilir). Takip için `sync` yalnızca teklifin hiç takip görevi (açık/tamam) yoksa kurar.
   Takip günleri değişince açık takipler silinip yeniden kurulur; **tamamlanmış** bir günün görevi aynı vade için yeniden
   kurulmaz. Ayarlardaki varsayılan günler sonradan değişirse mevcut görevler değişmez.
6. **Takip ayarları** (teklif detayı): "Ayarlardaki günleri kullan (3, 7)" anahtarı; kapatınca teklife özel günler
   düzenlenir ("Günleri uygula" veya Return). Geçersiz/tekrarlı günler (1–365 dışı) atılır; boş = varsayılan. Altında kurulu
   açık hatırlatmalar listelenir.
7. **Kazanıldı + fırsat.** Teklif Kazanıldı olunca bağlı fırsat varsa ve Kazanıldı değilse **onay penceresi** çıkar ("Evet,
   '…' Kazanıldı olsun" / "Hayır, fırsat kalsın"); Evet → `OpportunityService.setStage(.won)` (fırsatın kapanış hatırlatması da iptal
   olur). Hayır'da fırsata dokunulmaz. **Kaybedildi**'de sebep penceresi (isteğe bağlı sebep); fırsata dokunulmaz.
8. **Liste.** Fırsat/Teklif → Teklifler: yatay durum çipleri "Tümü (n), Taslak (n), Gönderildi (n), Takipte (n),
   Kazanıldı (n), Kaybedildi (n)". **Geçerliliği yaklaşan bölümü** (bekleyen + bitişe ≤ X gün kalan **veya süresi dolmuş**; X =
   Ayarlar'daki uyarı günü) en üstte, turuncu zeminli, "Geçerlilik: 2 gün kaldı" kalın + uyarı simgesi (süresi dolmuşsa kırmızı
   "Süresi dün doldu"); sıra: en çok gecikmiş/en yakın önce. Altında "Diğer teklifler" teklif tarihine göre yeniden eskiye.
   Filtre seçiliyken de aynı bölümleme uygulanır. Satır: no, toplam, müşteri, durum rozeti, geçerlilik.
9. **Form.** Teklif no (yeni teklifte **"T-2026-001" biçiminde öneri**: yıl içindeki en büyük sıra + 1; düzenlenebilir, benzersizlik
   zorlanmaz), tarih, geçerlilik (anahtar; varsayılan bir ay), müşteri (düzenlemede sabit), bağlı fırsat (müşterinin açık
   fırsatları + bağlı olan; fırsat detayından açılırsa seçili gelir), para birimi (varsayılan Ayarlar'dan), kalemler, notlar.
   Her kalem ayrı bölüm: katalog no, açıklama, adet (≥1 tam sayı), birim fiyat, iskonto % (0–100), satır toplamı canlı.
   **Kalem ekle**; kalem başlığındaki ⋯ menüsünden **yukarı/aşağı taşı** ve **sil** (sürükle-bırak yerine bu menü seçildi:
   Form içinde metin alanlarıyla düzenleme modu çakışıyor). Altta ara toplam, iskonto, genel toplam. Tamamen boş satırlar
   kaydedilirken atılır; geçersiz satır (kırmızı) kaydı engeller. Kalemler yerinde güncellenir (kimlik korunur).
10. **Listelendiği yerler.** Müşteri detayı → "Teklifler" (yaklaşanlar önce) + "+ Teklif ekle"; fırsat detayı → "Bağlı teklifler"
    (+ Teklif ekle: müşteri ve fırsat seçili). Üç gezinme yığını (Fırsat/Teklif, Müşteriler) `Quote` hedefini bilir.
11. **Widget.** Büyük widget'ın bekleyen teklif sayısı/toplamı zaten depodan okunuyordu (`WidgetDataLoader`: Gönderildi + Takipte,
    para birimi başına toplam); teklifler artık gerçekten girilebildiği için gerçek veriden gelir. Teklif kaydı da
    `reloadAllTimelines()` tetikler (repository kaydı). Testle doğrulandı (durum değişince sayı/toplam düşer).
12. **Ayarlar.** Yeni alan yok (takip günleri ve geçerlilik uyarısı alanları Ayarlar → Teklifler'de zaten vardı; artık
    kullanılıyor, fırsat bölümü varsayılan para birimini sağlıyor).
13. **Ekran görüntüleri (DEBUG):** `quotes` (liste), `quoteDetail`, `quoteForm` (kalemli teklif düzenleme), açık/koyu; örnek veride 6 teklif
    (geçerliliği 2 gün kalan, süresi dolmuş, taslak USD, kazanılmış, kaybedilmiş…). Bugün/`detail`/`opportunityDetail`
    görüntüleri yeni teklif ve hatırlatmalarla yenilenir.
14. **Yapılmayanlar:** PDF/e-posta ile teklif gönderme, teklif kopyalama, kalemleri katalogdan seçme, KDV/vergi, teklif
    numarası benzersizliği, sürükle-bırak sıralama, Takipte'ye otomatik geçiş (ilk takip tamamlanınca), fırsat aşamasını
    teklif gönderilince otomatik "Teklif verildi"ye çekme.
    **Elle denenmesi gerekenler:** kalem alanlarında klavye (adet `numberPad`, tutarlar `decimalPad`) ve form kaydırması,
    ⋯ menüsüyle taşıma, durum menüsü + Kaybedildi/Kazanıldı pencereleri, vurgulu satır renkleri açık/koyu modda.

## Ekran görüntüsü düzeltmeleri + widget/ziyaret formu (kararlar)

1. **"+ Ziyaret" butonu.** `safeAreaInset` içeriğin son satırlarını yine de kapatıyordu; buton artık `overlay` (sağ alt) ve
   kaydırılabilir içeriğin alt boşluğu `contentMargins(.bottom, 76, for: .scrollContent)` ile buton yüksekliği kadar
   artırıldı (`VisitButtonModifier.reservedHeight`). Buton **Ayarlar ve Şehirler ekranlarından kaldırıldı**; form/sheet
   ekranlarında zaten yok (butonu yalnızca liste/detay kökleri ve Harita yer tutucusu kullanır, sheet ayrı sunum hiyerarşisidir).
2. **CRM başlığı "=== ZİYARET n ===".** Büyük harf elle yazıldığı için noktalı İ de elle yazıldı (SPEC örneği dahil). Test:
   `testBlockHeaderUsesTurkishDottedCapitalI` (başlık tam eşitlik + `uppercased(with: tr_TR)` ile aynı + düz "ZIYARET" yok).
3. **Tutar alanları binlik ayraçlı.** `AmountTextField` (FormFields) yazarken `AmountParser.formatTyping` ile biçimler:
   noktalar binlik sayılıp yeniden hesaplanır, virgül ondalık (en çok 2 hane, sondaki virgül korunur), sona yeni yazılan tek nokta
   ondalığa çevrilir, yabancı karakterler atılır. Düzenleme açılışı `groupedEditingText` ("480.000", "142.500"). Kaydederken
   metin `AmountParser.parse` ile sayıya döner (biçimlenmiş metnin gidiş-dönüşü testli). Uygulandığı yerler: fırsat tahmini
   tutarı ve teklif kalemi birim fiyatı. İskonto % ve adet alanları ayraçsız kaldı. **Bilinen sınır:** imleç yazarken sona atlar
   (ortadan düzeltme yaparken); klavye, cihaz bölgesine göre "," veya "." tuşunu sunar — ikisi de desteklenir.
4. **Teklif listesi başlığı** "Geçerlilik uyarısı" (yaklaşanlar + süresi dolanlar).
5. **Bugün → ziyaret satırı:** saatin altında "Aktarıldı" / "Aktarılmadı" etiketi (simge yine var; durum artık yazıyla da okunur).
6. **Gezinme çubuğu arka planı:** kaydırınca beyaza dönen şey `AppAppearance`'ta `configureWithDefaultBackground()` (bulanık sistem
   zemini) idi. `standardAppearance`/`compactAppearance` artık opak ve `background` renginde, gölge çizgisi yok. Bu UIKit
   görünümü tüm yığınları ve sheet'leri kapsar; ekran başına `toolbarBackground` yazmaya gerek kalmadı (aynı sonuç, tek yer).
7. **Teklif no çakışma uyarısı:** `QuoteFormModel.duplicateNumberQuote` (büyük/küçük harf ve boşluk yok sayılır; düzenlenen teklifin
   kendisi hariç). Form başlık bölümünün altında turuncu/kırmızı uyarı + müşteri adı; **kaydetmeyi engellemez**. **"KDV hariç"**
   notu (`ExcludingVATAmount`): teklif detayında üstteki ve alttaki "Genel toplam", formda "Genel toplam" yanında/altında.
8. **Ziyaret formu sırası:** Müşteri → Görüşülen kişiler → **Görüşme notu** (büyük yuvarlak mikrofon butonu, canlı metin, durum
   mesajları, hemen altında not alanı) → Konu → Sonraki adım → Fırsat → Ziyaret tipi/tarih. Kayıtta mikrofon halkalıdır ve
   yanında Duraklat/Bitir görünür; ayrı "Sesli not" bölümü kalktı. Ekran görüntüleri: `screen-visitForm-*` (not bölümü üstte,
   dolu) ve `screen-visitRecording-*` (sahte motor canlı metni, mikrofon aktif).
9. **Kilit ekranı dikdörtgen widget'ı:** 1. satır görev başlığı (kalın, tek satır, öncelikli); 2. satır "Firma · tarih/saat";
   gecikmişse başta uyarı simgesi ve "Gecikmiş · 23 Kas". Dar yerde önce firma adı kısalır, tarih/saat sabit kalır.
   "Sıradaki iş" üst satırı kaldırıldı (boş durumda kalır).
10. **Büyük widget yüksekliği doldurur:** satır yükseklikleri sabit (başlık 16, görev 22, aralık 5); `GeometryReader` ile kalan
    yüksekliğe sığdığı kadar satır, kalanlar "+N takip daha" (`WeekWidgetLayout.fit`, testli). Sona yalnız kalan gün başlığı
    atılır. **Not:** yüksekliklere sabit değer verildiği için çok büyük Dynamic Type'ta satırlar kırpılabilir.
11. **Orta widget:** gecikmiş görevlerin sağında "Gecikmiş" yerine tarih ("23 Kas Pzt", overdue renginde); üstteki
    "N gecikmiş" sayacı duruyor.

**Elle denenmesi gerekenler (gerçek iPhone):** tutar alanında yazarken ayraç ve imleç davranışı, büyük mikrofon butonu ile izin
akışı, widget'ların gerçek ana/kilit ekranında yerleşimi (özellikle büyük widget'ın alt kenarı).

## Faz 3 – Bölge (kararlar)

**Önce:** `claude/ui-fixes` PR #7 ile main'e birleşti. Yeni dal `claude/region`.

0. **Tutar alanında imleç.** `AmountTextField` artık `UITextField` sarmalayıcı (SwiftUI `TextField` imleci okutmuyor). Her tuş vuruşunda
   `AmountParser.formatTyping(_:cursor:previous:)` metni biçimler ve imleci aynı "anlamlı karakter"in (rakam + ilk virgül) sağında tutar;
   binlik noktaları imleç sayımına girmez. Ortadan yazma/silme, yeni noktanın imleçten önce çıkması, baştaki sıfırın atılması,
   sona yazılan noktanın virgüle dönmesi `AmountCursorTests`'te. **Elle denenmesi gerekir:** gerçek klavyede ortadan düzeltme ve
   yapıştırma.
1. **Harita yok.** MapKit/CLGeocoder/konum/yol tarifi kapsam dışı; SPEC'teki harita bölümü ve satırları ("Harita" teknoloji satırı, pin/yol
   tarifi, "adresten koordinat", "konuma en yakın müşteri") kaldırıldı/yeniden yazıldı. `latitude/longitude` alanları şemada durur
   (CloudKit şemasını bozmamak için silinmedi) ama kullanılmaz. "Haftalık şehir planı" bu turda yapılmadı.
2. **Bölge sekmesi** (`AppTab.region`, simge `square.grid.2x2`): şehirler → ilçeler → OSB'ye göre müşteriler (`RegionView`).
   Mantık `RegionBuilder` (saf, testli); durum `RegionModel`. Şehir listesi Ayarlar'daki sıra + müşterisi olmayan şehirler (0) +
   bölge dışı şehirler (alfabetik) + şehri boş müşteriler ("Şehir belirtilmemiş", en sonda). İlçe satırı yalnızca müşterisi olan
   (filtreye göre) ilçeleri gösterir; "İlçe belirtilmemiş" en sonda. İlçe içinde OSB grupları alfabetik, **OSB'siz müşteriler en sonda ayrı
   grup**, grup içinde ada göre. Her satırda müşteri sayısı + bekleyen teklif + gecikmiş takip (gecikmiş = bugünden önce vadeli,
   tamamlanmamış). Şehir/ilçe/OSB eşleşmesi büyük/küçük harf ve Türkçe karakter duyarsızdır ("bursa" = Bursa, " Bursa  OSB " = "Bursa OSB").
   "+ Ziyaret" butonu üç seviyede de var.
3. **Filtreler (her seviyede aynı, VE ile):** Durum, Değerlendirme (menü çipleri), Teklif bekleyen (Gönderildi/Takipte),
   Ziyareti geçen, Migrasyon fırsatı. **"Ziyaret sıklığı aşılan" tanımı:** son ziyaretten (hiç yoksa eklenme tarihinden) bu yana geçen
   takvim günü ≥ değerlendirmenin eşiği (Ayarlar: Önemli 30 / Potansiyelli 60 / Zayıf 120); pasifler hariç — `VisitFrequencyService` ile aynı
   referans. Eşiğe **ulaşan** da dahil ("tam 30. gün" listelenir). Sayılar filtreye göre güncellenir; filtre sekmeyi değiştirince korunur,
   "Temizle" ile sıfırlanır.
4. **İlçe listeleri:** `DistrictCatalog` (Shared/Data, gömülü): Çanakkale 12, Balıkesir 20, Bursa 17, Bilecik 8, Yalova 6, Eskişehir 14, Kütahya 13,
   Afyonkarahisar 18 ilçe (testte sayılar doğrulanır). Merkez ilçesi "Merkez" adını taşıyan şehirlerde (Çanakkale, Bilecik, Yalova, Kütahya,
   Afyonkarahisar) "Merkez" listede; Balıkesir (Altıeylül, Karesi), Bursa (Nilüfer, Osmangazi, Yıldırım), Eskişehir (Odunpazarı, Tepebaşı)
   ilçeleriyle. "Afyon" kısa adı Afyonkarahisar'a eşlenir. **Resmi liste kaynağı bilgi birikimimizdir; yayına çıkmadan önce güncel il/ilçe
   listesiyle (ör. MERNİS/Nüfus ve Vatandaşlık) karşılaştırılmalı.**
5. **Müşteri formu:** şehir katalogdaysa İlçe bir seçici (Seçiniz + liste + "Diğer…"); "Diğer…" elle yazma alanı açar. Listede olmayan şehirde (yeni
   eklenen veya şehir seçilmemiş) serbest metin. Şehir değişince yeni şehrin listesinde olmayan ilçe temizlenir. Düzenlemede kayıtlı ilçe listedekiyle
   yalnızca yazım farkıyla eşleşiyorsa resmi yazıma çekilir; listede olmayan değer "Diğer" olarak açılır.
6. **Mevcut kayıtlar:** `DistrictMigration` uygulama açılışında çalışır (kayıtlı ilçe, şehrin listesindeki resmi yazımla eşleşiyorsa o yazım yazılır:
   "Nilufer" → "Nilüfer"); **eşleşmeyenler ve listede olmayan şehirler dokunulmaz**. Tekrar çalıştırmak zararsız (yalnızca farklı yazılanlar değişir).
   Bölge ekranı gruplamada da aynı eşleştirmeyi kullanır; yani göçten önce bile "nilufer" ve "Nilüfer" tek ilçe görünür.
7. **Müşteriler listesi:** filtre menüsüne İlçe eklendi (seçenekler verideki ilçeler, şehir seçiliyse yalnızca o şehrinkiler, aynı ilçenin yazımları
   tek seçenek). Şehir değişince ilçe filtresi sıfırlanır.
8. **Ekran görüntüleri (DEBUG):** `region` (şehirler), `regionCity` (Bursa ilçeleri), `regionDistrict` (Bursa/Nilüfer: "Bursa OSB" grubu ve "OSB belirtilmemiş"
   grubu), açık/koyu. Bu sahnelere özel `SampleData.loadRegionShowcase` (ek hayali Bursa müşterileri; temel örnek veri ve diğer testler değişmedi).
   `PlaceholderView` (Harita yer tutucusu) silindi.
9. **Yapılmayanlar:** harita/konum/yol tarifi, haftalık şehir planı, CSV içe aktarma, bölgeler arası toplu karşılaştırma. Bölge ekranında arama yok.

## Durum günlüğü (devam)

- Düzeltmeler + Ayarlar ekranı: CI ilk denemede yeşil (60 test), görüntüler elle incelendi.
- Ziyaret kaydı: CI ilk denemede yeşil (87 test; 24 ekran görüntüsü, `screen-visit*`). Ekranlar elle incelendi.
  **Elle denenmesi gerekenler (gerçek iPhone):** mikrofon/konuşma tanıma izin akışı, Türkçe canlı metin, duraklat/devam,
  1 dakikayı aşan kayıt (otomatik parçalama), izin reddedilince klavyeyle yazma.
- Bu noktada duruldu; sıradaki iş için yeni talimat bekleniyor.

## Faz 3b – CSV ile müşteri içe aktarma (kararlar)

- **Bölge filtre çubuğu (adım 0):** çubuk zaten yatay kaydırılabilir; üstteki boşluk `listSectionSpacing(.compact)` + `contentMargins(.top, 0)` ile kapatıldı. Sağ kenardaki "kırpılma" kaydırılabilir şeridin doğal görünümüdür.
- **Kodlama/ayraç:** önce UTF-8 (BOM atılır), olmazsa Windows-1254. Ayraç ilk satırdaki tırnak dışı `;` / `,` / sekme sayısına göre seçilir; eşitlikte `;`.
- **Eşleme:** başlıklar küçük harf + Türkçe karakter sadeleştirilip bilinen yazımlarla (tam, sonra "içerir") eşlenir; her sütun tek alana gider. Firma eşlenmeden "Önizle" kapalı.
- **Çakışma:** aynı firma adı + şehir (büyük/küçük harf, Türkçe karakter, fazla boşluk duyarsız). Şehir yazımı bölge listesi/kataloga göre resmî ada çevrilerek karşılaştırılır. Çakışanlar için toplu "Atla / Güncelle" (satır bazında seçim yok). Güncelle: yalnızca dolu CSV alanları üstüne yazar; durum ve değerlendirme değişmez.
- **Hatalı:** firma adı boş, e-posta biçimi geçersiz, dosyada aynı firma+şehrin tekrarı (ilk satır geçerli, sonrakiler hatalı).
- **Yeni müşteri:** durum "Aday", değerlendirme önizlemedeki seçim (varsayılan Potansiyelli). İlçe şehrin resmî listesiyle eşleştirilir, eşleşmezse olduğu gibi.
- **Telefon/e-posta:** Customer'da bu alanlar yok; Contact'a yazılır. Yetkili adı yoksa "Genel" adlı kişi açılır. Aynı adlı kişi varsa yenisi eklenmez (boş telefon/e-posta doldurulur).
- **Şablon:** Ayarlar → "İçe aktarma" → ShareLink; UTF-8 + BOM, `;` ayraçlı (Türkçe Excel'de doğrudan açılır).
- Giriş noktası: Müşteriler üst çubuğundaki indirme simgesi (Dosyalar'dan CSV seçimi).

## Faz 3c – Haftalık şehir planı (kararlar)

- **Saklama:** `AppSettings.cityPlan` (gün anahtarı `yyyy-MM-dd` → şehirler, App Group UserDefaults). Hafta kavramı yok; her gün bağımsız anahtar olduğundan "her hafta yeniden atanır" kendiliğinden sağlanır. 28 günden eski kayıtlar atılır. Ayar değişince hatırlatma motoru zaten yeniden planlar (sabah özeti güncellenir).
- **Şerit:** Bugün listesinin ilk bölümü (listeyle birlikte kayar). Hafta içi: bu hafta Pzt–Cum; Cumartesi/Pazar: gelecek hafta gösterilir ("Gelecek hafta"). Günde ilk şehir + "+N" görünür. "Geçen haftayı kopyala": önceki haftanın (7 gün öncesi) atamalarını bu haftanın üstüne yazar (önceki hafta boş olan gün boşalır); önceki hafta boşsa düğme pasif.
- **Gün sayfası:** şehirler çoklu seçilir (Ayarlar'daki sorumlu şehirler), sonra "Önerilen ziyaretler".
- **Öncelik sırası (SPEC):** 1) gecikmiş takip, 2) geçerliliği yaklaşan teklif, 3) ziyaret sıklığı aşılan, 4) açık fırsat, 5) hiç ziyaret edilmemiş aday. Müşteri en güçlü nedenine göre sıralanır, tüm nedenler satırda (ilk ikisi) yazar. Aynı katmanda önemli → potansiyelli → zayıf, sonra ada göre. Neden yoksa öneri yok; pasifler önerilmez.
  - "Gecikmiş takip" sayımına ziyaret sıklığı ve teklif geçerlilik görevleri girmez (kendi katmanları var) ve "Ziyaret: …" plan görevleri girmez (plan kendini beslemesin).
  - "Geçerliliği yaklaşan": bekleyen (Gönderildi/Takipte) teklif, bitişe ≤ ayardaki uyarı günü; süresi dolmuş bekleyen teklif de dahil ("Teklif süresi doldu").
  - Ziyaret sıklığı: Bölge filtresiyle aynı kural (eşik gün dahil, pasif hariç).
- **Plana ekle:** "Ziyaret: <firma>" adlı, o güne, ayardaki hatırlatma saatinde, kaynağı "manuel" bir FollowUpTask. Aynı gün aynı müşteri için açık görev varsa tekrar eklemez; satırda "Planlandı" görünür. Bildirimi mevcut görev bildirimi üretir.
- **Sabah özeti:** günün şehri planlıysa ilk satır "Bugün Bursa, Yalova: 3 planlı ziyaret" (ya da "planlı ziyaret yok"), altına her zamanki takip özeti. Planlı ziyaret sayısı o gün vadeli "Ziyaret: " görevleridir. Şehri planlı ama işi olmayan gün için de özet gönderilir. Plan yoksa metin eskisi gibi.

## Faz 3d – Kurulu baz (kararlar)

- **Model zaten vardı** (InstalledProduct, `hasMigrationOpportunity`, Bölge'deki migrasyon filtresi); bu fazda ekran, ayar ve akışlar eklendi.
- **Yaşam döngüsü adları:** Aktif / Aktif (olgun) / **Üretim sonu** (eskiden "Ömrünü tamamlıyor") / Üretimden kalktı. Ham değerler (`endOfLife` vb.) değişmedi, veri göçü gerekmedi.
- **Müşteri detayı → Kurulu baz:** satıra dokun = düzenle, sola kaydır = sil (onaylı), "Ürün ekle", satırda "Fırsat aç". Katalog no zorunlu, adet ≥ 1.
- **Ürün aileleri (Ayarlar → Kurulu baz):** ad + varsayılan yaşam döngüsü + not; düzenlenebilir/silinebilir/eklenebilir, App Group UserDefaults'ta JSON. Örnekler: PLC-5 (Üretimden kalktı), SLC 500 (Üretim sonu), ikisinde de "Rockwell yaşam döngüsü sayfasından doğrulayın" notu. **Bu iki durumu kendi bilgimle seçtim; yayından önce Rockwell sayfasıyla doğrulayın.** Liste hiç kaydedilmemişse örnekler gelir; boş liste bilinçli seçim sayılır.
- **Aile seçimi:** formda listeden seçilince yaşam döngüsü ailenin varsayılanına çekilir, sonra elle değiştirilebilir. "Diğer…" ile serbest aile adı yazılır; serbest ad yaşam döngüsünü değiştirmez. Mevcut ürünü açmak yaşam döngüsünü ezmez.
- **Migrasyon etiketi:** Üretim sonu / Üretimden kalktı ürünü olan müşteride detayda ve müşteri satırında "Migrasyon fırsatı". Müşteriler filtre menüsüne "Migrasyon fırsatı olanlar" anahtarı eklendi (diğer filtrelerle VE).
- **Fırsat aç:** fırsat formu müşteri seçili, başlık "<aile> migrasyonu" (aile yoksa katalog no), açıklama "Ürün: <katalog> (<aile>) / Adet / Yaşam döngüsü / Not" satırları. Tutar boş (0), kullanıcı doldurur; kaydet'e basılana dek hiçbir şey oluşmaz.

## Faz 4a – Kartvizit okuma (kararlar)

- **Tamamen cihaz üstü ve ücretsiz:** canlı tarama VisionKit `DataScannerViewController` (yalnızca metin). Cihaz desteklemiyorsa (ör. simülatör) ya da kamera izni yoksa "Fotoğraftan seç" (PhotosPicker) + Vision `VNRecognizeTextRequest` açılır; canlı ekranda da fotoğraf seçilebilir. Canlı taramada "Metni al"a basınca o an tanınan parçalar yukarıdan aşağıya okunur. Fotoğraf kaydedilmez.
- **Dil:** istenen `tr-TR` + `en-US`; Vision'da istek, cihazın `supportedRecognitionLanguages()` listesine süzülür (desteklenmeyen dil isteği hata verdirmesin; Türkçe yoksa `en-US` ile okunur, Türkçe karakterler bozulabilir). **Gerçek kartvizitlerle gerçek iPhone'da denenmeli.**
- **Ayrıştırma (`BusinessCardParser`, saf mantık):** telefon ve web `NSDataDetector`, e-posta düzenli ifade; adres anahtar sözcüklerle (Mah./Sok./Cad./No:/posta kodu/şehir içeren "/"/OSB), `NSDataDetector` adresi yalnızca rakamlı ve başka türlü sınıflanamayan satırda yedek (Türkçe adreste güvenilmez). Firma: A.Ş., Ltd. Şti., Sanayi, Ticaret, San./Tic. (kısaltma yalnızca noktalı ya da ≥ 3 sözcüklü satırda; "Ali San" soyadı firma sanılmasın) > sektör sözcüğü (Makina, Otomasyon, Mühendislik…) > ad seçilmeyen satır. Unvan sözcük bazında eşleşir ("Mühendisi" unvan, "Mühendislik" değil). Ad: unvanın hemen üstündeki "Ad Soyad" biçimli satır; TAMAMI BÜYÜK ad Türkçe kurallarla düzeltilir. Telefon: cep varsa o, faks atlanır, diğerleri kişi notuna. Şehir/ilçe adresten (son geçen şehir) tahmin edilir.
- **Eşleştirme:** büyük/küçük harf ve Türkçe karakter duyarsız tam ad; olmazsa A.Ş./Ltd. Şti./San./Tic./ve gibi yasal ekler atılarak (ör. "ÖRNEK MAKİNA SAN. VE TİC. A.Ş." = "Örnek Makina A.Ş."). Sonuç formunda firma adı düzeltildikçe eşleşme canlı güncellenir.
- **Sonuç formu:** ana düğme altta sabit. Eşleşme varsa "Bu müşteriye kişi olarak ekle" (ad boşsa pasif; aynı adlı kişi varsa uyarır, engellemez). Yoksa "Yeni müşteri oluştur": müşteri formu dolu açılır (durum Aday), kaydedilince karttaki kişi de eklenir.
- **Müşteri detayından** açılırsa kişi doğrudan o müşteriye eklenir; karttaki firma adı farklı görünüyorsa uyarı çıkar.
- **Web adresi:** modelde alan yok; yeni müşteride müşteri notuna, mevcut müşteriye eklemede kişi notuna "Web: …" yazılır.
- **Giriş noktaları:** Müşteriler üst çubuğu (kartvizit simgesi) ve müşteri detayı → Kişiler → "Kartvizit tara". İzin metni `NSCameraUsageDescription` (Türkçe).
- **Ekran görüntüleri:** `screen-cardResult-*` (eşleşen firma) ve `screen-cardResultNew-*` (yeni firma), hayali kartvizit metinleriyle.
- **Elle denenmesi gerekenler (gerçek iPhone):** kamera izni, canlı taramada Türkçe karakterler, fotoğraftan okuma, izin reddedilince yedek yol.

## Faz 4b – Claude ile not düzenleme (kararlar)

- **API yok:** `NoteAssistant` protokolü `.handoff(text)` (kullanıcı metni götürür) veya `.suggestion(NoteSuggestion)` (doğrudan öneri) döndürür. Şimdiki uygulama `ShareToClaudeAssistant` (`.handoff`); ileride API uygulaması `.suggestion` döndürür, form ve önizleme aynı kalır. Seçim `AppContext.noteAssistant`.
- **Gönderilen metin:** talimat + bugünün tarihi (GG.AA.YYYY) + müşteri adı + işaretli kişiler ("Ad (Unvan)") + "Ham not:" + formdaki not. SPEC'teki "kurulu baz" girdisi istenmediği için eklenmedi. Aynı anda panoya kopyalanır ve sistem paylaşım menüsü açılır. Düğme müşteri seçili ve not doluyken etkin; açık sesli kayıt önce bitirilir.
- **Yapıştırma:** `UIPasteboard` okunur; iOS başka uygulamadan kopyalanan metin için izin sorabilir (sistem `PasteButton`ı düğme adını değiştirtmediği için kullanılmadı). Panoda hâlâ bizim gönderdiğimiz metin varsa uyarılır (gönderilen metin de şablonu içerdiği için cevap sanılmasın).
- **Ayrıştırma (`ClaudeReplyParser`):** etiketler büyük/küçük harf ve Türkçe karakter duyarsız; Markdown süsleri ve şablon dışı metin tolere edilir. **"Özet" yoksa ya da boşsa şablon bozuk sayılır:** metnin tamamı nota, uyarıyla; diğer alanlar değişmez. Diğer alanların eksikliği hata değildir. "-", "Yok", "(yoksa boş)" boş sayılır. Tarih: GG.AA.YYYY, `/` ve `-`, iki haneli yıl, YYYY-AA-GG, "4 Aralık [2026]", "04.12" (yılsız geçmiş tarih gelecek yıl); anlaşılamayan veya geçersiz tarih uyarı verir.
- **Onay:** önizlemede "Forma uygula" denmeden form değişmez. Boş gelen alanlar formdaki değeri silmez; not Özet ile değiştirilir. Ziyaret yine ancak "Kaydet" ile kaydedilir.
- **Ham not:** uygulamadan hemen önce formdaki not `Visit.transcript`'e eklenir (dikte metni zaten oradaysa tekrarlanmaz; önceki öneri değiştirilmeden duruyorsa eklenmez). Formda "Ham not (saklanıyor)" açılır alanından görülür. CRM raporuna girmez.
- **Ayarlar → Claude ile düzenleme → Claude talimatı:** düzenlenebilir, "Varsayılana dön" (onaylı). Varsayılana eşit metin saklanmaz; boş bırakılırsa varsayılan gönderilir.
- **Bilinen sınır (toparlama turunda giderildi):** iOS uygulamayı arka planda kapatırsa form kayboluyordu; artık ziyaret taslağı saklanıyor (aşağıda).
- **Ekran görüntüleri:** `screen-claudeButtons-*`, `screen-claudePreview-*`, `screen-claudeBroken-*`, `screen-settingsClaude-*`.
- **Elle denenmesi gerekenler (gerçek iPhone):** paylaşım menüsünde Claude uygulamasının çıkması ve metnin gelmesi, cevabı kopyalayıp yapıştırma (izin penceresi), Claude'un şablona uyması.

## Durum günlüğü – Faz 4

- 4a: CI ilk denemede yeşil (416 test). PR #12. İlk koşuda döngünün ilk senaryosunun görüntüsü erken alındı; yeni senaryolar döngünün sonuna taşındı.
- 4b: derleme ve testler ilk denemede yeşil (437 test). Yalnızca `claudePreview` görüntüsü önizleme açılmadan alınmıştı: 2. denemede Claude senaryolarının beklemesi 12 sn yapıldı, ama iş 30 dk sınırını aşıp iptal oldu (yavaş runner; önceki yeşil koşu da 27,5 dk). 3. denemede sınır 45 dk yapıldı: yeşil ve görüntüler doğru. **Dikkat:** ekran görüntüsü döngüsü işin yarıdan fazlasını alıyor; senaryo sayısı artarsa döngüyü ayrı işe bölmek gerekebilir.
- Gerçek iPhone denemesi yapılmadan SPEC'e göre Faz 4 kapanmış sayılmaz. "Müşteri değerlendirme önerisi" (SPEC → Yapay zekâ) bu turun kapsamında değildi, yapılmadı.

## Toparlama turu – ziyaret taslağı (kararlar)

- **Nerede:** uygulamanın Application Support klasöründe tek dosya (`visit-draft.json`); App Group'a, buluta veya yedeğe girmez. Aynı anda tek form açılabildiği için tek taslak yeterli.
- **Ne zaman yazılır:** değişiklikten en geç 1 sn sonra (art arda değişiklikler birleşir; bekleyen yazma ertelenmez, yoksa aralıksız konuşurken hiç yazılmazdı). Uygulama arka plana giderken beklemeden yazılır (Claude'a geçiş senaryosu). Sesli notun henüz teslim edilmemiş canlı metni de taslağa girer.
- **Ne taslak sayılır:** yeni ziyarette metin, işaretli kişi veya takip tarihi; yalnızca müşteri seçmek sayılmaz. Düzenlemede açılıştaki halden her fark. Değişiklik geri alınırsa taslak silinir.
- **Ne zaman silinir:** "Kaydet" ve onaylanan "İptal" ("Kaydedilmemiş ziyaret notu silinsin mi?"). Değişiklik varken form kaydırarak kapatılamaz. Form başka yoldan kapanırsa taslak durur ve soru hemen sorulur.
- **Soru:** açılışta "Yarım kalan ziyaret notu var" → "Devam et" / "Sil". Yanıtlanana kadar widget'ın "+ Ziyaret" bağlantısı form açmaz. "Devam et"ten sonra taslak, form kaydedilene kadar diskte durur.
- Faz 4b'deki "uygulama kapanırsa form kaybolur" sınırı bununla kalktı (en fazla son ~1 sn kaybolabilir).

## Toparlama turu – CI (kararlar)

- **`build.yml`:** her dalın her push'unda iki iş: birim testleri ve FreeDevice cihaz derlemesi (+ kimlik/yetki doğrulaması, `scripts/ci/check-freedevice.sh`). Aynı repodan açılan PR'da `pull_request` işleri atlanır (aynı commit iki kez derlenmesin); fork PR'larında çalışır.
- **`screenshots.yml`:** yalnızca `main`'e push, `screenshots` etiketli PR veya elle. Bir iş uygulamayı derleyip widget görüntülerini üretir; simülatör görüntüleri üç paralel parçada çekilir (`scripts/ci/screenshots.sh`; yeni senaryo betikteki listeye eklenir). Artifact'ler: `screenshots-widgets`, `screenshots-1..3`; 14 gün saklanır.
- FreeDevice derlemesi ayrıca Release türü derlemeyi de ilk kez CI'ya sokar (DEBUG koduna yanlışlıkla bağımlılık yakalanır).

## Toparlama turu – FreeDevice (kararlar)

- **Yapılandırma:** `project.yml` → `configs.FreeDevice` (Release türü; örnek veri ve DEBUG senaryoları derlenmez), şema `SahaSatis-FreeDevice`. Kimlikler `com.kadyxx.sahasatis[.widget]`, `group.com.kadyxx.sahasatis`. Debug/Release kimlikleri değişmedi.
- **Yetkiler:** uygulama yetki dosyaları artık XcodeGen üretmiyor, `Config/` altında elle duruyor (yapılandırmaya göre dosya seçebilmek için). Normal dosyanın içeriği öncekiyle aynı; FreeDevice dosyasında yalnızca App Group var. Widget yetkisi (yalnızca App Group) değişmedi.
- **Kod:** uygulamada zaten CloudKit veya Sign in with Apple kodu yok (`cloudKitDatabase: .none`), bu yüzden yetkileri kapatmak davranışı değiştirmiyor. App Group klasörü alınamazsa (`AppGroup.isAvailable`) depo uygulamanın kendi klasöründe açılır, widget depo açmadan boş durum gösterir.
- **Sınır:** App Group'lu ve App Group'suz kurulumda veri farklı yerdedir; geçiş yedekle/geri yükle ile yapılır (rehberde yazılı). Ücretsiz hesapla gerçek imzalama ve cihaza kurulum CI'da denenemez; Mac'te ilk kurulumda doğrulanacak.

## Toparlama turu – yedekleme (kararlar)

- **Kapsam:** 8 modelin tüm kayıtları, ilişkileri (id ile) ve ayarlar (profil, şehirler, hatırlatmalar, haftalık plan, ürün aileleri, CRM adresi, Claude talimatı). Girmeyenler: son yedek tarihi ve yarım kalan taslak (cihaza ait).
- **Biçim:** `SahaSatis-Yedek-YYYY-AA-GG-SSDD.json`, `format`/`version` başlıklı; tarihler kayıpsız (sayısal). Test, modele eklenip yedeğe eklenmeyen alanı yakalar. İleride eklenen alanlar eski yedekler açılsın diye opsiyonel olmalı.
- **Dışa aktarma:** sistem paylaşım menüsü ("Dosyalara Kaydet" dahil). "Son yedek" yalnızca işlem tamamlanırsa güncellenir ("Kopyala" da tamamlanmış sayılır; uygulama dosyanın nereye gittiğini bilemez). Geçici dosya sonra silinir. **Dosya şifresizdir ve müşteri verisi içerir**; `.gitignore`'a eklendi.
- **Geri yükleme:** birleştirme yok, **tümünü değiştirir**. Önce dosyanın tamamı doğrulanır (başka dosya / bozuk / yeni sürüm reddedilir), sonra özetli onay sorulur. Silme + ekleme tek `save`; hata olursa geri alınır. İşlem sırasında ekranlar kaldırılıp yeniden kurulur (silinmiş kayda bakan görünüm çökmesin). Bekleyen taslak silinir; hatırlatmalar ve widget'lar yeniden hesaplanır.
- **Uyarı:** Bugün ekranında, son yedek 7 günden eskiyse; hiç yedek yoksa yalnızca en az bir müşteri varken. Dokununca Ayarlar.
- iCloud yedeği yok; FreeDevice kurulumunda tek koruma budur (uygulama silinirse veri gider).

## Durum günlüğü – toparlama turu

- Test ve FreeDevice derlemesi ilk denemede yeşil: 470 test (33'ü yeni); FreeDevice kimlik ve yetki doğrulamaları geçti. (`gh run view --log` çıktısı testlerin bir kısmını göstermedi; toplam, artifact'teki `xcodebuild.log`'dan doğrulandı.)
- Ekran görüntüsü iş akışı ilk denemede yeşil (86 görüntü). Görüntü bir hata gösterdi: "Sil" yıkıcı rolde olunca iOS yarım kalan not sorusuna "Vazgeç" ekliyordu. Rol kaldırıldı; ikinci koşuda yalnızca "Devam et" / "Sil".
- Süre: test işi ~13 dk, FreeDevice ~3 dk (paralel). Ekran görüntüsü akışı toplam ~27 dk (derleme ~12 dk + paralel parçalar ~15 dk); artık her push'u bekletmiyor.
- Gerçek cihazda denenmeli: taslağın uygulama kapatılınca geri gelmesi, "Dosyalara Kaydet" ve geri yükleme, ücretsiz hesapla imzalama (App Group dahil), widget'lar.
- CI artifact'leri artık yalnızca `D:\saha-satis-artifacts` altına indirilir ve iş bitince silinir; daha önce C: sürücüsüne indirilenler (12 klasör, ~243 MB) silindi.
