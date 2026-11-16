import Foundation

/// After a relaunch (crash, update, reboot), rebuilds the tracker from stored samples so no walk is lost.
public enum SessionRecovery {
    /// Replays samples recorded after the last saved session, saves any session that closes
    /// (including one closed by `tick(now:)`), and returns the tracker holding a still-open session.
    /// Idempotent: a second call replays nothing new.
    public static func recover(store: SessionStore, now: Date,
                               tracker: SessionTracker = .init()) throws -> SessionTracker {
        var tracker = tracker
        for sample in try store.samples(after: store.lastClosedSessionEnd()) {
            if let closed = tracker.ingest(sample) { try store.save(closed) }
        }
        if let closed = tracker.tick(now: now) { try store.save(closed) }
        return tracker
    }
}
