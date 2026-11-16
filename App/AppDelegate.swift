import AppKit

/// Owns the model so it exists before launch completes, and receives `tapismarche://…` links
/// (Raycast, terminal, Shortcuts) through AppKit's standard URL routing.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(model.open)
    }
}
