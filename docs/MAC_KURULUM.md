# Mac'ten iPhone'a kurulum (ücretsiz Apple ID)

Ücretli Apple Developer hesabı olmadan, uygulamayı bir Mac kullanarak kendi iPhone'una kurma rehberi.
Kurulumda **FreeDevice** yapılandırması kullanılır: iCloud ve Apple ile Giriş kapalıdır, veriler yalnızca telefonda durur.

> ## ⚠️ En önemli üç kural
>
> 1. **Uygulamayı iPhone'dan SİLME.** Silersen tüm veriler gider ve geri gelmez. Yenilerken eskisinin **üstüne** kur.
> 2. Her yenilemeden önce uygulamada **Ayarlar → Yedekleme → Yedekle** yap ve dosyayı **Dosyalara Kaydet** ile sakla.
> 3. Kurulum **7 gün** geçerlidir. Süre dolunca uygulama açılmaz ama veriler telefonda durur; yeniden kurunca geri gelir.

## Gerekenler

- Bir Mac (kendi Mac'in, ödünç bir Mac veya kiralık Mac). macOS sürümü, aşağıdaki Xcode'u çalıştırabilmeli.
- iPhone ve veri aktarabilen bir USB kablosu.
- Apple ID (iki adımlı doğrulama açık).
- Yaklaşık 40 GB boş disk alanı ve internet.

## 1. Xcode'u kur

1. Mac'te **App Store**'u aç, **Xcode**'u ara ve yükle (büyük bir indirmedir).
   - Xcode, iPhone'undaki iOS sürümünü desteklemeli. iPhone'un iOS'u yeniyse Xcode'un da güncel olması gerekir.
2. Xcode'u bir kez aç. Lisansı kabul et. Hangi platformların indirileceği sorulursa **iOS**'u seç ve inmesini bekle.
3. **Terminal**'i aç (⌘ + Boşluk, "Terminal" yaz) ve çalıştır:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app
   xcodebuild -version
   ```

   İlk komut Mac parolanı ister (yazarken ekranda görünmez). İkincisi Xcode sürümünü yazmalı.

## 2. Homebrew ve XcodeGen'i kur

1. Homebrew yüklü mü diye bak: `brew --version`. Sürüm yazıyorsa 3. adıma geç.
2. Yüklü değilse [brew.sh](https://brew.sh) sayfasındaki kurulum komutunu çalıştır:

   ```sh
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

   Kurulum bitince ekranda **"Next steps"** başlığı altında bir-iki komut yazar. **Onları da çalıştır**, yoksa
   `brew` komutu bulunamaz.
3. XcodeGen'i kur:

   ```sh
   brew install xcodegen
   ```

## 3. Projeyi indir

```sh
cd ~/Documents
git clone https://github.com/Kadyxx/saha-satis.git
cd saha-satis
```

`git` için "komut satırı araçlarını yükle" penceresi çıkarsa onayla ve komutu tekrar çalıştır.

## 4. Xcode projesini üret ve FreeDevice şemasını seç

```sh
xcodegen generate
open SahaSatis.xcodeproj
```

`xcodegen generate` tüm yapılandırmaları üretir. FreeDevice'ı seçmek için Xcode'un üst ortasındaki şema adına
tıkla ve **SahaSatis-FreeDevice** şemasını seç.

> **`SahaSatis` şemasını kullanma.** O şema ücretli hesap isteyen yetkiler (iCloud, Apple ile Giriş) içerir ve ücretsiz
> hesapla imzalanamaz.

## 5. Apple ID'ni ekle ve Personal Team'i seç

1. Xcode menüsü: **Xcode → Settings… → Accounts**. Sol alttaki **+** → **Apple ID** → giriş yap.
2. Xcode'da sol sütunun en üstündeki mavi **SahaSatis** proje simgesine tıkla.
3. **TARGETS** altında **SahaSatis**'i seç → **Signing & Capabilities** sekmesi:
   - **Automatically manage signing** işaretli olsun.
   - **Team**: adının yanında **(Personal Team)** yazan takımı seç.
4. **SahaSatisWidget** hedefi için aynısını yap.
5. Test hedefine (SahaSatisTests) dokunmana gerek yok.

FreeDevice kimlikleri (`project.yml` içinde hazırdır, elle yazma):

| | |
| --- | --- |
| Uygulama | `com.kadyxx.sahasatis` |
| Widget | `com.kadyxx.sahasatis.widget` |
| App Group | `group.com.kadyxx.sahasatis` |

### App Group imzalanamazsa

App Group, widget'ların uygulama verisini okuyabilmesi için gerekir. Xcode, App Groups satırında kırmızı hata
gösterip imzalayamazsa:

1. Önce **Try Again** / **Register** düğmesi varsa dene; internet bağlantını ve doğru takımı seçtiğini kontrol et.
2. Olmazsa **her iki hedefte** (SahaSatis ve SahaSatisWidget) App Groups bölümünün yanındaki çöp kutusuyla bu
   yetkiyi kaldır. Uygulama normal çalışır; **widget'lar boş görünür**.

Dikkat: App Group varken ve yokken veriler telefonda **farklı yerlerde** tutulur. Bu tercihi veri girmeden önce yap.
Sonradan değiştirmek zorunda kalırsan önce uygulamada **Yedekle**, yeni kurulumdan sonra **Yedekten geri yükle**.

## 6. iPhone'u hazırla

1. iPhone'u kabloyla Mac'e bağla ve kilidini aç. **"Bu bilgisayara güvenilsin mi?"** sorusuna **Güven** de.
2. Xcode'un üst ortasında, şema adının yanındaki cihaz listesinden **kendi iPhone'unu** seç (simülatör değil).
3. **Geliştirici Modu**'nu aç: iPhone'da **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu** → aç.
   iPhone yeniden başlar; açılınca **Aç**'ı onayla ve parolanı gir.
   - Menü görünmüyorsa iPhone Mac'e bağlıyken Xcode'da bir kez ▶︎'a bas, sonra tekrar bak.

## 7. Yükle

1. Xcode'da **▶︎ (Run)** düğmesine bas (⌘R). İlk derleme birkaç dakika sürer.
2. Anahtar zinciri parolası sorulursa Mac parolanı yaz ve **Always Allow** de.
3. İlk seferde iPhone **"Güvenilmeyen Geliştirici"** uyarısı verebilir:
   iPhone'da **Ayarlar → Genel → VPN ve Aygıt Yönetimi** → **Geliştirici Uygulaması** altında Apple ID'n →
   **Güven**. (İnternet bağlantısı gerekir.)
4. Uygulamayı aç (veya Xcode'dan tekrar ▶︎). Bildirim izni sorulunca **İzin Ver** de.
5. Kablo çıkarılınca uygulama çalışmaya devam eder.

## 8. İlk açılış kontrolü

- **Örnek veri GELMEMELİ.** Müşteri listesi boş olmalı; "Örnek Makina A.Ş." gibi hayali firmalar, hazır takip veya
  teklif görünmemeli. Görürsen **gerçek veri girme**: yanlış şema ya da başlatma ayarıyla kurulmuştur. Xcode'da
  **SahaSatis-FreeDevice** şemasının seçili olduğunu kontrol et.
- Hazır gelmesi normal olanlar **varsayılan ayarlardır**: sorumlu şehir listesi ve iki ürün ailesi (PLC-5, SLC 500).
- Widget eklemek için: ana ekranda boş bir yere basılı tut → **+** (veya **Düzenle → Widget Ekle**) → **Saha Satış**.
- Gerçek veri girmeye başlayınca ilk yedeğini al. Son yedek 7 günden eskiyse Bugün ekranında uyarı çıkar.

## 9. Her 7 günde bir yenileme

Ücretsiz Apple ID ile imza **7 gün** geçerlidir. Süre dolunca uygulama ve widget'lar açılmaz.
**Silme.** Şunları yap (süre dolmadan yapman daha rahattır):

1. Uygulama hâlâ açılıyorsa **Ayarlar → Yedekleme → Yedekle**.
2. iPhone'u Mac'e bağla. Terminal'de:

   ```sh
   cd ~/Documents/saha-satis
   git pull
   xcodegen generate
   open SahaSatis.xcodeproj
   ```

3. `xcodegen generate` projeyi yeniden ürettiği için **Team seçimi sıfırlanır**: 5. adımdaki gibi iki hedefte de
   Personal Team'i tekrar seç.
4. **SahaSatis-FreeDevice** şemasını ve iPhone'unu seç, **▶︎**'a bas. Uygulama eskisinin üstüne kurulur ve veriler durur.

> ## ⚠️ Yeniden kurarken uygulamayı SİLME
>
> "Açılmıyor", "kullanılamıyor" veya Xcode'da kurulum hatası görsen bile iPhone'daki uygulamayı silme: silmek tüm
> verileri yok eder. Kurulum hata verirse hatayı çöz, tekrar ▶︎'a bas. Bundle ID'yi, App Group tercihini veya Apple
> ID'yi değiştirme: farklı kimlikle kurulan uygulama eski veriyi görmeyebilir. Mecbur kalırsan önce yedek al.

Ücretsiz hesabın diğer sınırları: telefonda aynı anda en fazla 3 uygulama bu yöntemle kurulu olabilir ve 7 gün içinde
sınırlı sayıda yeni uygulama kimliği oluşturulabilir. Kimlikleri değiştirmeden yenilemek sorun çıkarmaz.

## 10. İş bitince Apple ID'yi Xcode'dan kaldır

Özellikle **ödünç veya kiralık Mac** kullandıysan:

1. Xcode: **Xcode → Settings… → Accounts** → Apple ID'ni seç → sol alttaki **−** düğmesi → onayla.
2. **Anahtar Zinciri Erişimi** (Keychain Access) uygulamasını aç → **giriş** zinciri → **Sertifikalarım** →
   **Apple Development: …** adlı, e-postanı içeren sertifikayı özel anahtarıyla birlikte sil.
3. Mac senin değilse proje klasörünü ve derleme çıktılarını da sil:

   ```sh
   rm -rf ~/Documents/saha-satis ~/Library/Developer/Xcode/DerivedData/SahaSatis-*
   ```

4. Kiralık Mac'te Safari, App Store veya sistem ayarlarında Apple ID ile oturum açtıysan oralardan da çık.

Apple ID'yi Xcode'dan kaldırmak iPhone'daki uygulamayı silmez; kalan süre boyunca çalışmaya devam eder. Sonraki
yenilemede Apple ID'yi yeniden eklersin.

## Sık karşılaşılan sorunlar

| Belirti | Çözüm |
| --- | --- |
| `brew: command not found` | 2. adımdaki "Next steps" komutlarını çalıştır, Terminal'i kapatıp aç. |
| "Personal development teams … do not support iCloud / Sign in with Apple" | Yanlış şema ya da yapılandırma: **SahaSatis-FreeDevice** seç. Signing ekranının üstünde **FreeDevice** filtresine bak. |
| "Signing for … requires a development team" | 5. adım: iki hedefte de Team seç. |
| "Developer Mode disabled" | 6. adımdaki Geliştirici Modu. |
| "Untrusted Developer" / "Güvenilmeyen Geliştirici" | 7. adımın 3. maddesi. |
| Cihaz listede yok veya "not supported" | Kilidi aç, kabloyu değiştir; Xcode'u güncelle. |
| Widget boş, uygulamada veri var | App Group imzalanmamış olabilir (5. adım). İmzalıysa uygulamayı bir kez açıp widget'ı kaldırıp yeniden ekle. |

> Mac'te yapılan değişiklikleri (Team seçimi, kaldırılan yetki) repoya commit etme. `Config/` altında değişiklik
> kaldıysa ve geri almak istersen: `git checkout -- Config`
