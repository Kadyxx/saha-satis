import SwiftUI

private struct ContactEditTarget: Identifiable {
    let id = UUID()
    let contact: Contact?
}

private struct VisitEditTarget: Identifiable {
    let id = UUID()
    let visit: Visit
}

/// Müşteri detayı: üst kart (değerlendirme rozeti + not), Kişiler, Notlar, Ziyaret geçmişi, Fırsatlar ve Kurulu baz.
struct CustomerDetailView: View {
    let customer: Customer
    let repositories: Repositories
    let settings: AppSettings
    /// Silme onayından sonra çağrılır; silme işlemini liste ekranı güvenle yapar.
    let onDelete: (Customer) -> Void
    /// Yalnızca ekran görüntüsü senaryosu: açılışta ziyaret geçmişine kaydırır.
    var scrollToHistory = false

    @EnvironmentObject private var appContext: AppContext
    @Environment(\.openURL) private var openURL
    @State private var contacts: [Contact] = []
    @State private var visits: [Visit] = []
    @State private var opportunities: [Opportunity] = []
    @State private var showingNewOpportunity = false
    @State private var quotes: [Quote] = []
    @State private var showingNewQuote = false
    @State private var visitTarget: VisitEditTarget?
    @State private var visitToDelete: Visit?
    @State private var showingEdit = false
    @State private var contactTarget: ContactEditTarget?
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                headerSection
                contactsSection
                notesSection
                visitsSection
                opportunitiesSection
                quotesSection
                installedBaseSection
            }
            .task {
                guard scrollToHistory else { return }
                try? await Task.sleep(for: .milliseconds(600))
                proxy.scrollTo(historyAnchor, anchor: .top)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .visitButton(customer: customer, onSaved: reloadVisits)
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { showingEdit = true } label: { Label("Düzenle", systemImage: "pencil") }
                    Button(role: .destructive) { confirmingDelete = true } label: { Label("Müşteriyi sil", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            reloadContacts()
            reloadVisits()
            reloadOpportunities()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appDataDidChange)) { _ in reloadOpportunities() }
        .sheet(isPresented: $showingNewQuote, onDismiss: reloadOpportunities) {
            QuoteFormView(context: appContext, quote: nil, customer: customer, onSaved: reloadOpportunities)
        }
        .sheet(isPresented: $showingNewOpportunity, onDismiss: reloadOpportunities) {
            OpportunityFormView(context: appContext, opportunity: nil, customer: customer, onSaved: reloadOpportunities)
        }
        .sheet(isPresented: $showingEdit) {
            CustomerFormView(
                customer: customer,
                repository: repositories.customers,
                cities: settings.responsibleCities
            )
        }
        .sheet(item: $contactTarget) { target in
            ContactFormView(
                contact: target.contact,
                customer: customer,
                repository: repositories.contacts,
                onSaved: reloadContacts
            )
        }
        .sheet(item: $visitTarget) { target in
            VisitFormView(context: appContext, customer: customer, visit: target.visit, onSaved: reloadVisits)
        }
        .confirmationDialog(
            "Bu ziyaret silinsin mi?",
            isPresented: visitDeleteBinding,
            titleVisibility: .visible
        ) {
            Button("Ziyareti sil", role: .destructive) {
                if let visit = visitToDelete { delete(visit) }
                visitToDelete = nil
            }
            Button("Vazgeç", role: .cancel) { visitToDelete = nil }
        }
        .confirmationDialog(
            "Bu müşteri ve tüm kişileri, ziyaretleri, fırsatları ve teklifleri silinsin mi?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Müşteriyi sil", role: .destructive) { onDelete(customer) }
            Button("Vazgeç", role: .cancel) {}
        }
        .alert("İşlem başarısız", isPresented: errorBinding) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Bölümler

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(customer.name)
                        .font(.title3.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 8)
                    RatingBadge(rating: customer.rating)
                }
                if !customer.locationText.isEmpty {
                    Text(customer.locationText)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 6) {
                    Text(customer.status.title)
                    if !customer.sector.isEmpty {
                        Text("·")
                        Text(customer.sector)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                if customer.hasMigrationOpportunity {
                    TagLabel(text: "Migrasyon fırsatı")
                }
                if !customer.ratingNote.isEmpty {
                    Text(customer.ratingNote)
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Theme.surface)
    }

    private var contactsSection: some View {
        Section("Kişiler") {
            ForEach(contacts) { contact in
                ContactRow(contact: contact) { url in openURL(url) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(contact) } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button { contactTarget = ContactEditTarget(contact: contact) } label: {
                            Label("Düzenle", systemImage: "pencil")
                        }
                        .tint(Theme.brandText)
                    }
            }
            Button {
                contactTarget = ContactEditTarget(contact: nil)
            } label: {
                Label("Kişi ekle", systemImage: "plus")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private let historyAnchor = "visit-history-anchor"

    /// Ziyaret geçmişi: en yeni üstte; satıra dokunmak ziyareti açıp düzenlemeyi sağlar.
    private var visitsSection: some View {
        Section("Ziyaret geçmişi") {
            if visits.isEmpty {
                Text("Henüz ziyaret yok. Sağ alttaki + Ziyaret ile ilk kaydı ekleyin.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .id(historyAnchor)
            } else {
                ForEach(Array(visits.enumerated()), id: \.element.id) { index, visit in
                    Button { visitTarget = VisitEditTarget(visit: visit) } label: {
                        VisitHistoryRow(visit: visit)
                    }
                    .id(index == 0 ? historyAnchor : visit.id.uuidString)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { visitToDelete = visit } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var notesSection: some View {
        Section("Notlar") {
            if customer.notes.isEmpty {
                Text("Not yok")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(customer.notes)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// Müşterinin fırsatları (aşamaya göre, açıklar önce); satıra dokununca fırsat detayı açılır.
    private var opportunitiesSection: some View {
        Section("Fırsatlar") {
            if opportunities.isEmpty {
                Text("Bu müşteri için fırsat yok.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(opportunities) { opportunity in
                    NavigationLink(value: opportunity) {
                        OpportunityRow(opportunity: opportunity, showCustomer: false, showStage: true)
                    }
                }
            }
            Button { showingNewOpportunity = true } label: {
                Label("Fırsat ekle", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .listRowBackground(Theme.surface)
    }

    /// Müşterinin teklifleri (geçerliliği yaklaşanlar önce); satıra dokununca teklif detayı açılır.
    private var quotesSection: some View {
        Section("Teklifler") {
            if quotes.isEmpty {
                Text("Bu müşteri için teklif yok.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(quotes) { quote in
                    NavigationLink(value: quote) {
                        QuoteRow(quote: quote, expiry: expiry(of: quote), showCustomer: false)
                    }
                }
            }
            Button { showingNewQuote = true } label: {
                Label("Teklif ekle", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        }
        .listRowBackground(Theme.surface)
    }

    private func expiry(of quote: Quote) -> QuoteExpiryState {
        QuoteListing.expiryState(
            for: quote, warningDays: settings.quoteExpiryWarningDays, now: Date(), calendar: .current
        )
    }

    private func emptySection(title: String, message: String) -> some View {
        Section(title) {
            Text(message)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(Theme.surface)
    }

    private var installedBaseSection: some View {
        Section("Kurulu baz") {
            let products = (customer.installedBase ?? [])
                .sorted { $0.catalogNumber < $1.catalogNumber }
            if products.isEmpty {
                Text("Kurulu baz kaydı yok.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(products) { product in
                    HStack {
                        Text(product.catalogNumber)
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(product.lifecycleStatus.title)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - İşlemler

    private func reloadOpportunities() {
        let all = (try? repositories.opportunities.opportunities(for: customer)) ?? []
        opportunities = PipelineGrouping.groups(from: all).flatMap(\.opportunities)
        let allQuotes = (try? repositories.quotes.quotes(for: customer)) ?? []
        let sections = QuoteListing.make(
            quotes: allQuotes, filter: nil, warningDays: settings.quoteExpiryWarningDays, now: Date(), calendar: .current
        )
        quotes = sections.approaching + sections.others
    }

    private func reloadContacts() {
        do {
            contacts = try repositories.contacts.contacts(for: customer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadVisits() {
        do {
            visits = try repositories.visits.visits(for: customer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ visit: Visit) {
        do {
            let service = VisitService(
                repositories: repositories,
                reminderMinutes: settings.defaultReminderTime.minutesSinceMidnight
            )
            try service.delete(visit)
            reloadVisits()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var visitDeleteBinding: Binding<Bool> {
        Binding(get: { visitToDelete != nil }, set: { if !$0 { visitToDelete = nil } })
    }

    private func delete(_ contact: Contact) {
        do {
            try repositories.contacts.delete(contact)
            reloadContacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

/// Kişi satırı: ad/unvan, telefon ve e-posta metni, tek dokunuşla ara / e-posta / WhatsApp.
private struct ContactRow: View {
    let contact: Contact
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(contact.fullName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if contact.isPrimary {
                    TagLabel(text: "Asıl kişi")
                }
            }
            if !contact.title.isEmpty {
                Text(contact.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !contact.phone.isEmpty {
                Text(contact.phone)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !contact.email.isEmpty {
                Text(contact.email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 20) {
                if let url = ContactLink.dialURL(contact.phone) {
                    Button { open(url) } label: { Label("Ara", systemImage: "phone.fill") }
                }
                if let url = ContactLink.mailURL(contact.email) {
                    Button { open(url) } label: { Label("E-posta", systemImage: "envelope.fill") }
                }
                if let url = ContactLink.whatsAppURL(contact.phone) {
                    Button { open(url) } label: { Label("WhatsApp", systemImage: "message.fill") }
                }
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .buttonStyle(.borderless)
            .tint(Theme.brandText)
        }
        .padding(.vertical, 2)
    }
}
