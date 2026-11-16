import Foundation
import Testing
@testable import WalkingPadKit

private let t0 = Date(timeIntervalSince1970: 1_794_000_000)

private func session(startingAt second: Int, minutes: Int = 10) -> WalkSession {
    WalkSession(start: t0.addingTimeInterval(TimeInterval(second)),
                end: t0.addingTimeInterval(TimeInterval(second + minutes * 60)),
                totals: SessionTotals(activeSeconds: minutes * 60, distanceM: minutes * 60, steps: 42,
                                      energyKcal: 7, avgSpeedKmh: 3.6, maxSpeedKmh: 4.0))
}

private func appendWalk(_ store: SessionStore, seconds: Int) throws {
    for s in 0..<seconds {
        try store.append(TreadmillSample(timestamp: t0.addingTimeInterval(TimeInterval(s)), speedKmh: 3.6,
                                         distanceM: s, energyKcal: 0, steps: s * 2))
    }
}

@Test func savedSessionRoundTrips() throws {
    let store = try SessionStore(path: nil)
    let original = session(startingAt: 0)
    try store.save(original)
    let all = try store.sessions(in: DateInterval(start: t0, duration: 3600))
    #expect(all == [original])
}

@Test func unsyncedListsOnlySessionsWithoutNotionPage() throws {
    let store = try SessionStore(path: nil)
    let a = session(startingAt: 0), b = session(startingAt: 3600)
    try store.save(a)
    try store.save(b)
    try store.markSynced(a.id, notionPageId: "page-a")
    #expect(try store.unsyncedSessions() == [b])
}

@Test func resavingASyncedSessionKeepsItSynced() throws {
    let store = try SessionStore(path: nil)
    let a = session(startingAt: 0)
    try store.save(a)
    try store.markSynced(a.id, notionPageId: "page-a")
    try store.save(a)
    #expect(try store.unsyncedSessions().isEmpty)
}

@Test func sessionsInIntervalFilterByStart() throws {
    let store = try SessionStore(path: nil)
    let inside = session(startingAt: 3000, minutes: 30) // starts inside, ends after the interval
    try store.save(session(startingAt: -600))
    try store.save(inside)
    try store.save(session(startingAt: 3600))
    #expect(try store.sessions(in: DateInterval(start: t0, duration: 3600)) == [inside])
}

@Test func recoverClosesSessionLeftOpenByCrash() throws {
    let store = try SessionStore(path: nil)
    try appendWalk(store, seconds: 600)
    let tracker = try SessionRecovery.recover(store: store, now: t0.addingTimeInterval(599 + 240))
    let saved = try store.sessions(in: DateInterval(start: t0, duration: 3600))
    #expect(saved.count == 1)
    #expect(saved.first?.totals.distanceM == 599)
    #expect(tracker.openSession == nil)
}

@Test func recoverTwiceSavesOneSession() throws {
    let store = try SessionStore(path: nil)
    try appendWalk(store, seconds: 600)
    let now = t0.addingTimeInterval(599 + 240)
    _ = try SessionRecovery.recover(store: store, now: now)
    _ = try SessionRecovery.recover(store: store, now: now)
    #expect(try store.sessions(in: DateInterval(start: t0, duration: 3600)).count == 1)
}

@Test func recoverKeepsStillOpenSessionInTracker() throws {
    let store = try SessionStore(path: nil)
    try appendWalk(store, seconds: 600)
    let tracker = try SessionRecovery.recover(store: store, now: t0.addingTimeInterval(599 + 30))
    #expect(try store.sessions(in: DateInterval(start: t0, duration: 3600)).isEmpty)
    #expect(tracker.openSession?.start == t0)
}

@Test func pruneRemovesOnlyOlderSamples() throws {
    let store = try SessionStore(path: nil)
    try appendWalk(store, seconds: 10)
    try store.pruneSamples(before: t0.addingTimeInterval(5))
    let left = try store.samples(after: nil)
    #expect(left.map(\.timestamp) == (5..<10).map { t0.addingTimeInterval(TimeInterval($0)) })
}

@Test func recapRecordRoundTrips() throws {
    let store = try SessionStore(path: nil)
    let record = RecapRecord(weekStart: t0, notionPageId: "recap-1", fingerprint: "abc")
    try store.saveRecap(record)
    #expect(try store.recap(weekStart: t0) == record)
    try store.saveRecap(RecapRecord(weekStart: t0, notionPageId: "recap-2", fingerprint: "def"))
    #expect(try store.recap(weekStart: t0)?.notionPageId == "recap-2")
}

@Test func storePersistsAcrossReopen() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    let original = session(startingAt: 0)
    try SessionStore(path: path).save(original)
    #expect(try SessionStore(path: path).sessions(in: DateInterval(start: t0, duration: 3600)) == [original])
}
