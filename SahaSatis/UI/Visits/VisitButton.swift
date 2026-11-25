import SwiftUI

/// Sağ altta "+ Ziyaret" hızlı butonu (action rengi) ve ziyaret formunu açan sheet.
/// `safeAreaInset` kullanıldığı için buton listelerin son satırlarını kapatmaz; kaydırırken içeriğin üstünde durur.
struct VisitButtonModifier: ViewModifier {
    /// Müşteri detayından açılırsa o müşteri seçili gelir.
    let customer: Customer?
    let onSaved: () -> Void

    @EnvironmentObject private var context: AppContext
    @State private var isPresenting = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .sheet(isPresented: $isPresenting) {
                VisitFormView(context: context, customer: customer, visit: nil, onSaved: onSaved)
            }
    }
}

extension View {
    /// Ekranın sağ altına "+ Ziyaret" butonu ekler.
    func visitButton(customer: Customer? = nil, onSaved: @escaping () -> Void = {}) -> some View {
        modifier(VisitButtonModifier(customer: customer, onSaved: onSaved))
    }
}
