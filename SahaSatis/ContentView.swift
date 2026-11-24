import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Theme.brand)
                Text("Saha Satış")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Faz 0 – altyapı hazır")
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Bugün")
        }
    }
}

#Preview {
    ContentView()
}
