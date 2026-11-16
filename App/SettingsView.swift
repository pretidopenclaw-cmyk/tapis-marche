import ServiceManagement
import SwiftUI
import WalkingPadKit

struct SettingsView: View {
    let model: AppModel

    @State private var token = ""
    @State private var parentPage = ""
    @State private var message: String?
    @State private var busy = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Notion") {
                if model.notionConfigured {
                    Text("Notion connecté : base « Marches » et page « Récaps hebdo ».")
                    Button("Déconnecter Notion") { model.disconnectNotion() }
                } else {
                    SecureField("Jeton d'intégration Notion", text: $token)
                    TextField("Page Notion parente (URL)", text: $parentPage)
                    Button("Connecter Notion", action: connect)
                        .disabled(busy || token.isEmpty || parentPage.isEmpty)
                }
                Text(model.notionLine).foregroundStyle(.secondary)
                if let message { Text(message) }
            }
            Section("Démarrage") {
                Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func connect() {
        busy = true
        Task {
            message = await model.connectNotion(token: token, parentPage: parentPage)
            if model.notionConfigured { token = "" }
            busy = false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Lancement à l'ouverture de session impossible : \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
