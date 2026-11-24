import SwiftUI

/// "Merhaba" widget içeriği. Widget hedefi ve test hedefi tarafından ortak derlenir
/// (testler bu görünümü PNG'ye çevirip ekran görüntüsü artifact'i üretir).
struct HelloWidgetView: View {
    let date: Date

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.wave.fill")
                .font(.title)
                .foregroundStyle(.orange)
            Text("Merhaba")
                .font(.headline)
            Text("Bugün için takip yok")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
