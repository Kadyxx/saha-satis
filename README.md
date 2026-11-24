# saha-satis

Saha satış mühendisleri için widget odaklı iOS asistanı. Tüm kararlar [docs/SPEC.md](docs/SPEC.md) içindedir.

- Proje dosyası XcodeGen ile `project.yml`'den üretilir; `.xcodeproj` repoda yoktur.
- Derleme yalnızca GitHub Actions macOS runner'ında yapılır (`.github/workflows/build.yml`).
- Bundle ID / App Group / iCloud kimlikleri `project.yml` başındaki `settings.base` altında tek yerde durur.
- Bu repo public: API anahtarı, `.p8` dosyası ve müşteri verisi asla commit edilmez.
