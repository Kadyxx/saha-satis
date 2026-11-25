# Saha Satış Uygulaması – Teknik Şartname

Nov 24, 2026 · @Abdulkadir

## Amaç ve kapsam

Uygulama, tek bir saha satış mühendisinin takip edeceği işleri sürekli hatırlatan, widget odaklı kişisel bir iOS satış asistanıdır. CRM'in yerine geçmez; ziyaret notları gün sonunda e-posta ile CRM'e kopyalanmak üzere dışa aktarılır.

**Kullanıcı:** AB Market Otomasyon satış mühendisleri (Allen Bradley distribütörü). İlk sürüm tek kullanıcıyla başlar; ileride başka bölgelerdeki satış arkadaşları da kendi hesaplarıyla kullanacak, bu yüzden kullanıcı girişi ilk sürümde vardır.

**Sorumlu bölge (ilk kullanıcı; her kullanıcı kendi şehir listesini ayarlar):** Çanakkale, Balıkesir, Bursa, Bilecik, Yalova, Eskişehir, Kütahya, Afyonkarahisar.

**Temel ilkeler**

- Hatırlatma ve widget her şeyin merkezinde: kullanıcı uygulamayı açmadan ne yapacağını görmeli.
- Önce çevrimdışı: fabrikada çekim olmasa da her şey çalışmalı, veri telefonda tutulmalı.
- Hızlı giriş: ziyaret kaydı sesle, 30 saniyede bitmeli.
- CRM entegrasyonu yok: sadece ziyaret notları kopyalanabilir metin olarak e-postayla gönderilir.
- Arayüz dili Türkçe; para birimleri TL, USD, EUR.

## Mac olmadan geliştirme yolu

Kod Windows'ta Claude Code (Sonnet) ile yazılır, GitHub Actions'ın macOS makinelerinde derlenir ve TestFlight üzerinden iPhone'a kurulur. Xcode hiç açılmaz; proje dosyası XcodeGen ile `project.yml`'den üretilir.

**Bir kerelik kurulum (kullanıcı yapar)**

1. Apple Developer Program'a bireysel kayıt (yıllık 99 USD). Onay birkaç gün sürebilir.
2. developer.apple.com → Identifiers: Bundle ID (ör. `com.<ad>.sahasatis`), widget için ikinci Bundle ID (`com.<ad>.sahasatis.widget`), App Group (`group.com.<ad>.sahasatis`), iCloud container (`iCloud.com.<ad>.sahasatis`).
3. App Store Connect: uygulama kaydını oluştur; Users and Access → Integrations → App Store Connect API anahtarı üret (App Manager rolü), `.p8` dosyasını indir, Key ID ve Issuer ID'yi not et.
4. GitHub'da repo aç; Settings → Secrets altına `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`, `TEAM_ID` ekle.
5. Windows'a Git, VS Code ve Claude Code kur; repoyu klonla.
6. iPhone'a TestFlight uygulamasını kur.

**Her geliştirme döngüsü**

1. Sonnet kodu yazar, `git push` yapılır.
2. GitHub Actions (macos runner): `brew install xcodegen` → `xcodegen generate` → testler → `xcodebuild archive` (API anahtarı ile otomatik imzalama, `-allowProvisioningUpdates`) → TestFlight'a yükleme (fastlane `upload_to_testflight` veya `xcrun altool`).
3. Build TestFlight'ta işlenince (genelde 10–30 dk) iPhone'da güncellenir. Dahili test için Apple incelemesi gerekmez.

**Kısıtlar ve çözümler**

- Simülatör ve canlı önizleme yok; her deneme bir build demek. Bu yüzden Sonnet'ten her adımda derlenebilir, küçük değişiklikler istenir.
- Private repoda ücretsiz GitHub planı ayda yaklaşık 190–200 macOS dakikası karşılar (10–15 dakikalık build ile ayda yaklaşık 13–20 derleme); sonrası dakikası 0,062 USD. Public repoda standart runner'lar ücretsiz ve sınırsızdır. Public repoda koda asla müşteri verisi veya anahtar konmaz; anahtarlar yalnızca GitHub Secrets'ta durur. Alternatif: Codemagic'in ücretsiz katmanı.
- Bir hata derleme loglarıyla çözülemezse saatlik/aylık kiralık bulut Mac (ör. MacinCloud) ile Xcode'da hata ayıklama yapılır.

