import Foundation

public enum PadURLError: Error, Equatable {
    case unknownCommand(String)
    case unreadableSpeed(String)
}

/// `tapismarche://demarrer | arreter | vitesse/<km/h> | plus-vite | moins-vite`
public enum PadURLCommand: Equatable, Sendable {
    case start, stop, speed(Double), faster, slower

    static let scheme = "tapismarche"
    static let nudgeKmh = 0.5

    public init(url: URL) throws(PadURLError) {
        guard url.scheme == Self.scheme, let host = url.host() else {
            throw .unknownCommand(url.absoluteString)
        }
        switch host {
        case "demarrer": self = .start
        case "arreter": self = .stop
        case "plus-vite": self = .faster
        case "moins-vite": self = .slower
        case "vitesse":
            let raw = url.lastPathComponent
            guard let kmh = Double(raw.replacingOccurrences(of: ",", with: ".")), kmh.isFinite else {
                throw .unreadableSpeed(raw)
            }
            self = .speed(kmh)
        default:
            throw .unknownCommand(host)
        }
    }

    /// Nil for speed changes while the belt is stopped: a Set Target Speed on a stopped pad might start it.
    public func padCommand(currentSpeedKmh: Double, range: SpeedRange) -> PadCommand? {
        let target: Double
        switch self {
        case .start: return .start
        case .stop: return .stop
        case .speed(let kmh): target = kmh
        case .faster: target = currentSpeedKmh + Self.nudgeKmh
        case .slower: target = currentSpeedKmh - Self.nudgeKmh
        }
        return currentSpeedKmh > 0 ? .setSpeed(range.clamp(target)) : nil
    }
}
