import Foundation
import Testing
@testable import WalkingPadKit

private let calendar: Calendar = {
    var c = WeeklySummary.isoCalendar
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

private let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 14, minute: 5))!
private let config = NotionConfig(dataSourceId: "ds-1", recapsPageId: "recaps-1")

private func session(steps: Int? = 1830) -> WalkSession {
    WalkSession(id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
                start: start, end: start.addingTimeInterval(1500),
                totals: SessionTotals(activeSeconds: 1500, distanceM: 1250, steps: steps, energyKcal: 64,
                                      avgSpeedKmh: 3.0, maxSpeedKmh: 4.25))
}

private func property(_ json: [String: Any], _ name: String) -> [String: Any]? {
    (json["properties"] as? [String: Any])?[name] as? [String: Any]
}

private func plainText(_ richText: Any?) -> String? {
    ((richText as? [[String: Any]])?.first?["text"] as? [String: Any])?["content"] as? String
}

@Test func parsesPageIdFromNotionURL() {
    let url = "https://www.notion.so/david/Tapis-marche-1a2b3c4d5e6f708192a3b4c5d6e7f809?pvs=4"
    #expect(NotionPageId.parse(url) == "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809")
    #expect(NotionPageId.parse("1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809") == "1a2b3c4d-5e6f-7081-92a3-b4c5d6e7f809")
    #expect(NotionPageId.parse("https://www.notion.so/nothing-here") == nil)
}

@Test func setUpWorkspaceCreatesDatabaseAndRecapsPage() async throws {
    let transport = FakeTransport()
    transport.enqueue(200, #"{"id": "db-1", "data_sources": [{"id": "ds-9", "name": "Marches"}]}"#)
    transport.enqueue(200, #"{"id": "recaps-9"}"#)
    let result = try await NotionClient(token: "secret", transport: transport).setUpWorkspace(parentPageId: "parent-1")
    #expect(result == NotionConfig(dataSourceId: "ds-9", recapsPageId: "recaps-9"))
    let (db, recaps) = (transport.sent[0], transport.sent[1])
    #expect(db.method == "POST" && db.path == "/v1/databases")
    #expect((db.json["parent"] as? [String: String])?["page_id"] == "parent-1")
    let schema = (db.json["initial_data_source"] as? [String: Any])?["properties"] as? [String: Any]
    #expect(Set(schema?.keys ?? [:].keys) == ["Séance", "Date", "Début", "Fin", "Durée (min)", "Distance (km)", "Pas",
                                               "Vitesse moy. (km/h)", "Vitesse max (km/h)", "kcal", "ID"])
    #expect(recaps.path == "/v1/pages")
    #expect(plainText(property(recaps.json, "title")?["title"]) == "Récaps hebdo")
}

@Test func sessionPageHasExactPropertiesAndParent() async throws {
    let transport = FakeTransport()
    let pageId = try await NotionClient(token: "secret", transport: transport)
        .createSessionPage(session(), in: config, calendar: calendar)
    #expect(pageId == "page-1")
    let json = transport.sent[0].json
    #expect((json["parent"] as? [String: String]) == ["type": "data_source_id", "data_source_id": "ds-1"])
    #expect(plainText(property(json, "Séance")?["title"]) == "lun. 16 nov. · 14:05")
    #expect((property(json, "Date")?["date"] as? [String: String])?["start"] == "2026-11-16")
    #expect((property(json, "Début")?["date"] as? [String: String])?["start"] == "2026-11-16T14:05:00+01:00")
    #expect(property(json, "Durée (min)")?["number"] as? Double == 25)
    #expect(property(json, "Distance (km)")?["number"] as? Double == 1.25)
    #expect(property(json, "Pas")?["number"] as? Double == 1830)
    #expect(property(json, "Vitesse moy. (km/h)")?["number"] as? Double == 3.0)
    #expect(property(json, "Vitesse max (km/h)")?["number"] as? Double == 4.3)
    #expect(property(json, "kcal")?["number"] as? Double == 64)
    #expect(plainText(property(json, "ID")?["rich_text"]) == "11111111-2222-3333-4444-555555555555")
}

