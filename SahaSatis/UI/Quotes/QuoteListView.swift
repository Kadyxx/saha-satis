import SwiftUI

/// Pipeline ekranındaki "Teklifler" içeriği: durum filtresi (Taslak, Gönderildi, Takipte, Kazanıldı, Kaybedildi) ve
/// liste. Geçerliliği yaklaşan/dolan bekleyen teklifler üstte ve vurgulu ayrı bölümde.
struct QuoteListView: View {
    @Bindable var model: QuoteListModel
    let warningDays: Int

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            if model.totalCount == 0 {
                empty(title: "Henüz teklif yok", message: "Sağ üstteki + ile ilk teklifinizi hazırlayın.")
            } else if model.sections.isEmpty {
                empty(title: "Bu durumda teklif yok", message: "Başka bir durum seçin.")
            } else {
                list
            }
        }
        .onChange(of: model.filter) { model.reload(warningDays: warningDays) }
    }

    // MARK: - Filtre

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "Tümü", status: nil)
                ForEach(QuoteStatus.allCases, id: \.self) { status in
                    chip(title: status.title, status: status)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func chip(title: String, status: QuoteStatus?) -> some View {
        let selected = model.filter == status
        return Button {
            model.filter = status
        } label: {
            Text("\(title) (\(model.count(for: status)))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? Theme.onBrand : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? Theme.brand : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Liste

    private var list: some View {
        List {
            if !model.sections.approaching.isEmpty {
                Section {
                    ForEach(model.sections.approaching) { quote in
                        NavigationLink(value: quote) {
                            QuoteRow(quote: quote, expiry: model.expiryState(for: quote))
                        }
                        .listRowBackground(Theme.action.opacity(0.16))
                    }
                } header: {
                    Label("Geçerliliği yaklaşan", systemImage: "clock.badge.exclamationmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .textCase(nil)
                }
            }
            if !model.sections.others.isEmpty {
                Section {
                    ForEach(model.sections.others) { quote in
                        NavigationLink(value: quote) {
                            QuoteRow(quote: quote, expiry: model.expiryState(for: quote))
                        }
                        .listRowBackground(Theme.surface)
                    }
                } header: {
                    if !model.sections.approaching.isEmpty {
                        Text("Diğer teklifler")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func empty(title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "doc.text")
                .foregroundStyle(Theme.textPrimary)
        } description: {
            Text(message)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
