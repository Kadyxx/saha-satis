import SwiftUI

/// Bugün ekranı (SPEC → Bugün): gecikmiş (kırmızı), bugün ve yarın takipleri; bugünkü ziyaretler ve
/// "CRM'e aktarılmadı" sayısı. Satırda sola kaydırma: Tamamlandı / Ertele. Sağ üstte manuel takip ekleme.
struct TodayView: View {
    let repositories: Repositories
    @ObservedObject var reminders: ReminderScheduler
    let debugScene: DebugScene?

    @EnvironmentObject private var appContext: AppContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var model: TodayModel
    @State private var newTask: ManualTaskSeed?
    @State private var postponeTarget: FollowUpTask?
    @State private var customDateTarget: FollowUpTask?
    @State private var didRunDebugScene = false

    init(repositories: Repositories, reminders: ReminderScheduler, debugScene: DebugScene? = nil) {
        self.repositories = repositories
        _reminders = ObservedObject(wrappedValue: reminders)
        self.debugScene = debugScene
        _model = State(initialValue: TodayModel(repositories: repositories))
    }

    var body: some View {
        NavigationStack {
            list
                .background(Theme.background)
                .visitButton(onSaved: { model.reload() })
                .navigationTitle("Bugün")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { newTask = ManualTaskSeed() } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Takip ekle")
                    }
                }
                .sheet(item: $newTask, onDismiss: { model.reload() }) { seed in
                    ManualTaskFormView(context: appContext, seed: seed, onSaved: { model.reload() })
                }
                .sheet(item: $customDateTarget) { task in
                    PostponeDateSheet(task: task) { date in
                        model.postpone(task, .date(date))
                    }
                }
                .confirmationDialog(
                    "Ertele",
                    isPresented: postponeDialogBinding,
                    titleVisibility: .visible,
                    presenting: postponeTarget
                ) { task in
                    ForEach(PostponeOption.presets, id: \.self) { option in
                        Button(option.title) { model.postpone(task, option) }
                    }
                    Button("Tarih seç…") { customDateTarget = task }
                    Button("Vazgeç", role: .cancel) {}
                } message: { task in
                    Text(task.title)
                }
                .alert("Hata", isPresented: errorBinding) {
                    Button("Tamam", role: .cancel) {}
                } message: {
                    Text(model.errorMessage ?? "")
                }
        }
        .onAppear { model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: .appDataDidChange)) { _ in model.reload() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { model.reload() }
        }
        .task { await runDebugSceneIfNeeded() }
    }

    // MARK: - Liste

    private var list: some View {
        List {
            if reminders.authorization == .denied {
                notificationsOffSection
            }
            visitsSection
            if model.sections.isEmpty {
                Section {
                    Text("Bugün için takip yok")
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.surface)
                }
            }
            taskSection("Gecikmiş", tasks: model.sections.overdue, isOverdue: true)
            taskSection("Bugün", tasks: model.sections.today, isOverdue: false)
            taskSection("Yarın", tasks: model.sections.tomorrow, isOverdue: false)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func taskSection(_ title: String, tasks: [FollowUpTask], isOverdue: Bool) -> some View {
        if !tasks.isEmpty {
            Section {
                ForEach(tasks) { task in
                    Button {
                        if let customer = task.customer { appContext.open(customer: customer) }
                    } label: {
                        TaskRow(task: task, isOverdue: isOverdue)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { model.complete(task) } label: {
                            Label("Tamamlandı", systemImage: "checkmark")
                        }
                        .tint(Theme.done)
                        Button { postponeTarget = task } label: {
                            Label("Ertele", systemImage: "clock.arrow.circlepath")
                        }
                        .tint(Theme.action)
                    }
                    .listRowBackground(Theme.surface)
                }
            } header: {
                Text("\(title) (\(tasks.count))")
                    .foregroundStyle(isOverdue ? Theme.overdue : Theme.textSecondary)
            }
        }
    }

    private var visitsSection: some View {
        Section {
            if model.visitsToday.isEmpty {
                Text("Bugün henüz ziyaret kaydı yok")
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ForEach(model.visitsToday) { visit in
                    HStack(spacing: 12) {
                        Image(systemName: visit.exportedToCRM ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(visit.exportedToCRM ? Theme.done : Theme.textSecondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visit.customer?.name ?? "Müşteri yok")
                                .foregroundStyle(Theme.textPrimary)
                            Text(visit.type.title)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 8)
                        Text(AppFormat.time(visit.date))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Label(
                    model.unexportedCount == 0
                        ? "Tüm ziyaretler CRM'e aktarıldı"
                        : "\(model.unexportedCount) ziyaret CRM'e aktarılmadı",
                    systemImage: "tray.and.arrow.up"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brandText)
            }
        } header: {
            Text("Bugünkü ziyaretler")
        }
        .listRowBackground(Theme.surface)
    }

    /// Bildirim izni reddedildiyse hatırlatmalar çalışmaz; kullanıcıya söyle.
    private var notificationsOffSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Bildirimler kapalı", systemImage: "bell.slash")
                    .font(.headline)
                    .foregroundStyle(Theme.overdue)
                Text("Hatırlatmaları alabilmek için bildirimlere izin verin.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Button("Ayarlar'ı aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Bağlamalar

    private var postponeDialogBinding: Binding<Bool> {
        Binding(get: { postponeTarget != nil }, set: { if !$0 { postponeTarget = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    }

    // MARK: - Ekran görüntüsü senaryoları (yalnızca DEBUG başlatma argümanıyla)

    private func runDebugSceneIfNeeded() async {
        guard debugScene == .todayForm, !didRunDebugScene else { return }
        didRunDebugScene = true
        let customer = try? repositories.customers.fetchAll().first { $0.name == "Örnek Makina A.Ş." }
        newTask = ManualTaskSeed(title: "Bakım sözleşmesi örneğini Ahmet Bey'e gönder", customer: customer)
    }
}
