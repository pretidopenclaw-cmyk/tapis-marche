import Foundation
import Testing
@testable import WalkingPadKit

private let calendar: Calendar = {
    var c = WeeklySummary.isoCalendar
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

private func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
}

private func walk(_ start: Date, seconds: Int, meters: Int, steps: Int?) -> WalkSession {
    WalkSession(start: start, end: start.addingTimeInterval(TimeInterval(seconds)),
                totals: SessionTotals(activeSeconds: seconds, distanceM: meters, steps: steps, energyKcal: 0,
                                      avgSpeedKmh: 3, maxSpeedKmh: 4))
}

private let now = date(18, 16)  // Wednesday, week 47

@Test func dashboardAddsTodayAndWeekIncludingOpenSession() {
    let closed = [walk(date(16, 9), seconds: 3600, meters: 4000, steps: 5000),   // Monday
                  walk(date(18, 9), seconds: 5400, meters: 6000, steps: 8000)]   // today
    let open = walk(date(18, 15), seconds: 1500, meters: 2400, steps: 4340)
    let d = Dashboard.make(closed: closed, open: open, now: now, calendar: calendar)
    #expect(d == Dashboard(todayActiveSeconds: 6900, todayDistanceM: 8400, todaySteps: 12340,
                           weekActiveSeconds: 10500, weekDistanceM: 12400))
}

@Test func dashboardStepsNilWhenPadNeverReportsThem() {
    let d = Dashboard.make(closed: [walk(date(18, 9), seconds: 600, meters: 700, steps: nil)], open: nil,
                           now: now, calendar: calendar)
    #expect(d.todaySteps == nil)
}

@Test func menuTitleFollowsPadState() {
    let d = Dashboard(todayActiveSeconds: 7500, todayDistanceM: 8400, todaySteps: 12340,
                      weekActiveSeconds: 0, weekDistanceM: 0)
    #expect(MenuText.title(.connected(speedKmh: 3.5), d) == "🚶 3,5 km/h · 12 340 pas")
    #expect(MenuText.title(.connected(speedKmh: 0), d) == "🚶 · 12 340 pas")
    #expect(MenuText.title(.absent, d) == "🚶̸")
    #expect(MenuText.title(.released(until: now), d) == "🚶̸")
    var noSteps = d
    noSteps.todaySteps = nil
    #expect(MenuText.title(.connected(speedKmh: 0), noSteps) == "🚶 · 8,4 km")
}

@Test func menuLinesMatchTheSpecMockup() {
    let d = Dashboard(todayActiveSeconds: 7500, todayDistanceM: 8400, todaySteps: 12340,
                      weekActiveSeconds: 27600, weekDistanceM: 31200)
    #expect(MenuText.today(d) == "Aujourd'hui : 2 h 05 · 8,4 km · 12 340 pas")
    #expect(MenuText.week(d) == "Cette semaine : 7 h 40 · 31,2 km")
}

@Test func notionLineCountsPendingSessions() {
    #expect(MenuText.notion(nil, configured: false) == "Notion : non configuré")
    #expect(MenuText.notion(SyncStatus(pending: 0, lastError: nil), configured: true) == "Notion : à jour")
    #expect(MenuText.notion(SyncStatus(pending: 1, lastError: nil), configured: true) == "Notion : 1 séance en attente")
    #expect(MenuText.notion(SyncStatus(pending: 3, lastError: .unauthorized), configured: true)
            == "Notion : 3 séances en attente")
    #expect(MenuText.notion(nil, configured: true) == "Notion : à jour")
}

@Test func sessionLineForRecentSessionsMenu() {
    let s = walk(date(16, 14, 5), seconds: 1500, meters: 1250, steps: 1830)
    #expect(MenuText.session(s, calendar: calendar) == "lun. 16 nov. · 14:05 — 25 min · 1,3 km")
}
