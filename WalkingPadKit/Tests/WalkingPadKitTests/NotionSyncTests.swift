import Foundation
import Testing
@testable import WalkingPadKit

private let calendar: Calendar = {
    var c = WeeklySummary.isoCalendar
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

private func date(_ d: Int, _ h: Int = 9) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h))!
}

private let config = NotionConfig(dataSourceId: "ds-1", recapsPageId: "recaps-1")
private let week47 = date(16, 0)
private let afterWeek47 = date(23, 8)   // Monday of week 48
private let midWeek47 = date(19, 12)

private func walk(_ start: Date) -> WalkSession {
    WalkSession(start: start, end: start.addingTimeInterval(1800),
                totals: SessionTotals(activeSeconds: 1800, distanceM: 2000, steps: 2600, energyKcal: 80,
                                      avgSpeedKmh: 4, maxSpeedKmh: 4.5))
}

private func makeSync(_ sessions: [WalkSession]) throws -> (NotionSync, SessionStore, FakeTransport) {
    let store = try SessionStore(path: nil)
    try sessions.forEach(store.save)
    let transport = FakeTransport()
    let sync = NotionSync(store: store, client: NotionClient(token: "t", transport: transport),
                          config: config, calendar: calendar)
    return (sync, store, transport)
}

private func pageCreations(_ transport: FakeTransport) -> [FakeTransport.Sent] {
    transport.sent.filter { $0.method == "POST" && $0.path == "/v1/pages" }
}

@Test func syncCreatesOnePagePerPendingSessionAndMarksThem() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16)), walk(date(17))])
    let status = await sync.syncSessions()
    #expect(status == SyncStatus(pending: 0, lastError: nil))
    #expect(pageCreations(transport).count == 2)
    #expect(try store.unsyncedSessions().isEmpty)
}

@Test func secondSyncSendsNothing() async throws {
    let (sync, _, transport) = try makeSync([walk(date(16))])
    _ = await sync.syncSessions()
    let before = transport.sent.count
    _ = await sync.syncSessions()
    #expect(transport.sent.count == before)
}

@Test func sessionAlreadyInNotionIsLinkedNotRecreated() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16))])
    transport.enqueue(200, #"{"object": "list", "results": [{"id": "existing-1"}]}"#)
    let status = await sync.syncSessions()
    #expect(status.pending == 0)
    #expect(pageCreations(transport).isEmpty)
    #expect(try store.unsyncedSessions().isEmpty)
}

@Test func unauthorizedKeepsSessionsPending() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16)), walk(date(17))])
    transport.enqueue(401, "{}")
    let status = await sync.syncSessions()
    #expect(status == SyncStatus(pending: 2, lastError: .unauthorized))
    #expect(try store.unsyncedSessions().count == 2)
}

@Test func retryAfterFailureCreatesExactlyOnePage() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16))])
    transport.enqueue(200, #"{"results": []}"#)  // lookup: not there yet
    transport.enqueue(500, "boom")               // create fails
    let failed = await sync.syncSessions()
    #expect(failed.pending == 1)
    #expect(failed.lastError == .http(status: 500, body: "boom"))
    let retried = await sync.syncSessions()
    #expect(retried == SyncStatus(pending: 0, lastError: nil))
    #expect(pageCreations(transport).count == 2)  // one failed attempt, one success
    #expect(try store.unsyncedSessions().isEmpty)
}

@Test func unfinishedWeekGetsNoRecap() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16))])
    _ = await sync.syncRecaps(now: midWeek47)
    #expect(transport.sent.isEmpty)
    #expect(try store.recap(weekStart: week47) == nil)
}

@Test func finishedWeekGetsRecapOnce() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16)), walk(date(18))])
    _ = await sync.syncRecaps(now: afterWeek47)
    _ = await sync.syncRecaps(now: afterWeek47)
    let recaps = pageCreations(transport).filter { ($0.json["parent"] as? [String: String])?["page_id"] == "recaps-1" }
    #expect(recaps.count == 1)
    #expect(try store.recap(weekStart: week47)?.notionPageId == "page-1")
}

@Test func weekWithoutSessionsGetsNoRecap() async throws {
    let (sync, _, transport) = try makeSync([walk(date(2))])  // week 45 only
    _ = await sync.syncRecaps(now: afterWeek47)
    #expect(pageCreations(transport).count == 1)  // week 45; weeks 46 and 47 are empty
}

@Test func lateSessionReplacesExistingRecap() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16))])
    _ = await sync.syncRecaps(now: afterWeek47)
    let first = try #require(try store.recap(weekStart: week47))
    try store.save(walk(date(22, 23)))  // Sunday-night walk saved late
    _ = await sync.syncRecaps(now: afterWeek47)
    #expect(transport.sent.contains { $0.method == "PATCH" && $0.path == "/v1/pages/\(first.notionPageId)" })
    let second = try #require(try store.recap(weekStart: week47))
    #expect(second.notionPageId != first.notionPageId)
    #expect(second.fingerprint != first.fingerprint)
}

@Test func recapAlreadyDeletedInNotionIsStillReplaced() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16))])
    _ = await sync.syncRecaps(now: afterWeek47)
    try store.save(walk(date(20)))
    transport.enqueue(404, #"{"code": "object_not_found"}"#)
    let status = await sync.syncRecaps(now: afterWeek47)
    #expect(status.lastError == nil)
    #expect(pageCreations(transport).count == 2)
}

@Test func overlappingSyncsCreateEachSessionOnce() async throws {
    let store = try SessionStore(path: nil)
    try store.save(walk(date(16)))
    let transport = FakeTransport(latency: .milliseconds(30))
    let sync = NotionSync(store: store, client: NotionClient(token: "t", transport: transport),
                          config: config, calendar: calendar)
    async let first = sync.syncSessions()
    async let second = sync.syncSessions()
    _ = await (first, second)
    #expect(pageCreations(transport).count == 1)
}

@Test func recapRecoversAfterCreateFailedOnceOldPageTrashed() async throws {
    let (sync, store, transport) = try makeSync([walk(date(16))])
    _ = await sync.syncRecaps(now: afterWeek47)
    try store.save(walk(date(20)))
    transport.enqueue(200, "{}")                                   // trash old recap: ok
    transport.enqueue(500, "boom")                                 // create new recap: fails
    #expect(await sync.syncRecaps(now: afterWeek47).lastError == .http(status: 500, body: "boom"))
    transport.enqueue(400, #"{"code": "validation_error", "message": "archived"}"#)  // old page already in trash
    let retried = await sync.syncRecaps(now: afterWeek47)
    #expect(retried.lastError == nil)
    #expect(pageCreations(transport).count == 3)   // first recap, failed attempt, replacement
}
