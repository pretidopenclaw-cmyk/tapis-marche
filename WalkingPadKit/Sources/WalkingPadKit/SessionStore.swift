import Foundation
import GRDB

/// A weekly recap already published to Notion, and the fingerprint of the data it showed.
public struct RecapRecord: Equatable, Sendable {
    public var weekStart: Date
    public var notionPageId: String
    public var fingerprint: String

    public init(weekStart: Date, notionPageId: String, fingerprint: String) {
        self.weekStart = weekStart
        self.notionPageId = notionPageId
        self.fingerprint = fingerprint
    }
}

/// Local source of truth: raw samples, closed sessions and published recaps (SQLite).
public final class SessionStore: Sendable {
    private let db: DatabaseQueue
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// `path == nil` opens an in-memory database (tests).
    public init(path: String?) throws {
        db = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        try Self.migrator.migrate(db)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE sample (timestamp REAL PRIMARY KEY, json BLOB NOT NULL);
                CREATE TABLE session (id TEXT PRIMARY KEY, start REAL NOT NULL, "end" REAL NOT NULL,
                                      json BLOB NOT NULL, notionPageId TEXT);
                CREATE INDEX session_start ON session(start);
                CREATE TABLE recap (weekStart REAL PRIMARY KEY, notionPageId TEXT NOT NULL, fingerprint TEXT NOT NULL);
                """)
        }
        return migrator
    }

    public func append(_ sample: TreadmillSample) throws {
        let json = try encoder.encode(sample)
        try db.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO sample (timestamp, json) VALUES (?, ?)",
                           arguments: [sample.timestamp.timeIntervalSince1970, json])
        }
    }

    public func samples(after date: Date?) throws -> [TreadmillSample] {
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT json FROM sample WHERE timestamp > ? ORDER BY timestamp",
                             arguments: [date?.timeIntervalSince1970 ?? -Double.infinity])
        }
        return try rows.map { try decoder.decode(TreadmillSample.self, from: $0["json"] as Data) }
    }

    /// Upsert by id; never clears the Notion page id of an already synced session.
    public func save(_ session: WalkSession) throws {
        let json = try encoder.encode(session)
        try db.write { db in
            try db.execute(sql: """
                INSERT INTO session (id, start, "end", json) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET start = excluded.start, "end" = excluded."end", json = excluded.json
                """, arguments: [session.id.uuidString, session.start.timeIntervalSince1970,
                                 session.end.timeIntervalSince1970, json])
        }
    }

    /// Sessions whose start falls in `interval` (start inclusive, end exclusive).
    public func sessions(in interval: DateInterval) throws -> [WalkSession] {
        try fetchSessions(where: "start >= ? AND start < ?",
                          [interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970])
    }

    public func unsyncedSessions() throws -> [WalkSession] {
        try fetchSessions(where: "notionPageId IS NULL", [])
    }

    public func markSynced(_ id: UUID, notionPageId: String) throws {
        try db.write { db in
            try db.execute(sql: "UPDATE session SET notionPageId = ? WHERE id = ?",
                           arguments: [notionPageId, id.uuidString])
        }
    }

    public func lastClosedSessionEnd() throws -> Date? {
        let end = try db.read { db in try Double.fetchOne(db, sql: #"SELECT MAX("end") FROM session"#) }
        return end.map(Date.init(timeIntervalSince1970:))
    }

    public func pruneSamples(before date: Date) throws {
        try db.write { db in
            try db.execute(sql: "DELETE FROM sample WHERE timestamp < ?", arguments: [date.timeIntervalSince1970])
        }
    }

    public func recap(weekStart: Date) throws -> RecapRecord? {
        let row = try db.read { db in
            try Row.fetchOne(db, sql: "SELECT notionPageId, fingerprint FROM recap WHERE weekStart = ?",
                             arguments: [weekStart.timeIntervalSince1970])
        }
        return row.map { RecapRecord(weekStart: weekStart, notionPageId: $0["notionPageId"], fingerprint: $0["fingerprint"]) }
    }

    public func saveRecap(_ record: RecapRecord) throws {
        try db.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO recap (weekStart, notionPageId, fingerprint) VALUES (?, ?, ?)",
                           arguments: [record.weekStart.timeIntervalSince1970, record.notionPageId, record.fingerprint])
        }
    }

    private func fetchSessions(where condition: String, _ arguments: [Double]) throws -> [WalkSession] {
        let rows = try db.read { db in
            try Row.fetchAll(db, sql: "SELECT json FROM session WHERE \(condition) ORDER BY start",
                             arguments: StatementArguments(arguments))
        }
        return try rows.map { try decoder.decode(WalkSession.self, from: $0["json"] as Data) }
    }
}
