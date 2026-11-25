import SwiftUI

/// Sorumlu şehirler: ekle, sil, sırala.
struct CitiesSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var newCity = ""

    private var trimmedNewCity: String {
        newCity.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        List {
            Section {
                ForEach(settings.responsibleCities, id: \.self) { city in
                    Text(city)
                        .foregroundStyle(Theme.textPrimary)
                }
                .onDelete { offsets in
                    settings.responsibleCities.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    settings.responsibleCities.move(fromOffsets: source, toOffset: destination)
                }
            } header: {
                Text("Sorumlu şehirler")
            } footer: {
                Text("Sıralamak veya silmek için sağ üstteki Düzenle'ye dokunun.")
            }
            .listRowBackground(Theme.surface)

            Section("Şehir ekle") {
                HStack {
                    TextField("Şehir adı", text: $newCity)
                        .onSubmit(addCity)
                    Button("Ekle", action: addCity)
                        .disabled(trimmedNewCity.isEmpty)
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Varsayılan bölgeye dön", role: .destructive) {
                    settings.responsibleCities = AppSettings.defaultCities
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .visitButton()
        .navigationTitle("Şehirler")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }

    private func addCity() {
        let city = trimmedNewCity
        guard !city.isEmpty else { return }
        let exists = settings.responsibleCities.contains {
            $0.compare(city, options: [.caseInsensitive], range: nil, locale: AppFormat.locale) == .orderedSame
        }
        if !exists {
            settings.responsibleCities.append(city)
        }
        newCity = ""
    }
}
