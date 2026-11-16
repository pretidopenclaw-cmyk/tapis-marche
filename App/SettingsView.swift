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
                    SecureField("Nouveau jeton d'intégration", text: $token)
                    Button("Remplacer le jeton") {
                        message = model.replaceToken(token)
                        token = ""
                    }
                    .disabled(token.isEmpty)
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
            Section("Tapis") {
                Toggle("Vitesse au démarrage", isOn: autoPilot(\.preferredSpeedEnabled))
                Stepper(value: autoPilot(\.preferredSpeedKmh), in: 1.0...6.0, step: 0.1) {
                    Text(FrenchFormat.speed(model.autoPilotSettings.preferredSpeedKmh))
                }
                .disabled(!model.autoPilotSettings.preferredSpeedEnabled)
                Toggle("Arrêter quand je descends", isOn: autoPilot(\.autoStopEnabled))
            }
            Section("Démarrage") {
                Toggle("Lancer à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    private func autoPilot<Value>(_ keyPath: WritableKeyPath<AutoPilotSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.autoPilotSettings[keyPath: keyPath] },
            set: { value in
                var settings = model.autoPilotSettings
                settings[keyPath: keyPath] = value
                model.updateAutoPilot(settings)
            })
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
