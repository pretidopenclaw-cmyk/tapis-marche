import Foundation
import Observation
import os
import WalkingPadKit

/// Wires the pad, the session tracker and the local store; exposes what the menu shows.
@MainActor
@Observable
final class AppModel {
    private(set) var presence: PadPresence = .absent
    private(set) var dashboard: Dashboard = .empty
    private(set) var recentSessions: [WalkSession] = []
    private(set) var syncStatus: SyncStatus?

    let calendar = WeeklySummary.isoCalendar
    var title: String { MenuText.title(presence, dashboard) }

    private static let tickInterval: Duration = .seconds(30)
    private static let sampleRetention: TimeInterval = 7 * 24 * 3600
    private static let releaseDuration: TimeInterval = 15 * 60

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private var tracker: SessionTracker
    @ObservationIgnored private let connection = PadConnection()
    @ObservationIgnored private let log = Logger(subsystem: "ch.davidpreti.TapisMarche", category: "journal")

    init() {
        do {
            store = try SessionStore(path: Self.databasePath())
            tracker = try SessionRecovery.recover(store: store, now: .now)
        } catch {
            // Never fall back to an in-memory journal: losing walks silently is the one thing this app must not do.
            fatalError("Cannot open the walking journal: \(error)")
        }
        connection.onPresence = { [weak self] in self?.presence = $0 }
        connection.onSample = { [weak self] in self?.ingest($0) }
        connection.start()
        refresh()
        startTicking()
    }

    func releasePad() {
        connection.release(for: Self.releaseDuration)
    }

    private func ingest(_ sample: TreadmillSample) {
        record { try store.append(sample) }
        if let closed = tracker.ingest(sample) { save(closed) }
        refresh()
    }

    private func tick() {
        if let closed = tracker.tick(now: .now) { save(closed) }
        record { try store.pruneSamples(before: Date.now.addingTimeInterval(-Self.sampleRetention)) }
        refresh()
    }

    private func save(_ session: WalkSession) {
        record { try store.save(session) }
        log.notice("session closed \(session.totals.distanceM, privacy: .public) m in \(session.totals.activeSeconds, privacy: .public) s")
    }

    private func refresh() {
        let now = Date.now
        let recent = (try? store.sessions(in: DateInterval(start: now.addingTimeInterval(-14 * 24 * 3600), end: now))) ?? []
        recentSessions = Array(recent.suffix(5).reversed())
        dashboard = Dashboard.make(closed: recent, open: tracker.openSession, now: now, calendar: calendar)
    }

    private func startTicking() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.tick()
            }
        }
    }

    private func record(_ write: () throws -> Void) {
        do { try write() } catch { log.error("journal write failed: \(error.localizedDescription, privacy: .public)") }
    }

    private static func databasePath() throws -> String {
        let folder = URL.applicationSupportDirectory.appending(path: "TapisMarche")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "journal.sqlite").path
    }
}
