import SwiftUI

enum SettingsRoute: Hashable {
    case cities
    case productFamilies
}

/// Ayarlar sekmesi: profil, bölge, hatırlatmalar, dışa aktarma ve hakkında.
/// Değerler `AppSettings` üzerinden App Group UserDefaults'a anında yazılır.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let debugScene: DebugScene?

    @State private var path: [SettingsRoute]
    @State private var followUpText: String

    private let remindersAnchor = "reminders-anchor"

    init(settings: AppSettings, debugScene: DebugScene? = nil) {
        _settings = ObservedObject(wrappedValue: settings)
        self.debugScene = debugScene
        _path = State(initialValue: debugScene == .settingsCities ? [.cities] : [])
        _followUpText = State(initialValue: DayListFormat.format(settings.quoteFollowUpDays))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                Form {
                    profileSection
                    regionSection
                    installedBaseSection
                    remindersSection
                    visitFrequencySection
                    opportunitySection
                    quoteSection
                    exportSection
                    importSection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .task {
                    // Yalnızca ekran görüntüsü senaryosu: hatırlatmalar bölümüne kaydır.
                    guard debugScene == .settingsReminders else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo(remindersAnchor, anchor: .top)
                }
            }
            .navigationTitle("Ayarlar")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .cities:
                    CitiesSettingsView(settings: settings)
                case .productFamilies:
                    ProductFamiliesSettingsView(settings: settings)
                }
            }
        }
        .tint(Theme.brandText)
    }

    // MARK: - Bölümler

    private var profileSection: some View {
        Section {
            FormTextField(title: "Ad soyad", text: $settings.fullName)
            FormTextField(title: "Unvan", text: $settings.jobTitle)
        } header: {
            Text("Profil")
        } footer: {
            Text("Şimdilik yalnızca bu cihazda saklanır; giriş eklendiğinde hesabınızla birleşecek.")
        }
        .listRowBackground(Theme.surface)
    }

    private var regionSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.cities) {
                LabeledContent("Sorumlu şehirler", value: "\(settings.responsibleCities.count) şehir")
            }
        } header: {
            Text("Bölge")
        } footer: {
            Text("Müşteri formundaki şehir seçimi bu listeden gelir.")
        }
        .listRowBackground(Theme.surface)
    }

    private var installedBaseSection: some View {
        Section {
            NavigationLink(value: SettingsRoute.productFamilies) {
                LabeledContent("Ürün aileleri", value: "\(settings.productFamilies.count) aile")
            }
        } header: {
            Text("Kurulu baz")
        } footer: {
            Text("Aile adı ve varsayılan yaşam döngüsü. Örnek aileleri (PLC-5, SLC 500) Rockwell yaşam döngüsü sayfasından doğrulayın.")
        }
        .listRowBackground(Theme.surface)
    }

    private var remindersSection: some View {
        Section {
            DatePicker("Hatırlatma saati", selection: timeBinding(\.defaultReminderTime), displayedComponents: .hourAndMinute)
                .id(remindersAnchor)
            Toggle("Sabah özeti", isOn: $settings.morningSummaryEnabled)
            if settings.morningSummaryEnabled {
                DatePicker("Sabah özeti saati", selection: timeBinding(\.morningSummaryTime), displayedComponents: .hourAndMinute)
            }
            Toggle("Gün sonu hatırlatması", isOn: $settings.endOfDayReminderEnabled)
            if settings.endOfDayReminderEnabled {
                DatePicker("Gün sonu saati", selection: timeBinding(\.endOfDayReminderTime), displayedComponents: .hourAndMinute)
            }
            Toggle("Hafta sonu bildirimleri", isOn: $settings.weekendNotificationsEnabled)
        } header: {
            Text("Hatırlatmalar")
        } footer: {
            Text("Hafta sonu bildirimleri kapalıysa Cumartesi/Pazar'a düşen görevler Pazartesi'ye kayar.")
        }
        .listRowBackground(Theme.surface)
    }

    private var visitFrequencySection: some View {
        Section {
            Stepper("Önemli: \(settings.visitFrequencyImportantDays) gün", value: $settings.visitFrequencyImportantDays, in: 5...365, step: 5)
            Stepper("Potansiyelli: \(settings.visitFrequencyPromisingDays) gün", value: $settings.visitFrequencyPromisingDays, in: 5...365, step: 5)
            Stepper("Zayıf: \(settings.visitFrequencyWeakDays) gün", value: $settings.visitFrequencyWeakDays, in: 5...365, step: 5)
        } header: {
            Text("Ziyaret sıklığı")
        } footer: {
            Text("Son ziyaretten bu kadar gün geçen müşteriler için ziyaret hatırlatması oluşur.")
        }
        .listRowBackground(Theme.surface)
    }

    private var opportunitySection: some View {
        Section {
            Picker("Varsayılan para birimi", selection: $settings.defaultCurrency) {
                ForEach(Currency.allCases, id: \.self) { currency in
                    Text(currency.displayName).tag(currency)
                }
            }
            Toggle("Kapanış hatırlatması", isOn: $settings.opportunityCloseReminderEnabled)
            if settings.opportunityCloseReminderEnabled {
                Stepper("Kapanıştan \(settings.opportunityCloseReminderDays) gün önce", value: $settings.opportunityCloseReminderDays, in: 1...60)
            }
        } header: {
            Text("Fırsatlar")
        } footer: {
            Text("Beklenen kapanış tarihi olan açık fırsatlar için hatırlatma oluşur. Yeni fırsatlar varsayılan para birimiyle açılır.")
        }
        .listRowBackground(Theme.surface)
    }

    private var quoteSection: some View {
        Section {
            LabeledContent("Takip günleri") {
                TextField("3, 7", text: $followUpText)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityLabel("Teklif takip günleri")
            }
            .onChange(of: followUpText) { _, newValue in
                let parsed = DayListFormat.parse(newValue)
                if !parsed.isEmpty {
                    settings.quoteFollowUpDays = parsed
                }
            }
            Toggle("Geçerlilik uyarısı", isOn: $settings.quoteExpiryWarningEnabled)
            if settings.quoteExpiryWarningEnabled {
                Stepper("Bitişten \(settings.quoteExpiryWarningDays) gün önce", value: $settings.quoteExpiryWarningDays, in: 1...60)
            }
        } header: {
            Text("Teklifler")
        } footer: {
            Text("Takip günleri: teklif gönderildikten kaç gün sonra hatırlatılsın (virgülle ayırın). Her teklif için ayrıca değiştirilebilir.")
        }
        .listRowBackground(Theme.surface)
    }

    private var exportSection: some View {
        Section {
            FormTextField(title: "CRM e-posta alıcısı", text: $settings.crmEmail, keyboard: .emailAddress, autocapitalization: .never)
        } header: {
            Text("Dışa aktarma")
        } footer: {
            Text("Gün sonu ziyaret raporu bu adrese gönderilir.")
        }
        .listRowBackground(Theme.surface)
    }

    private var importSection: some View {
        Section {
            if let url = try? CustomerCSVTemplate.writeFile() {
                ShareLink(item: url) {
                    Label("Örnek CSV şablonunu paylaş", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("İçe aktarma")
        } footer: {
            Text("Müşteriler sekmesindeki içe aktarma düğmesiyle CSV yükleyin. Şablon Excel'de açılır (ayraç ;, UTF-8).")
        }
        .listRowBackground(Theme.surface)
    }

    private var aboutSection: some View {
        Section("Hakkında") {
            LabeledContent("Sürüm", value: AppInfo.versionText)
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Yardımcılar

    /// `TimeOfDay` ayarını `DatePicker`'ın beklediği `Date` bağlamasına çevirir.
    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { settings[keyPath: keyPath].date() },
            set: { settings[keyPath: keyPath] = TimeOfDay(date: $0) }
        )
    }
}
