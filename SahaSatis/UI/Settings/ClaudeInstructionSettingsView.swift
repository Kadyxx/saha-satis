import SwiftUI

/// "Claude talimatı": nota eklenip Claude'a gönderilen talimat metni.
struct ClaudeInstructionSettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var confirmingReset = false

    var body: some View {
        Form {
            Section {
                TextEditor(text: $settings.claudeInstruction)
                    .frame(minHeight: 360)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Claude talimatı")
            } footer: {
                Text("Bugünün tarihi, müşteri adı, görüşülen kişiler ve ham not bu metnin altına eklenir. Cevabın forma yazılabilmesi için Konu / Özet / Sonraki adım / Takip tarihi şablonunu koruyun. Boş bırakılırsa varsayılan metin gönderilir.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Varsayılana dön", role: .destructive) { confirmingReset = true }
                    .disabled(settings.claudeInstruction == AppSettings.defaultClaudeInstruction)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Claude talimatı")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Talimat varsayılan metne dönsün mü?", isPresented: $confirmingReset, titleVisibility: .visible
        ) {
            Button("Varsayılana dön", role: .destructive) {
                settings.claudeInstruction = AppSettings.defaultClaudeInstruction
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }
}
