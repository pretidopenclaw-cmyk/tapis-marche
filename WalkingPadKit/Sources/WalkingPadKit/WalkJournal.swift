import Foundation

/// The recording loop: feeds frames to the tracker and persists only what crash recovery needs —
/// the frames of a walk in progress, never the hours of standby frames of an idle pad.
public struct WalkJournal {
    private let store: SessionStore
    private var tracker: SessionTracker

    /// Opens the journal and recovers any walk a crash or relaunch left open.
    public init(store: SessionStore, now: Date) throws {
        self.store = store
        tracker = try SessionRecovery.recover(store: store, now: now)
    }

    public var openSession: WalkSession? { tracker.openSession }

    /// Returns the session this frame closed, already saved.
    public mutating func ingest(_ sample: TreadmillSample) throws -> WalkSession? {
        let wasWalking = tracker.openSession != nil
        let closed = tracker.ingest(sample)
        if wasWalking || tracker.openSession != nil { try store.append(sample) }
        if let closed { try store.save(closed) }
        return closed
    }

    /// Closes a walk whose frames stopped (pad gone, Mac asleep); returns it, already saved.
    public mutating func tick(now: Date) throws -> WalkSession? {
        guard let closed = tracker.tick(now: now) else { return nil }
        try store.save(closed)
        return closed
    }
}
