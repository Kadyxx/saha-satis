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
    /// Yalnızca ekran görüntüsü senaryoları: kurulu baza kaydırır / ilk migrasyon ürününün formunu açar.
    var scrollToInstalledBase = false
    var openMigrationProductForm = false

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
    @State private var cardSession: CardScanSession?
    @State private var confirmingDelete = false
    @State private var productTarget: ProductEditTarget?
    @State private var migrationTarget: MigrationTarget?
    @State private var productToDelete: InstalledProduct?
    @State private var didRunDebugScene = false
    @State private var installedBaseTick = 0
    @State private var errorMessage: String?

    var body: some View {
        let _ = installedBaseTick
        ScrollViewReader { proxy in
            List {
                // Yalnızca ekran görüntüsü senaryosu: kurulu baz bölümü en üstte (liste tembel yüklendiğinden kaydırma güvenilmez).
                if scrollToInstalledBase { installedBaseSection }
                headerSection
                contactsSection
                notesSection
                visitsSection
                opportunitiesSection
                quotesSection
                if !scrollToInstalledBase { installedBaseSection }
            }
            .task {
                if openMigrationProductForm, !didRunDebugScene {
                    didRunDebugScene = true
                    try? await Task.sleep(for: .milliseconds(600))
                    if let product = (customer.installedBase ?? []).first(where: { $0.productFamily == "PLC-5" }) {
                        productTarget = ProductEditTarget(product: product)
                    }
                    return
                }
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
        .sheet(item: $productTarget, onDismiss: { reloadInstalledBase() }) { target in
            InstalledProductFormView(
                customer: customer,
                product: target.product,
                families: settings.productFamilies,
                repository: repositories.installedProducts,
                onSaved: reloadInstalledBase
            )
        }
        .sheet(item: $migrationTarget, onDismiss: reloadOpportunities) { target in
            OpportunityFormView(
                context: appContext, opportunity: nil, customer: customer,
                prefill: MigrationOpportunityPrefill(product: target.product), onSaved: reloadOpportunities
            )
        }
        .confirmationDialog(
            "Bu ürün kurulu bazdan silinsin mi?",
            isPresented: Binding(get: { productToDelete != nil }, set: { if !$0 { productToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Ürünü sil", role: .destructive) {
                if let product = productToDelete { delete(product) }
                productToDelete = nil
            }
            Button("Vazgeç", role: .cancel) { productToDelete = nil }
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
        .sheet(item: $cardSession, onDismiss: reloadContacts) { session in
            BusinessCardFlowView(
                repositories: repositories, settings: settings, session: session, fixedCustomer: customer
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
            Button {
                cardSession = CardScanSession()
            } label: {
                Label("Kartvizit tara", systemImage: "person.text.rectangle")
            }
        }
        .listRowBackground(Theme.surface)
    }

    private let historyAnchor = "visit-history-anchor"
    private let installedBaseAnchor = "installed-base-anchor"

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

    /// Kurulu baz: ürün ekle/düzenle/sil; ömrünü tamamlayan ürünlerde "Fırsat aç" (migrasyon).
    private var installedBaseSection: some View {
        Section {
            let products = (customer.installedBase ?? [])
                .sorted { $0.catalogNumber.localizedCaseInsensitiveCompare($1.catalogNumber) == .orderedAscending }
            if products.isEmpty {
                Text("Kurulu baz kaydı yok.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(products) { product in
                    installedProductRow(product)
                        .id(product.id == products.first?.id ? installedBaseAnchor : product.id.uuidString)
                }
            }
            Button { productTarget = ProductEditTarget(product: nil) } label: {
                Label("Ürün ekle", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderless)
        } header: {
            Text("Kurulu baz")
        }
        .listRowBackground(Theme.surface)
    }

    private func installedProductRow(_ product: InstalledProduct) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { productTarget = ProductEditTarget(product: product) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.catalogNumber)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("× \(product.quantity)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    if !product.productFamily.isEmpty {
                        Text(product.productFamily)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(product.lifecycleStatus.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(product.lifecycleStatus.isMigrationCandidate ? Theme.overdue : Theme.textSecondary)
                    if !product.notes.isEmpty {
                        Text(product.notes)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button("Fırsat aç") { migrationTarget = MigrationTarget(product: product) }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .fixedSize()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { productToDelete = product } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    // MARK: - İşlemler

    /// Kurulu baz değişince ilişkili listeyi ve "Migrasyon fırsatı" etiketini yeniler.
    private func reloadInstalledBase() {
        installedBaseTick += 1
    }

    private func delete(_ product: InstalledProduct) {
        do {
            try repositories.installedProducts.delete(product)
            reloadInstalledBase()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

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

private struct ProductEditTarget: Identifiable {
    let id = UUID()
    let product: InstalledProduct?
}

private struct MigrationTarget: Identifiable {
    let id = UUID()
    let product: InstalledProduct
}