@Test func sessionPageOmitsStepsWhenNil() async throws {
    let transport = FakeTransport()
    _ = try await NotionClient(token: "secret", transport: transport)
        .createSessionPage(session(steps: nil), in: config, calendar: calendar)
    #expect(property(transport.sent[0].json, "Pas") == nil)
}

@Test func recapLinesMatchTheSpecFormat() {
    let summary = WeeklySummary(weekStart: start, isoWeek: 47, sessionCount: 5, activeSeconds: 7 * 3600 + 40 * 60,
                                distanceM: 31_200, steps: 41_380,
                                perDayActiveSeconds: [0, 60, 120, 0, 0, 0, 0],
                                bestDay: .init(weekdayIndex: 1, activeSeconds: 2 * 3600 + 10 * 60, distanceM: 9100),
                                previousWeekDistanceM: 26_900, fingerprint: "f", title: "Semaine 47 — 16-22 nov.")
    #expect(NotionPayloads.recapLines(summary) == [
        "5 séances · 7 h 40 de marche · 31,2 km · 41 380 pas",
        "Meilleur jour : mardi (2 h 10, 9,1 km)",
        "vs semaine précédente : +4,3 km",
    ])
}

@Test func recapPageUsesSummaryTitleUnderRecapsPage() async throws {
    let transport = FakeTransport()
    let summary = WeeklySummary.make(sessions: [session()], previousWeek: [], weekStart: start, calendar: calendar)
    _ = try await NotionClient(token: "secret", transport: transport).createRecapPage(summary, in: config)
    let json = transport.sent[0].json
    #expect((json["parent"] as? [String: String])?["page_id"] == "recaps-1")
    #expect(plainText(property(json, "title")?["title"]) == summary.title)
    let children = json["children"] as? [[String: Any]] ?? []
    #expect(children.contains { ($0["type"] as? String) == "code" })
}

@Test func trashUsesInTrash() async throws {
    let transport = FakeTransport()
    try await NotionClient(token: "secret", transport: transport).trashPage("page-7")
    #expect(transport.sent[0].method == "PATCH" && transport.sent[0].path == "/v1/pages/page-7")
    #expect(transport.sent[0].json["in_trash"] as? Bool == true)
}

@Test func everyRequestCarriesVersionAndBearer() async throws {
    let transport = FakeTransport()
    _ = try await NotionClient(token: "secret", transport: transport)
        .createSessionPage(session(), in: config, calendar: calendar)
    let headers = transport.sent[0].headers
    #expect(headers["Authorization"] == "Bearer secret")
    #expect(headers["Notion-Version"] == "2026-03-11")
    #expect(headers["Content-Type"] == "application/json")
}

@Test func mapsStatusCodesToErrors() async {
    let transport = FakeTransport()
    transport.enqueue(401, "{}")
    transport.enqueue(429, "{}")
    transport.enqueue(500, "boom")
    let client = NotionClient(token: "secret", transport: transport)
    await #expect(throws: NotionError.unauthorized) { try await client.trashPage("p") }
    await #expect(throws: NotionError.rateLimited) { try await client.trashPage("p") }
    await #expect(throws: NotionError.http(status: 500, body: "boom")) { try await client.trashPage("p") }
}

@Test func findSessionPageQueriesDataSourceByID() async throws {
    let transport = FakeTransport()
    transport.enqueue(200, #"{"object": "list", "results": [{"id": "existing-1"}]}"#)
    transport.enqueue(200, #"{"object": "list", "results": []}"#)
    let client = NotionClient(token: "secret", transport: transport)
    #expect(try await client.findSessionPage(session().id, in: config) == "existing-1")
    #expect(try await client.findSessionPage(session().id, in: config) == nil)
    let query = transport.sent[0]
    #expect(query.method == "POST" && query.path == "/v1/data_sources/ds-1/query")
    let filter = query.json["filter"] as? [String: Any]
    #expect(filter?["property"] as? String == "ID")
    #expect((filter?["rich_text"] as? [String: String])?["equals"] == "11111111-2222-3333-4444-555555555555")
}