## Teknik mimari

SwiftUI + SwiftData ile, iOS 17 minimum, tek uygulama hedefi ve bir widget uzantısı. Veri, App Group içindeki ortak SwiftData deposunda tutulur ve iCloud (CloudKit) ile yedeklenir.

| Katman | Seçim | Not |
| --- | --- | --- |
| Arayüz | SwiftUI, NavigationStack, TabView | Sekmeler: Bugün, Müşteriler, Fırsat/Teklif, Harita, Ayarlar |
| Veri | SwiftData + CloudKit senkron | Depo App Group konteynerinde; widget aynı depoyu okur |
| Hatırlatma | UserNotifications (yerel bildirim) | Sunucu yok |
| Widget | WidgetKit + App Intents | İnteraktif widget için iOS 17 |
| Ses → metin | Speech framework, `tr-TR` | Uzun kayıtlar parçalanarak işlenir |
| Kartvizit | VisionKit / Vision metin tanıma | Faz 4 |
| Yapay zekâ | Foundation Models (cihaz üstü) veya isteğe bağlı bulut LLM | iOS 26+, Apple Intelligence destekli cihaz; Faz 4 |
| Harita | MapKit + CLGeocoder | Adres → koordinat |
| E-posta | MFMailComposeViewController | Yoksa paylaşım menüsü |
| Proje | XcodeGen `project.yml` | `.xcodeproj` repoya girmez |

**Sonnet'in bilmesi gereken kısıtlar**

- SwiftData + CloudKit: tüm özellikler opsiyonel veya varsayılan değerli olmalı, `@Attribute(.unique)` kullanılamaz, ilişkiler opsiyonel olmalı.
- iOS aynı anda en fazla 64 bekleyen yerel bildirime izin verir; hatırlatma motoru her zaman en yakın 64'ü planlar ve uygulama açılışında / arka plan yenilemede yeniden hesaplar.
- Widget zaman çizelgesi sınırlı yenilenir; veri değişince `WidgetCenter.shared.reloadAllTimelines()` çağrılır.
- Yapay zekâ özellikleri `SystemLanguageModel.default.availability` kontrolüyle açılır; desteklenmeyen cihazda uygulama yapay zekâsız tam çalışır.
- Kişisel veri cihaz ve kullanıcının iCloud'u dışına çıkmaz; harici sunucu veya analitik yok. Tek istisna, kullanıcının açarsa kullandığı bulut yapay zekâ seçeneğidir.

**Kullanıcı girişi ve çok kullanıcılı yapı**

