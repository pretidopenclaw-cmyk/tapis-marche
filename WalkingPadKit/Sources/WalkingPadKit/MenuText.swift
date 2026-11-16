import Foundation

/// What the pad connection looks like from the menu bar.
public enum PadPresence: Equatable, Sendable {
    case absent
    case connecting
    case connected(speedKmh: Double)
    case released(until: Date)
}

/// Today's and this week's totals, closed sessions plus the one in progress.
public struct Dashboard: Equatable, Sendable {
    public var todayActiveSeconds: Int
    public var todayDistanceM: Int
    public var todaySteps: Int?
    public var weekActiveSeconds: Int
    public var weekDistanceM: Int

    public static let empty = Dashboard(todayActiveSeconds: 0, todayDistanceM: 0, todaySteps: nil,
                                        weekActiveSeconds: 0, weekDistanceM: 0)

    public static func make(closed: [WalkSession], open: WalkSession?, now: Date, calendar: Calendar) -> Dashboard {
        let all = closed + [open].compactMap { $0 }
        let week = all.filter { calendar.isDate($0.start, equalTo: now, toGranularity: .weekOfYear) }
        let today = week.filter { calendar.isDate($0.start, inSameDayAs: now) }
        let steps = today.compactMap(\.totals.steps)
        return Dashboard(todayActiveSeconds: today.reduce(0) { $0 + $1.totals.activeSeconds },
                         todayDistanceM: today.reduce(0) { $0 + $1.totals.distanceM },
                         todaySteps: steps.isEmpty ? nil : steps.reduce(0, +),
                         weekActiveSeconds: week.reduce(0) { $0 + $1.totals.activeSeconds },
                         weekDistanceM: week.reduce(0) { $0 + $1.totals.distanceM })
    }
}

/// The menu bar copy from the spec mockup.
public enum MenuText {
    public static func title(_ presence: PadPresence, _ d: Dashboard) -> String {
        guard case .connected(let speed) = presence else { return "🚶̸" }
        let today = d.todaySteps.map { "\(FrenchFormat.thousands($0)) pas" } ?? FrenchFormat.km(d.todayDistanceM)
        return speed > 0 ? "🚶 \(FrenchFormat.speed(speed)) · \(today)" : "🚶 · \(today)"
    }

    public static func today(_ d: Dashboard) -> String {
        var parts = [FrenchFormat.duration(d.todayActiveSeconds), FrenchFormat.km(d.todayDistanceM)]
        if let steps = d.todaySteps { parts.append("\(FrenchFormat.thousands(steps)) pas") }
        return "Aujourd'hui : " + parts.joined(separator: " · ")
    }

    public static func week(_ d: Dashboard) -> String {
        "Cette semaine : \(FrenchFormat.duration(d.weekActiveSeconds)) · \(FrenchFormat.km(d.weekDistanceM))"
    }

    public static func notion(_ status: SyncStatus?, configured: Bool) -> String {
        guard configured else { return "Notion : non configuré" }
        switch status?.pending ?? 0 {
        case 0: return "Notion : à jour"
        case 1: return "Notion : 1 séance en attente"
        case let n: return "Notion : \(n) séances en attente"
        }
    }

    public static func session(_ s: WalkSession, calendar: Calendar) -> String {
        "\(FrenchFormat.sessionStart(s.start, calendar: calendar)) — "
            + "\(FrenchFormat.duration(s.totals.activeSeconds)) · \(FrenchFormat.km(s.totals.distanceM))"
    }
}
