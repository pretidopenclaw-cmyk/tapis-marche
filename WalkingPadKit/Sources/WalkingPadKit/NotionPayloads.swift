import Foundation

/// Pure builders for Notion request bodies and the French copy they carry. No network here.
public enum NotionPayloads {
    static let databaseTitle = "Marches"
    static let recapsPageTitle = "Récaps hebdo"

    static func databaseBody(parentPageId: String) -> [String: Any] {
        let number: [String: Any] = ["number": ["format": "number"]]
        let date: [String: Any] = ["date": [String: Any]()]
        return [
            "parent": ["type": "page_id", "page_id": parentPageId],
            "title": richText(databaseTitle),
            "initial_data_source": ["properties": [
                "Séance": ["title": [String: Any]()],
                "Date": date, "Début": date, "Fin": date,
                "Durée (min)": number, "Distance (km)": number, "Pas": number,
                "Vitesse moy. (km/h)": number, "Vitesse max (km/h)": number, "kcal": number,
                "ID": ["rich_text": [String: Any]()],
            ]],
        ]
    }

    static func childPageBody(parentPageId: String, title: String, children: [[String: Any]] = []) -> [String: Any] {
        [
            "parent": ["type": "page_id", "page_id": parentPageId],
            "properties": ["title": ["title": richText(title)]],
            "children": children,
        ]
    }

    static func sessionPageBody(_ session: WalkSession, dataSourceId: String, calendar: Calendar) -> [String: Any] {
        let t = session.totals
        var properties: [String: Any] = [
            "Séance": ["title": richText(sessionTitle(session.start, calendar: calendar))],
            "Date": ["date": ["start": day(session.start, calendar: calendar)]],
            "Début": ["date": ["start": timestamp(session.start, calendar: calendar)]],
            "Fin": ["date": ["start": timestamp(session.end, calendar: calendar)]],
            "Durée (min)": ["number": (Double(t.activeSeconds) / 60).rounded()],
            "Distance (km)": ["number": round(Double(t.distanceM) / 1000, decimals: 2)],
            "Vitesse moy. (km/h)": ["number": round(t.avgSpeedKmh, decimals: 1)],
            "Vitesse max (km/h)": ["number": round(t.maxSpeedKmh, decimals: 1)],
            "kcal": ["number": t.energyKcal],
            "ID": ["rich_text": richText(session.id.uuidString)],
        ]
        if let steps = t.steps { properties["Pas"] = ["number": steps] }
        return ["parent": ["type": "data_source_id", "data_source_id": dataSourceId], "properties": properties]
    }

    static func recapPageBody(_ summary: WeeklySummary, recapsPageId: String) -> [String: Any] {
        let paragraphs = recapLines(summary).map(paragraph)
        let chart = code("\(WeeklySummary.sparkline(summary.perDayActiveSeconds))  (lun → dim)")
        return childPageBody(parentPageId: recapsPageId, title: summary.title,
                             children: [paragraphs.first, chart].compactMap { $0 } + paragraphs.dropFirst())
    }

    /// The recap's text lines, e.g. "5 séances · 7 h 40 de marche · 31,2 km · 41 380 pas".
    static func recapLines(_ s: WeeklySummary) -> [String] {
        var headline = ["\(s.sessionCount) séance\(s.sessionCount > 1 ? "s" : "")",
                        "\(duration(s.activeSeconds)) de marche", km(s.distanceM)]
        if let steps = s.steps { headline.append("\(thousands(steps)) pas") }
        var lines = [headline.joined(separator: " · ")]
        if let best = s.bestDay {
            lines.append("Meilleur jour : \(weekdays[best.weekdayIndex]) (\(duration(best.activeSeconds)), \(km(best.distanceM)))")
        }
        if let previous = s.previousWeekDistanceM {
            let delta = s.distanceM - previous
            lines.append("vs semaine précédente : \(delta >= 0 ? "+" : "-")\(km(abs(delta)))")
        }
        return lines
    }

    // MARK: - French formatting

    private static let weekdays = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60
        return hours == 0 ? "\(minutes) min" : "\(hours) h \(String(format: "%02d", minutes))"
    }

    static func km(_ meters: Int) -> String {
        String(format: "%.1f km", Double(meters) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func thousands(_ n: Int) -> String {
        let digits = Array(String(n))
        return digits.enumerated().map { index, digit in
            (index > 0 && (digits.count - index) % 3 == 0 ? " " : "") + String(digit)
        }.joined()
    }

    private static func sessionTitle(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE d MMM · HH:mm", calendar).string(from: date)
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        formatter("yyyy-MM-dd", calendar).string(from: date)
    }

    private static func timestamp(_ date: Date, calendar: Calendar) -> String {
        let iso = ISO8601DateFormatter()
        iso.timeZone = calendar.timeZone
        return iso.string(from: date)
    }

    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    private static func round(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10, Double(decimals))
        return (value * factor).rounded() / factor
    }

    // MARK: - Blocks

    private static func richText(_ content: String) -> [[String: Any]] {
        [["type": "text", "text": ["content": content]]]
    }

    private static func paragraph(_ content: String) -> [String: Any] {
        ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(content)]]
    }

    private static func code(_ content: String) -> [String: Any] {
        ["object": "block", "type": "code", "code": ["rich_text": richText(content), "language": "plain text"]]
    }
}
