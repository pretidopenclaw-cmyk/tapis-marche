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

    public func padCommand(currentSpeedKmh: Double, range: SpeedRange) -> PadCommand {
        switch self {
        case .start: .start
        case .stop: .stop
        case .speed(let kmh): .setSpeed(range.clamp(kmh))
        case .faster: .setSpeed(range.clamp(currentSpeedKmh + Self.nudgeKmh))
        case .slower: .setSpeed(range.clamp(currentSpeedKmh - Self.nudgeKmh))
        }
    }
}
