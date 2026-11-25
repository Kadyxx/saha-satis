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

## Durum günlüğü (devam)

- Düzeltmeler + Ayarlar ekranı: CI ilk denemede yeşil (60 test), görüntüler elle incelendi.
- Ziyaret kaydı: CI ilk denemede yeşil (87 test; 24 ekran görüntüsü, `screen-visit*`). Ekranlar elle incelendi.
  **Elle denenmesi gerekenler (gerçek iPhone):** mikrofon/konuşma tanıma izin akışı, Türkçe canlı metin, duraklat/devam,
  1 dakikayı aşan kayıt (otomatik parçalama), izin reddedilince klavyeyle yazma.
- Bu noktada duruldu; sıradaki iş için yeni talimat bekleniyor.
