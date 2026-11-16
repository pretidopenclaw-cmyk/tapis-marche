import Foundation

public struct SyncStatus: Equatable, Sendable {
    public var pending: Int
    public var lastError: NotionError?

    public init(pending: Int, lastError: NotionError?) {
        self.pending = pending
        self.lastError = lastError
    }
}

/// Pushes local sessions and weekly recaps to Notion. Safe to call any number of times:
/// a session is matched on its « ID » before being created, a recap is replaced only when its data changed.
public actor NotionSync {
    private let store: SessionStore
    private let client: NotionClient
    private let config: NotionConfig
    private let calendar: Calendar

    public init(store: SessionStore, client: NotionClient, config: NotionConfig, calendar: Calendar) {
        self.store = store
        self.client = client
        self.config = config
        self.calendar = calendar
    }

    /// Syncs pending sessions oldest first; stops at the first error and keeps the rest pending.
    public func syncSessions() async -> SyncStatus {
        let error = await attempt {
            for session in try store.unsyncedSessions() {
                var pageId = try await client.findSessionPage(session.id, in: config)
                if pageId == nil {
                    pageId = try await client.createSessionPage(session, in: config, calendar: calendar)
                }
                try store.markSynced(session.id, notionPageId: pageId!)
            }
        }
        return status(error)
    }

    /// Publishes (or refreshes) the recap of every finished week that has at least one session.
    public func syncRecaps(now: Date) async -> SyncStatus {
        let error = await attempt {
            for weekStart in try finishedWeeks(before: now) {
                try await syncRecap(weekStart: weekStart)
            }
        }
        return status(error)
    }

    private func syncRecap(weekStart: Date) async throws {
        let sessions = try store.sessions(in: week(startingAt: weekStart))
        guard !sessions.isEmpty else { return }
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
        let summary = WeeklySummary.make(sessions: sessions, previousWeek: try store.sessions(in: week(startingAt: previousStart)),
                                         weekStart: weekStart, calendar: calendar)
        let existing = try store.recap(weekStart: weekStart)
        guard existing?.fingerprint != summary.fingerprint else { return }
        if let existing { try await trashIgnoringMissing(existing.notionPageId) }
        let pageId = try await client.createRecapPage(summary, in: config)
        try store.saveRecap(RecapRecord(weekStart: weekStart, notionPageId: pageId, fingerprint: summary.fingerprint))
    }

    /// Week starts from the first recorded session up to the last week that ended at or before `now`.
    private func finishedWeeks(before now: Date) throws -> [Date] {
        guard let first = try store.earliestSessionStart() else { return [] }
        var weeks: [Date] = []
        var start = WeeklySummary.weekStart(containing: first, calendar: calendar)
        while week(startingAt: start).end <= now {
            weeks.append(start)
            start = week(startingAt: start).end
        }
        return weeks
    }

    private func week(startingAt start: Date) -> DateInterval {
        calendar.dateInterval(of: .weekOfYear, for: start)!
    }

    /// A recap David already deleted in Notion must not block its replacement.
    private func trashIgnoringMissing(_ pageId: String) async throws {
        do {
            try await client.trashPage(pageId)
        } catch NotionError.http(status: 404, _) {
            return
        }
    }

    private func attempt(_ work: () async throws -> Void) async -> NotionError? {
        do {
            try await work()
            return nil
        } catch let error as NotionError {
            return error
        } catch {
            return .other(error.localizedDescription)
        }
    }

    private func status(_ error: NotionError?) -> SyncStatus {
        let pending = (try? store.unsyncedSessions().count) ?? 0
        return SyncStatus(pending: pending, lastError: error)
    }
}
