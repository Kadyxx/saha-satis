import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "briefcase.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Saha Satış")
                    .font(.largeTitle.bold())
                Text("Faz 0 – altyapı hazır")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Bugün")
        }
    }
}

#Preview {
    ContentView()
}
