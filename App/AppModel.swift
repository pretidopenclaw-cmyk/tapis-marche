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
    private(set) var notionConfigured = false

    let calendar = WeeklySummary.isoCalendar
    var title: String { MenuText.title(presence, dashboard) }
    var notionLine: String { MenuText.notion(syncStatus, configured: notionConfigured) }

    private static let tickInterval: Duration = .seconds(30)
    private static let sampleRetention: TimeInterval = 7 * 24 * 3600
    private static let releaseDuration: TimeInterval = 15 * 60
    private static let recapInterval: TimeInterval = 3600
    private static let notionConfigKey = "notionConfig"

    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private var tracker: SessionTracker
    @ObservationIgnored private let connection = PadConnection()
    @ObservationIgnored private let log = Logger(subsystem: "ch.davidpreti.TapisMarche", category: "journal")
    @ObservationIgnored private var sync: NotionSync?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var lastSyncAt = Date.distantPast

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
        configureSync()
        syncNow()
        startTicking()
    }

    // MARK: - Notion

    /// Creates the Notion workspace under the shared page; returns a French message for the settings window.
    func connectNotion(token: String, parentPage: String) async -> String {
        guard let parentId = NotionPageId.parse(parentPage) else { return "Lien de page Notion invalide." }
        do {
            let config = try await NotionClient(token: token, transport: URLSessionTransport())
                .setUpWorkspace(parentPageId: parentId)
            try Keychain.write(token)
            UserDefaults.standard.set(try JSONEncoder().encode(config), forKey: Self.notionConfigKey)
            configureSync()
            syncNow()
            return "Notion connecté."
        } catch NotionError.unauthorized {
            return "Jeton refusé par Notion."
        } catch NotionError.http(let status, _) where status == 404 {
            return "Page introuvable : partage-la avec ton intégration Notion."
        } catch {
            return "Échec de la connexion à Notion : \(error)"
        }
    }

    func disconnectNotion() {
        Keychain.delete()
        UserDefaults.standard.removeObject(forKey: Self.notionConfigKey)
        retry?.cancel()
        sync = nil
        notionConfigured = false
        syncStatus = nil
    }

    private func configureSync() {
        guard let token = Keychain.read(),
              let data = UserDefaults.standard.data(forKey: Self.notionConfigKey),
              let config = try? JSONDecoder().decode(NotionConfig.self, from: data) else { return }
        sync = NotionSync(store: store, client: NotionClient(token: token, transport: URLSessionTransport()),
                          config: config, calendar: calendar)
        notionConfigured = true
    }

    /// Sessions first, then recaps; on failure, retries after 1, 2, 5, then every 15 minutes.
    private func syncNow() {
        guard let sync else { return }
        retry?.cancel()
        lastSyncAt = .now
        Task {
            let sessions = await sync.syncSessions()
            let recaps = await sync.syncRecaps(now: .now)
            let error = sessions.lastError ?? recaps.lastError
            syncStatus = SyncStatus(pending: sessions.pending, lastError: error)
            if let error {
                failures += 1
                log.error("notion sync failed (\(self.failures, privacy: .public)): \(String(describing: error), privacy: .public)")
                scheduleRetry()
            } else {
                failures = 0
                log.notice("notion sync ok")
            }
        }
    }

    private func scheduleRetry() {
        let delay = RetrySchedule.delaySeconds(afterFailures: failures)
        retry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.syncNow()
        }
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
        if failures == 0, Date.now.timeIntervalSince(lastSyncAt) >= Self.recapInterval { syncNow() }
        refresh()
    }

    private func save(_ session: WalkSession) {
        record { try store.save(session) }
        log.notice("session closed \(session.totals.distanceM, privacy: .public) m in \(session.totals.activeSeconds, privacy: .public) s")
        syncNow()
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
