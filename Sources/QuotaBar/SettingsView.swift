import SwiftUI
#if os(macOS)
import AppKit
import ServiceManagement
#endif

struct SettingsView: View {
    @Bindable var model: UsageModel
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?
    #endif
    var body: some View {
        NavigationStack {
            Form {
                Section("Appareils") {
                    Toggle("Synchroniser avec iCloud", isOn: $model.syncEnabled)
                        .disabled(!model.cloudSyncAvailable)
                    if !model.cloudSyncAvailable {
                        Text("Cette compilation locale permet l’enregistrement du widget macOS. La synchronisation iCloud nécessite une compilation signée avec ton équipe Apple.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Seuls les quotas et leur date de lecture sont synchronisés. Le Mac doit rester ouvert avec QuotaBar actif pour publier de nouvelles valeurs. La réception iCloud peut être différée.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                #if os(macOS)
                Section("Codex sur ce Mac") {
                    TextField("Chemin de l’exécutable", text: $model.executablePath)
                        .font(.system(.caption, design: .monospaced))
                        .autocorrectionDisabled()
                    Button("Choisir l’exécutable…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url { model.executablePath = url.path }
                    }
                    Button("Se connecter / changer de compte") { Task { await model.login() } }
                        .disabled(model.isLoggingIn || model.isRefreshing)
                    Text("Utilise la session de Codex. Changer de compte change aussi celui du CLI local. Aucun mot de passe n’est conservé par QuotaBar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Barre de menus") {
                    Toggle("Ouvrir à la connexion", isOn: $loginEnabled)
                        .onChange(of: loginEnabled) { _, enabled in
                            do {
                                if enabled { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch {
                                settingsError = error.localizedDescription
                                loginEnabled = SMAppService.mainApp.status == .enabled
                            }
                        }
                    Text("Actualisation toutes les 30 secondes, même lorsque le panneau est fermé. Chaque fenêtre du groupe sélectionné apparaît directement dans la barre : 5 h 72 % · 7 j 84 %. Un avertissement signale un échec de lecture ; après 15 minutes sans lecture, les valeurs deviennent des tirets.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let settingsError { Text(settingsError).foregroundStyle(.orange) }
                #endif
                Section("Widget") {
                    Text("Ajoute le widget QuotaBar depuis la galerie de widgets. Il affiche le quota Codex et la dernière lecture du Mac. macOS et iOS décident du rythme de rafraîchissement des widgets.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Link("Voir l’usage dans ChatGPT", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Réglages")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminé") { dismiss() } } }
        }
        #if os(macOS)
        .frame(width: 510, height: 580)
        #endif
    }
}
