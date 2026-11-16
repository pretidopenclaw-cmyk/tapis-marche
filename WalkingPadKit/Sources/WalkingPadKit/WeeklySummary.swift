import CryptoKit
import Foundation

/// What one ISO week of walking looked like (Monday 00:00 → Sunday 23:59, local time).
/// A session counts on the day and week it started.
public struct WeeklySummary: Equatable, Sendable {
    public struct BestDay: Equatable, Sendable {
        public var weekdayIndex: Int
        public var activeSeconds: Int
        public var distanceM: Int
    }

    public var weekStart: Date
    public var isoWeek: Int
    public var sessionCount: Int
    public var activeSeconds: Int
    public var distanceM: Int
    public var steps: Int?
    /// 7 entries, Monday first.
    public var perDayActiveSeconds: [Int]
    public var bestDay: BestDay?
    public var previousWeekDistanceM: Int?
    /// Stable across launches; changes iff the sessions shown (or the comparison) change.
    public var fingerprint: String
    public var title: String

    /// ISO 8601 weeks, French month names, local time zone.
    public static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "fr_CH")
        calendar.timeZone = .current
        return calendar
    }

    public static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)!.start
    }

    public static func make(sessions: [WalkSession], previousWeek: [WalkSession], weekStart: Date,
                            calendar: Calendar) -> WeeklySummary {
        let days = dailyTotals(sessions, weekStart: weekStart, calendar: calendar)
        let reportedSteps = sessions.compactMap(\.totals.steps)
        let previousDistance = previousWeek.isEmpty ? nil : previousWeek.reduce(0) { $0 + $1.totals.distanceM }
        return WeeklySummary(
            weekStart: weekStart,
            isoWeek: calendar.component(.weekOfYear, from: weekStart),
            sessionCount: sessions.count,
            activeSeconds: sessions.reduce(0) { $0 + $1.totals.activeSeconds },
            distanceM: sessions.reduce(0) { $0 + $1.totals.distanceM },
            steps: reportedSteps.isEmpty ? nil : reportedSteps.reduce(0, +),
            perDayActiveSeconds: days.map(\.activeSeconds),
            bestDay: days.filter { $0.activeSeconds > 0 }.max { $0.activeSeconds < $1.activeSeconds },
            previousWeekDistanceM: previousDistance,
            fingerprint: fingerprint(of: sessions, previousDistance: previousDistance),
            title: title(weekStart: weekStart, calendar: calendar)
        )
    }

    public static func sparkline(_ perDay: [Int]) -> String {
        let levels = Array("▁▂▃▄▅▆▇█")
        let peak = perDay.max() ?? 0
        return String(perDay.map { value in
            guard value > 0, peak > 0 else { return "·" }
            let level = Int((Double(value) / Double(peak) * 8).rounded(.up)) - 1
            return levels[min(max(level, 0), 7)]
        })
    }

    private static func dailyTotals(_ sessions: [WalkSession], weekStart: Date, calendar: Calendar) -> [BestDay] {
        var days = (0..<7).map { BestDay(weekdayIndex: $0, activeSeconds: 0, distanceM: 0) }
        for session in sessions {
            let day = calendar.dateComponents([.day], from: weekStart, to: calendar.startOfDay(for: session.start)).day ?? -1
            guard days.indices.contains(day) else { continue }
            days[day].activeSeconds += session.totals.activeSeconds
            days[day].distanceM += session.totals.distanceM
        }
        return days
    }

    /// "Semaine 47 — 16-22 nov." or, across months, "Semaine 49 — 30 nov.-6 déc."
    private static func title(weekStart: Date, calendar: Calendar) -> String {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
        let month = DateFormatter()
        month.calendar = calendar
        month.locale = calendar.locale
        month.timeZone = calendar.timeZone
        month.dateFormat = "MMM"
        let startDay = calendar.component(.day, from: weekStart)
        let endDay = calendar.component(.day, from: weekEnd)
        let sameMonth = calendar.isDate(weekStart, equalTo: weekEnd, toGranularity: .month)
        let range = sameMonth
            ? "\(startDay)-\(endDay) \(month.string(from: weekEnd))"
            : "\(startDay) \(month.string(from: weekStart))-\(endDay) \(month.string(from: weekEnd))"
        return "Semaine \(calendar.component(.weekOfYear, from: weekStart)) — \(range)"
    }

    private static func fingerprint(of sessions: [WalkSession], previousDistance: Int?) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let canonical = sessions.sorted { $0.id.uuidString < $1.id.uuidString }
        let payload = (try? encoder.encode(canonical)) ?? Data()
        let digest = SHA256.hash(data: payload + Data("\(previousDistance ?? -1)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
