import AppKit

/// Receives `tapismarche://…` links (Raycast, terminal, Shortcuts) as Apple Events.
/// Installed from the App initializer, before launch finishes, so a link that launches the app is not lost.
final class URLEventHandler: NSObject {
    private let onURL: (URL) -> Void

    init(onURL: @escaping (URL) -> Void) {
        self.onURL = onURL
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handle(_:with:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(_ event: NSAppleEventDescriptor, with reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text) else { return }
        onURL(url)
    }
}