- Giriş: Sign in with Apple (şifre tutulmaz, Apple'ın zorunlu tuttuğu yerel yöntem). İlk açılışta kurulum: ad soyad, unvan, sorumlu şehirler, CRM e-posta adresi.
- Faz 1–3: her kullanıcının verisi kendi iCloud özel veritabanında (CloudKit private database). Sunucu ve ek maliyet yok; kullanıcılar birbirinin verisini görmez.
- Ekip paylaşımı (ortak müşteri havuzu, yönetici görünümü, bölgeler arası devir) istenirse Faz 5'te bir sunucu (ör. Supabase veya Firebase) eklenir. Buna hazırlık için tüm veri erişimi baştan `Repository` protokolleri arkasında yazılır; görünümler SwiftData'ya doğrudan bağlanmaz.
- Her kaydın bir `ownerUserID` alanı olur (Apple kullanıcı kimliği); bugün filtrelemeye gerek yok, sunucuya geçişte veri taşımayı kolaylaştırır.
- Arkadaşlara dağıtım: TestFlight (build'ler 90 gün geçerli, yenisi yüklenmeli) veya kalıcı çözüm olarak App Store'da listelenmeyen (unlisted) uygulama. Firma adına yayınlanacaksa geliştirici hesabının bireysel değil kurumsal (organization) açılması daha uygun olur; bu karar hesap açmadan önce verilmeli.

## Veri modeli

Sekiz SwiftData modeli var; merkezde `Customer` durur, diğerleri ona bağlanır. Kod tanımlayıcıları İngilizce, arayüz metinleri Türkçedir. Her modelde `id: UUID`, `createdAt`, `updatedAt` bulunur.

| Model | Alanlar | İlişkiler |
| --- | --- | --- |
| `Customer` (Müşteri) | name, city (kullanıcının bölge listesinden; sabit kodlanmaz), district, industrialZone (OSB), sector, address, latitude, longitude, status (`current` / `potential` / `passive` → Mevcut / Aday / Pasif), rating (`important` / `promising` / `weak` → Önemli / Potansiyelli / Zayıf), ratingNote (kısa değerlendirme metni), notes, lastVisitDate (hesaplanan) | contacts, visits, opportunities, quotes, installedBase, tasks |
| `Contact` (Kişi) | fullName, title, phone, email, notes, isPrimary | customer |
| `InstalledProduct` (Kurulu baz) | catalogNumber (ör. 1756-L71), productFamily, quantity, lifecycleStatus (`active` / `activeMature` / `endOfLife` / `discontinued`), notes | customer |
| `Visit` (Ziyaret) | date, type (`visit` / `phone` / `online`), transcript (ham ses metni), summary (düzenlenmiş not), topics, nextStep, nextStepDate, exportedToCRM (Bool), exportedAt | customer, contacts, opportunity? |
| `Opportunity` (Fırsat) | title, description, estimatedValue, currency, stage (`lead` / `qualified` / `quoted` / `negotiation` / `won` / `lost`), expectedCloseDate, lostReason | customer, quotes, visits |
| `Quote` (Teklif) | quoteNumber, date, validUntil, currency, totalAmount (kalemlerden hesaplanır), status (`draft` / `sent` / `followUp` / `won` / `lost`), followUpDays (bu teklife özel; boşsa ayarlardaki varsayılan), notes | customer, opportunity?, items, tasks |
| `QuoteItem` (Teklif kalemi) | catalogNumber, description, quantity, unitPrice, discountPercent, lineTotal (hesaplanan) | quote |
| `FollowUpTask` (Takip / görev) | title, dueDate, isDone, doneAt, source (`manual` / `visitNextStep` / `quoteFollowUp` / `quoteExpiry` / `visitFrequency`), notificationID | customer?, quote?, visit? |

Ayarlar (`AppSettings`) UserDefaults'ta App Group altında tutulur; ayrıntı "Hatırlatma motoru" bölümünde.

## Modüller ve ekranlar

Beş sekme var: Bugün, Müşteriler, Fırsat/Teklif, Harita, Ayarlar. Her yerde sağ altta "+ Ziyaret" hızlı butonu durur.

**1. Bugün (ana ekran)**

- Gecikmiş takipler (kırmızı), bugünün takipleri, yarının takipleri
- Bugün yapılan ziyaretler ve "CRM'e aktarılmadı" sayısı
- Takip satırında sola kaydırma: Tamamlandı / Ertele (1 gün, 3 gün, 1 hafta, tarih seç)

**2. Müşteriler**

- Liste: arama; şehir, durum ve değerlendirme (Önemli / Potansiyelli / Zayıf) filtreleri; son ziyaret tarihine göre sıralama
- Müşteri detayı: üst kartta değerlendirme rozeti ve kısa değerlendirme notu; sekmeler Kişiler, Geçmiş (ziyaret + teklif + not zaman çizelgesi), Fırsatlar, Kurulu baz, Notlar
- Kişi satırından tek dokunuşla arama, e-posta, WhatsApp
- Kurulu bazda `endOfLife` veya `discontinued` ürün varsa müşteri kartında "Migrasyon fırsatı" etiketi
- CSV ile toplu müşteri içe aktarma (Dosyalar uygulamasından; kolonlar: firma, şehir, ilçe, OSB, sektör, adres, telefon)

**3. Ziyaret kaydı**

1. Müşteri seç (son ziyaret edilenler ve konuma en yakınlar üstte), kişileri işaretle.
2. Mikrofon butonu: konuşma canlı metne döner; duraklat/devam; metin düzenlenebilir.
3. "Sonraki adım" ve tarih alanı (tarih seçilirse otomatik takip oluşur).
4. İsteğe bağlı: fırsata bağla veya yeni fırsat aç.
5. Kaydet. (Faz 4: "Yapay zekâ ile düzenle" butonu.)

**4. Gün sonu dışa aktarma**

- Bugün ekranında "Ziyaretleri CRM için gönder": seçilen günün (varsayılan bugün) aktarılmamış ziyaretleri tek e-postada.
- Alıcı adresi ayarlardan; konu `Ziyaret Raporu – 24.11.2026`.
- Gönderim sonrası ziyaretler `exportedToCRM = true` olur; tekrar göndermek mümkündür.
- Her ziyaret ayrı blok, alanlar CRM'e tek tek yapıştırılacak sırada. Şablon ayarlardan değiştirilebilir; varsayılan:

```
=== ZIYARET 1 ===
Tarih: 24.11.2026
Firma: Örnek Makina A.Ş.
Şehir / İlçe: Bursa / Nilüfer
Görüşülen: Ahmet Yılmaz (Bakım Müdürü)
Ziyaret tipi: Yüz yüze
Konu: Hat 3 PLC yenileme
Görüşme notu:
...
Sonraki adım: Teklif hazırlanacak
Takip tarihi: 28.11.2026
```

**5. Fırsat / Teklif**

- Pipeline görünümü: aşamalara göre gruplu liste, aşama başına toplam tutar (para birimine göre ayrı)
- Teklif formu: no, tarih, geçerlilik, para birimi, kalemler (katalog no, açıklama, adet, birim fiyat, iskonto), toplam otomatik
- Teklif detayında "Takip ayarları": bu teklife özel takip günleri (varsayılan ayarlardan gelir)
- Durum değişince (kazanıldı/kaybedildi) bekleyen takipler iptal edilir; kaybedildi için sebep sorulur

**6. Harita ve bölge**

- MapKit haritası; pin rengi duruma, pin boyutu değerlendirmeye göre
- Üstte şehir seçici (kullanıcının bölgesindeki şehirler) ve filtreler: teklif bekleyen, uzun süredir ziyaret edilmeyen, aday
- Pin → müşteri kartı → Apple Haritalar'da yol tarifi
- Haftalık plan: günlere şehir ata (ör. Salı Bursa); o günün şehri için önerilen ziyaret listesi (gecikmiş takipler + ziyaret sıklığı aşılanlar + Potansiyelli müşteriler)

## Hatırlatma motoru ve ayarlar

Tüm hatırlatmalar `FollowUpTask` kayıtlarıdır; bildirimler bu kayıtlardan üretilir. Bütün süreler Ayarlar'dan değiştirilebilir, teklif takip günleri ayrıca teklif bazında ezilebilir.

| Kural | Tetikleyici | Varsayılan | Ayarlanabilir |
| --- | --- | --- | --- |
| Teklif takibi | Teklif durumu `sent` olunca | Gönderimden 3 ve 7 gün sonra | Gün listesi (ör. 2, 5, 10); teklif bazında da |
| Teklif geçerlilik uyarısı | `validUntil` yaklaşınca | Bitişten 3 gün önce | Gün sayısı, aç/kapa |
| Ziyaret sonraki adımı | Ziyarette `nextStepDate` dolunca | O tarih, sabah saati | — |
| Ziyaret sıklığı | Son ziyaretten bu yana geçen gün | Önemli 30, Potansiyelli 60, Zayıf 120 gün | Değerlendirme başına gün |
| Fırsat kapanış tarihi | `expectedCloseDate` yaklaşınca | 7 gün önce | Gün sayısı, aç/kapa |
| Sabah özeti | Her iş günü | 08:00 | Saat, günler |
| Gün sonu hatırlatması | Aktarılmamış ziyaret varsa | 18:00 | Saat, aç/kapa |

**Çalışma mantığı**

- Bildirim saati: tarihli görevler için Ayarlar'daki "hatırlatma saati" (varsayılan 09:00), görev bazında değiştirilebilir.
- `ReminderScheduler` her veri değişikliğinde, uygulama açılışında ve `BGAppRefreshTask` ile günde bir kez tüm bekleyen bildirimleri silip en yakın 64'ü yeniden planlar.
- Ziyaret sıklığı görevleri aynı müşteri için tek açık görev olarak tutulur; ziyaret girilince kapanır.
- Bildirim aksiyonları: "Tamamlandı", "Yarına ertele". Bildirime dokununca ilgili kayıt açılır.
- Hafta sonu bildirimi Ayarlar'dan kapatılabilir; kapalıysa Cumartesi/Pazar'a düşen görev Pazartesi'ye kayar.

**Diğer ayarlar:** CRM e-posta alıcısı, dışa aktarma şablonu, varsayılan para birimi, iCloud senkron aç/kapa, verileri JSON olarak yedekle / geri yükle.

## Widget'lar

Dört widget var: iki ana ekran, iki kilit ekranı. Hepsi aynı SwiftData deposunu App Group üzerinden okur; ana ekrandakiler App Intents ile uygulamayı açmadan iş tamamlatabilir.

| Widget | Boyut | Gösterir | Etkileşim |
| --- | --- | --- | --- |
| Bugünün takipleri | Ana ekran, orta (`systemMedium`) | Gecikmiş + bugünün ilk 3–4 görevi: müşteri, görev, saat | Her satırda onay kutusu (`CompleteTaskIntent`); dokununca görev açılır |
| Haftalık görünüm | Ana ekran, büyük (`systemLarge`) | Bugün + sonraki 6 günün görevleri, bekleyen teklif sayısı ve toplamı, aktarılmamış ziyaret sayısı | Onay kutusu; "+ Ziyaret" butonu uygulamayı kayıt ekranında açar |
| Sıradaki iş | Kilit ekranı, dikdörtgen (`accessoryRectangular`) | En yakın görev: "X Firması – teklif takibi", saat/tarih; gecikmişse uyarı simgesi | Dokununca görev açılır |
| Bekleyen iş sayısı | Kilit ekranı, yuvarlak (`accessoryCircular`) | Bugün + gecikmiş görev sayısı | Dokununca Bugün ekranı |

- Timeline: şu an + her görev saatinde bir giriş, en fazla 24 saatlik; gece yarısı yenilenir.
- Uygulamada görev, ziyaret veya teklif değişince `WidgetCenter.shared.reloadAllTimelines()`.
- Boş durum metni: "Bugün için takip yok".

## Renk paleti

Tüm renkler `Shared/Assets.xcassets` içinde açık/koyu mod varyantlı "Color Set" olarak tanımlıdır ve kodda yalnızca `Theme.swift` içindeki isimli sabitlerle kullanılır; kodda doğrudan hex yazılmaz. Widget'lar ve uygulama ikonu da bu paleti kullanır. `AccentColor` = `brand`.

| Rol | Açık mod | Koyu mod |
| --- | --- | --- |
| `background` | #EFE8DD | #22272F |
| `surface` (kart) | #F8F5EF | #303841 |
| `textPrimary` | #303841 | #EFE8DD |
| `textSecondary` | #5A6270 | #9AA3AE |
| `brand` (seçili, rozet) | #76ABAE | #76ABAE |
| `brandText` (turkuaz yazı) | #2F6265 | #76ABAE |
| `action` (+Ziyaret, bugün) | #FF5722 | #FF7A50 |
| `onAction` / `onBrand` | #303841 | #22272F |
| `overdue` (gecikmiş) | #B3261E | #FF6B6B |
| `done` (tamamlandı) | #76ABAE | #76ABAE |
| `swipeDone` (kaydırma: Tamamlandı zemini) | #2F6265 | #2F6265 |
| `swipePostpone` (kaydırma: Ertele zemini) | #A63A12 | #A63A12 |

**Değerlendirme rozetleri:** Önemli = `action`, Potansiyelli = `brand`, Zayıf = #9AA3AE (her iki modda; `ratingWeak`).

**Kurallar**

- #76ABAE (`brand`) ve #FF5722 (`action`) açık zeminde küçük yazı rengi olarak kullanılmaz (kontrast yetersiz). Turkuaz yazı için `brandText`; bu renklerin üstündeki yazı `onAction` / `onBrand` olur.
- `swipeDone` / `swipePostpone`: `swipeActions` düğmelerinde sistem yazı rengini değiştirtmez (hep beyaz); bu yüzden zeminleri iki modda da koyudur (beyaz yazıyla ≥ 6:1). Başka yerde kullanılmaz.
- `onAction` ve `onBrand` şimdilik aynı değerlere sahiptir ama ayrı Color Set'lerdir; gerekirse ayrışabilir.

## Yapay zekâ ve kartvizit

Yapay zekâ `NoteAssistant` protokolü arkasında yazılır ve iki uygulaması olur. Kullanıcının iPhone 14 Pro'su Apple Intelligence'ı desteklemediği için (iPhone 15 Pro ve sonrası gerekir) cihaz üstü model ona kapalıdır; ikinci seçenek ona yöneliktir. Hiçbiri yoksa yapay zekâ butonları gizlenir ve uygulama tam çalışır.

- **Cihaz üstü (Foundation Models):** uygun cihazı olan arkadaşlar için. Veri telefondan çıkmaz, ücretsiz, çevrimdışı çalışır.
- **Bulut (ör. Claude API):** kullanıcı kendi API anahtarını Ayarlar'a girer, anahtar Keychain'de saklanır. Varsayılan kapalıdır. Açıkken yalnızca düzenlenecek not metni ve müşteri adı gönderilir; internet gerekir. Kullanıcı bu seçeneği onayladı; ilk uygulama Claude API ile yapılır.

**Ziyaret notunu düzenleme**

- Girdi: ham ses metni + müşteri adı + kişi listesi + kurulu baz.
- Çıktı (`@Generable` yapı): `summary` (CRM'e uygun düzgün paragraf), `topics`, `mentionedProducts` (katalog no / ürün ailesi), `nextStep`, `nextStepDate`, `opportunityHint` (yeni fırsat önerisi).
- Kullanıcı öneriyi görür, düzenler, onaylar; otomatik kaydetme yok. Ham metin her zaman saklanır.

**Müşteri değerlendirme önerisi**

- Ziyaret geçmişi, açık fırsatlar ve teklif toplamından kısa değerlendirme metni ve Önemli / Potansiyelli / Zayıf önerisi üretir. Son karar kullanıcınındır.

**Kartvizit okuma**

1. Kamera veya fotoğraftan metin tanıma (VisionKit `DataScannerViewController` ya da Vision `VNRecognizeTextRequest`).
2. Metin alanlara ayrılır: ad soyad, unvan, firma, telefon, e-posta, adres. Yapay zekâ varsa Foundation Models ile, yoksa kural tabanlı (`NSDataDetector` ile telefon/e-posta/adres; kalan satırlar için basit kurallar).
3. Firma mevcutsa ona kişi eklenir, yoksa yeni müşteri oluşturma formu dolu açılır.

Türkçe karakterlerin (ğ, ş, ı, İ) metin tanımada doğru okunması gerçek kartvizitlerle test edilmeli.

## Fazlar ve kabul kriterleri

Altı faz sırayla gelir; her faz bittiğinde uygulama TestFlight'ta kullanılabilir durumdadır. Bir faz, altındaki maddelerin hepsi gerçek iPhone'da denenmeden kapanmaz.

**Faz 0 – Altyapı**

- [ ] `project.yml` ile uygulama + widget hedefi, App Group ve iCloud yetkileri tanımlı
- [ ] GitHub Actions her `main` push'unda derleyip TestFlight'a yüklüyor
- [ ] Boş uygulama ve "Merhaba" widget'ı iPhone'da görünüyor

**Faz 1 – Çekirdek**

- [ ] Sign in with Apple ile giriş ve ilk kurulum (ad, unvan, şehirler, CRM e-postası)
- [ ] Müşteri, kişi, not ekleme/düzenleme; değerlendirme (Önemli / Potansiyelli / Zayıf) ve kısa değerlendirme notu
- [ ] Sesli ziyaret kaydı Türkçe metne dönüşüyor; sonraki adım tarihi takip oluşturuyor
- [ ] Manuel takip ekleme; bildirim doğru saatte geliyor, Tamamlandı / Ertele çalışıyor
- [ ] Dört widget çalışıyor; ana ekran widget'ından görev tamamlanabiliyor
- [ ] Gün sonu e-postası şablona uygun geliyor, Windows'ta CRM'e yapıştırılabiliyor
- [ ] Veriler iCloud ile yedekleniyor; uygulama silinip kurulunca geri geliyor

**Faz 2 – Fırsat ve teklif**

- [ ] Fırsat pipeline'ı ve teklif formu (ürün kalemleri, para birimi, toplam)
- [ ] Teklif takip ve geçerlilik hatırlatmaları ayarlardaki ve teklife özel günlerle oluşuyor
- [ ] Kazanıldı / kaybedildi bekleyen takipleri iptal ediyor

**Faz 3 – Bölge**

- [ ] Harita, pin renkleri ve filtreler
- [ ] CSV ile toplu müşteri içe aktarma ve adresten koordinat
- [ ] Ziyaret sıklığı uyarıları değerlendirmeye göre çalışıyor
- [ ] Haftalık şehir planı ve günlük önerilen ziyaret listesi
- [ ] Kurulu baz ve "Migrasyon fırsatı" etiketi

**Faz 4 – Akıllı özellikler**

- [ ] Kartvizit okuma ile kişi/müşteri oluşturma
- [ ] Yapay zekâ ile ziyaret notu düzenleme ve değerlendirme önerisi

**Faz 5 – Ekip (isteğe bağlı)**

- [ ] Sunucu seçimi ve veri taşıma
- [ ] Ortak müşteri havuzu, yönetici görünümü, kullanıcılar arası müşteri devri

## Sonnet için başlangıç promptu

Bu dokümanı Markdown olarak dışa aktarıp repoya `docs/SPEC.md` olarak koy; Claude Code'a (Sonnet) ilk mesaj olarak aşağıdakini ver. Sonraki her faz için yalnızca faz numarasını değiştir.

```
Sen deneyimli bir iOS geliştiricisisin. docs/SPEC.md dosyasını baştan sona oku; tüm kararlar oradadır.

Önemli kısıt: Mac yok, Windows'tayım. Xcode açılamaz. Proje XcodeGen (project.yml) ile üretilir ve sadece GitHub Actions macOS runner'ında derlenir. Kodu yerelde derleyemezsin; bu yüzden:
- Her adımda küçük ve derlenebilir değişiklik yap.
- Swift 6 / iOS 17 API'lerini dikkatle kullan, emin olmadığın API'yi kullanma.
- SwiftData + CloudKit kısıtlarına uy (opsiyonel/varsayılan değerli özellikler, unique yok).
- Veri erişimini Repository protokolleri arkasında yaz.
- Arayüz metinleri Türkçe, kod tanımlayıcıları İngilizce.

Şimdi Faz 0'ı yap: project.yml (uygulama + widget hedefi, App Group, iCloud, Sign in with Apple yetkileri), boş SwiftUI uygulaması, "Merhaba" widget'ı ve .github/workflows/testflight.yml. Workflow App Store Connect API anahtarını ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8_BASE64, TEAM_ID secret'larından alsın. Bitirince benim App Store Connect'te ve GitHub'da elle yapmam gerekenleri adım adım listele.
```

## Kararlar

**Verilen kararlar (24.11.2026)**

- CRM: belirli bir CRM'e uyum gerekmez. Ziyaretler e-postayla gelir, kullanıcı CRM'e kendisi kopyalar. Varsayılan şablon yeterli.
- Cihaz: iPhone 14 Pro. Cihaz üstü yapay zekâ bu cihazda yok (bkz. Yapay zekâ bölümü).
- Geliştirici hesabı: bireysel.
- Veri: ilk süreçte herkes yalnız kendi verisini görür. Faz 5 şimdilik plan dışı.
- Firma onayı: alındı.

**Sonradan verilen kararlar**

- GitHub reposu: public. Derleme dakikaları ücretsiz; koda müşteri verisi, `.p8` dosyası veya API anahtarı asla girmez (`.gitignore` ile korunur), anahtarlar yalnızca GitHub Secrets'ta durur.
- Bulut yapay zekâ: onaylandı. Faz 4'te Claude API ile yapılır; kullanıcı kendi API anahtarını Ayarlar'a girer.

## Kaynaklar

- [Apple – Foundation Models ve Apple Intelligence duyurusu](https://www.apple.com/newsroom/2025/06/apple-intelligence-gets-even-more-powerful-with-new-capabilities-across-apple-devices/)
- [ShiftDelete – Apple Intelligence Türkçe desteği ve uyumlu cihazlar](https://en.shiftdelete.net/apple-intelligence-has-gained-turkish-language-support/)
- [Apple Developer Forums – Foundation Models'ın sistem dili koşulu](https://developer.apple.com/forums/thread/805378)
