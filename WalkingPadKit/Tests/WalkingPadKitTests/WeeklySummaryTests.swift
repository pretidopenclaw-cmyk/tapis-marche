import Foundation
import Testing
@testable import WalkingPadKit

private let calendar: Calendar = {
    var c = WeeklySummary.isoCalendar
    c.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func walk(_ start: Date, minutes: Int, meters: Int = 1000, steps: Int? = 1500) -> WalkSession {
    WalkSession(start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                totals: SessionTotals(activeSeconds: minutes * 60, distanceM: meters, steps: steps,
                                      energyKcal: 0, avgSpeedKmh: 3, maxSpeedKmh: 4))
}

private let week47 = date(2026, 11, 16)

@Test func weekStartIsMondayMidnight() {
    #expect(WeeklySummary.weekStart(containing: date(2026, 11, 22, 23, 30), calendar: calendar) == week47)
}

@Test func titleWithinOneMonth() {
    let summary = WeeklySummary.make(sessions: [], previousWeek: [], weekStart: week47, calendar: calendar)
    #expect(summary.title == "Semaine 47 — 16-22 nov.")
}

@Test func titleAcrossTwoMonths() {
    let summary = WeeklySummary.make(sessions: [], previousWeek: [], weekStart: date(2026, 11, 30), calendar: calendar)
    #expect(summary.title == "Semaine 49 — 30 nov.-6 déc.")
}

@Test func sessionCrossingMidnightCountsOnStartDay() {
    let late = walk(date(2026, 11, 22, 23, 30), minutes: 70)
    let summary = WeeklySummary.make(sessions: [late], previousWeek: [], weekStart: week47, calendar: calendar)
    #expect(summary.perDayActiveSeconds == [0, 0, 0, 0, 0, 0, 70 * 60])
}

@Test func totalsAddUpAndCompareToPreviousWeek() {
    let sessions = [walk(date(2026, 11, 16, 9), minutes: 30, meters: 2000),
                    walk(date(2026, 11, 17, 14), minutes: 45, meters: 3000)]
    let previous = [walk(date(2026, 11, 10, 9), minutes: 20, meters: 1500)]
    let summary = WeeklySummary.make(sessions: sessions, previousWeek: previous, weekStart: week47, calendar: calendar)
    #expect(summary.isoWeek == 47)
    #expect(summary.sessionCount == 2)
    #expect(summary.activeSeconds == 75 * 60)
    #expect(summary.distanceM == 5000)
    #expect(summary.steps == 3000)
    #expect(summary.previousWeekDistanceM == 1500)
}

@Test func bestDayIsLongestActiveDay() {
    let sessions = [walk(date(2026, 11, 16, 9), minutes: 30, meters: 2000),
                    walk(date(2026, 11, 17, 9), minutes: 50, meters: 3000),
                    walk(date(2026, 11, 17, 15), minutes: 20, meters: 1200)]
    let summary = WeeklySummary.make(sessions: sessions, previousWeek: [], weekStart: week47, calendar: calendar)
    #expect(summary.bestDay == .init(weekdayIndex: 1, activeSeconds: 70 * 60, distanceM: 4200))
    #expect(summary.previousWeekDistanceM == nil)
}

@Test func emptyWeekHasNoBestDay() {
    #expect(WeeklySummary.make(sessions: [], previousWeek: [], weekStart: week47, calendar: calendar).bestDay == nil)
}

@Test func sparklineScalesToMax() {
    #expect(WeeklySummary.sparkline([0, 60, 120, 0, 0, 0, 0]) == "·▄█····")
    #expect(WeeklySummary.sparkline([0, 0, 0, 0, 0, 0, 0]) == "·······")
}

@Test func stepsNilWhenNoSessionHasSteps() {
    let summary = WeeklySummary.make(sessions: [walk(week47, minutes: 30, steps: nil)], previousWeek: [],
                                     weekStart: week47, calendar: calendar)
    #expect(summary.steps == nil)
}

@Test func fingerprintChangesWhenASessionIsAdded() {
    let one = [walk(date(2026, 11, 16, 9), minutes: 30)]
    let two = one + [walk(date(2026, 11, 18, 9), minutes: 30)]
    let a = WeeklySummary.make(sessions: one, previousWeek: [], weekStart: week47, calendar: calendar)
    let a2 = WeeklySummary.make(sessions: one, previousWeek: [], weekStart: week47, calendar: calendar)
    let b = WeeklySummary.make(sessions: two, previousWeek: [], weekStart: week47, calendar: calendar)
    #expect(a.fingerprint == a2.fingerprint)
    #expect(a.fingerprint != b.fingerprint)
}
