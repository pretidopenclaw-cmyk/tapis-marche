import Foundation

/// The French number/date copy shared by the menu bar and Notion ("7 h 40", "31,2 km", "41 380").
public enum FrenchFormat {
    static let weekdays = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

    public static func duration(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = seconds % 3600 / 60
        return hours == 0 ? "\(minutes) min" : "\(hours) h \(String(format: "%02d", minutes))"
    }

    /// One decimal, rounded half up: 1250 m → "1,3 km".
    public static func km(_ meters: Int) -> String {
        decimal((Double(meters) / 100).rounded() / 10) + " km"
    }

    public static func speed(_ kmh: Double) -> String {
        decimal((kmh * 10).rounded() / 10) + " km/h"
    }

    public static func thousands(_ n: Int) -> String {
        let digits = Array(String(n))
        return digits.enumerated().map { index, digit in
            (index > 0 && (digits.count - index) % 3 == 0 ? " " : "") + String(digit)
        }.joined()
    }

    /// "lun. 16 nov. · 14:05"
    public static func sessionStart(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE d MMM · HH:mm", calendar).string(from: date)
    }

    static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = calendar.locale
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }
}
