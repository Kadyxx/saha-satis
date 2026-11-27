# saha-satis

Saha satış mühendisleri için widget odaklı iOS asistanı. Tüm kararlar [docs/SPEC.md](docs/SPEC.md) içindedir.

- Proje dosyası XcodeGen ile `project.yml`'den üretilir; `.xcodeproj` repoda yoktur.
- Derleme GitHub Actions macOS runner'ında yapılır:
  - `build.yml`: her push'ta birim testleri ve FreeDevice cihaz derlemesi.
  - `screenshots.yml`: ekran görüntüleri; yalnızca `main`'e birleştirmede, PR'a `screenshots` etiketi eklenince veya elle.
- Bundle ID / App Group / iCloud kimlikleri `project.yml` başındaki `settings` altında tek yerde durur.
- Ücretsiz Apple ID ile kendi iPhone'una kurulum: [docs/MAC_KURULUM.md](docs/MAC_KURULUM.md).
- Bu repo public: API anahtarı, `.p8` dosyası ve müşteri verisi asla commit edilmez.
