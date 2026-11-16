import AppKit
import SwiftUI
import WalkingPadKit

struct MenuBarView: View {
    let model: AppModel

    var body: some View {
        Text(MenuText.today(model.dashboard))
        Text(MenuText.week(model.dashboard))
        Menu("Dernières séances") {
            if model.recentSessions.isEmpty {
                Text("Aucune séance")
            }
            ForEach(model.recentSessions) { session in
                Text(MenuText.session(session, calendar: model.calendar))
            }
        }
        Divider()
        Button("Libérer le tapis pour KS Fit (15 min)") { model.releasePad() }
        Divider()
        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }
}
