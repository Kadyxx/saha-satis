import SwiftUI

private enum WeekFormat {
    static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = AppFormat.locale
        formatter.setLocalizedDateFormatFromTemplate(format)
        return formatter
    }
    static let shortWeekday = formatter("EEE")
    static let dayNumber = formatter("d")
    static let longDay = formatter("dMMMMEEEE")
}

/// Bugün ekranının en üstündeki "Bu hafta" şeridi: Pzt–Cum, her günün şehirleri. Güne dokununca plan sayfası açılır.
struct WeekStripSection: View {
    @ObservedObject var settings: AppSettings
    let now: Date
    let onSelect: (Date) -> Void

    private var calendar: Calendar { .current }
    private var week: [Date] { WeekPlan.displayedWeek(at: now, calendar: calendar) }
    private var plan: WeekPlan { WeekPlan(cities: settings.cityPlan) }
    private var isNextWeek: Bool { calendar.isDate(week[0], inSameDayAs: now) == false && week[0] > now }

    var body: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(week, id: \.self) { day in
                    Button { onSelect(day) } label: { chip(for: day) }
                        .buttonStyle(.plain)
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .listRowBackground(Color.clear)
        } header: {
            HStack {
                Text(isNextWeek ? "Gelecek hafta" : "Bu hafta")
                Spacer()
                Button("Geçen haftayı kopyala") { copyPreviousWeek() }
                    .font(.footnote.weight(.semibold))
                    .textCase(nil)
                    .disabled(!plan.hasPreviousWeek(for: week, calendar: calendar))
            }
        }
    }

    private func chip(for day: Date) -> some View {
        let cities = plan.cities(on: day, calendar: calendar)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        return VStack(spacing: 3) {
            Text(WeekFormat.shortWeekday.string(from: day))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isToday ? Theme.brandText : Theme.textSecondary)
            Text(WeekFormat.dayNumber.string(from: day))
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 0) {
                if cities.isEmpty {
                    Text("—").foregroundStyle(Theme.textSecondary)
                } else {
                    Text(cities[0]).foregroundStyle(Theme.textPrimary)
                    Text(cities.count > 1 ? "+\(cities.count - 1)" : " ").foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .padding(.vertical, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isToday ? Theme.brandText : Color.clear, lineWidth: 1.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(WeekFormat.longDay.string(from: day)): \(cities.isEmpty ? "şehir atanmadı" : cities.joined(separator: ", "))")
    }

    private func copyPreviousWeek() {
        var updated = plan
        updated.copyPreviousWeek(into: week, calendar: calendar)
        updated.prune(before: now, calendar: calendar)
        settings.cityPlan = updated.cities
    }
}

/// Bir günün planı: şehir seçimi (birden fazla veya hiç) + o şehirlerdeki önerilen ziyaretler ("Plana ekle").
struct DayPlanView: View {
    let day: Date
    let repositories: Repositories
    @ObservedObject var settings: AppSettings

    @Environment(\.dismiss) private var dismiss
    @State private var refreshTick = 0
    @State private var errorMessage: String?

    private var calendar: Calendar { .current }
    private var cities: [String] { WeekPlan(cities: settings.cityPlan).cities(on: day, calendar: calendar) }

    var body: some View {
        let _ = refreshTick
        NavigationStack {
            Form {
                citySection
                suggestionSection
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(WeekFormat.longDay.string(from: day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
            .alert("Hata", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .tint(Theme.brandText)
    }

    // MARK: - Şehirler

    private var citySection: some View {
        Section {
            ForEach(settings.responsibleCities, id: \.self) { city in
                Button { toggle(city) } label: {
                    HStack {
                        Text(city).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if cities.contains(city) {
                            Image(systemName: "checkmark").foregroundStyle(Theme.brandText).fontWeight(.semibold)
                        }
                    }
                }
                .accessibilityAddTraits(cities.contains(city) ? .isSelected : [])
            }
        } header: {
            Text("Şehirler")
        } footer: {
            Text("Birden fazla şehir seçebilir veya günü boş bırakabilirsiniz. Sabah özeti bu şehirleri içerir.")
        }
        .listRowBackground(Theme.surface)
    }

    private func toggle(_ city: String) {
        var plan = WeekPlan(cities: settings.cityPlan)
        var list = plan.cities(on: day, calendar: calendar)
        if let index = list.firstIndex(of: city) { list.remove(at: index) } else { list.append(city) }
        plan.set(list, on: day, calendar: calendar)
        plan.prune(before: Date(), calendar: calendar)
        settings.cityPlan = plan.cities
    }

    // MARK: - Öneriler

    private var suggestions: [VisitSuggestion] {
        guard !cities.isEmpty else { return [] }
        let customers = (try? repositories.customers.fetchAll()) ?? []
        let planned = (try? WeekPlanTask.plannedCustomerIDs(on: day, repositories: repositories, calendar: calendar)) ?? []
        return VisitSuggester.suggestions(
            cities: cities,
            customers: customers,
            regionCities: settings.responsibleCities,
            context: RegionContext(rules: settings.visitFrequencyRules, now: Date()),
            expiryWarningDays: settings.quoteExpiryWarningDays,
            plannedCustomerIDs: planned
        )
    }

    @ViewBuilder
    private var suggestionSection: some View {
        let list = suggestions
        Section {
            if cities.isEmpty {
                Text("Öneri görmek için bu güne bir şehir seçin.").foregroundStyle(Theme.textSecondary)
            } else if list.isEmpty {
                Text("Bu şehirlerde önerilecek ziyaret yok.").foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(list) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        } header: {
            Text("Önerilen ziyaretler")
        } footer: {
            if !list.isEmpty {
                Text("Sıra: gecikmiş takip, geçerliliği yaklaşan teklif, ziyaret sıklığı, açık fırsat, hiç ziyaret edilmemiş aday.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private func suggestionRow(_ suggestion: VisitSuggestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(suggestion.customer.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    RatingBadge(rating: suggestion.customer.rating)
                }
                if !suggestion.customer.locationText.isEmpty {
                    Text(suggestion.customer.locationText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(Array(suggestion.reasons.prefix(2).enumerated()), id: \.offset) { index, reason in
                    Label(reason.text, systemImage: reason.symbol)
                        .font(.caption)
                        .foregroundStyle(index == 0 && reason.priority == 0 ? Theme.overdue : Theme.textSecondary)
                }
            }
            Spacer(minLength: 4)
            if suggestion.isPlanned {
                Label("Planlandı", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.done)
                    .fixedSize()
            } else {
                Button("Plana ekle") { add(suggestion.customer) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private func add(_ customer: Customer) {
        do {
            try WeekPlanTask.add(
                customer: customer, day: day, reminderTime: settings.defaultReminderTime,
                repositories: repositories, calendar: calendar
            )
            refreshTick += 1
        } catch {
            errorMessage = "Plana eklenemedi: \(error.localizedDescription)"
        }
    }
}
