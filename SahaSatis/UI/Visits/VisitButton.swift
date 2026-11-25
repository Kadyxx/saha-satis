import SwiftUI

/// Sağ altta "+ Ziyaret" hızlı butonu (action rengi) ve ziyaret formunu açan sheet.
/// Buton içeriğin üstünde yüzer; kaydırılabilir ekranların alt boşluğu (`contentMargins`) buton yüksekliği kadar
/// artırılır, böylece son satırlar, ok işaretleri ve rozetler butonun altında kalmaz.
struct VisitButtonModifier: ViewModifier {
    /// Butonun kapladığı yükseklik (≈46 pt) + alt boşluk + nefes payı.
    static let reservedHeight: CGFloat = 76

    /// Müşteri detayından açılırsa o müşteri seçili gelir.
    let customer: Customer?
    let onSaved: () -> Void

    @EnvironmentObject private var context: AppContext
    @State private var isPresenting = false

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, Self.reservedHeight, for: .scrollContent)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    isPresenting = true
                } label: {
                    Label("Ziyaret", systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(Theme.onAction)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Theme.action, in: Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                }
                .accessibilityLabel("Ziyaret ekle")
                .padding(.trailing, 16)
                .padding(.bottom, 12)
            }
            .sheet(isPresented: $isPresenting) {
                VisitFormView(context: context, customer: customer, visit: nil, onSaved: onSaved)
            }
    }
}

extension View {
    /// Ekranın sağ altına "+ Ziyaret" butonu ekler (Ayarlar ve form/sheet ekranlarında kullanılmaz).
    func visitButton(customer: Customer? = nil, onSaved: @escaping () -> Void = {}) -> some View {
        modifier(VisitButtonModifier(customer: customer, onSaved: onSaved))
    }
}
