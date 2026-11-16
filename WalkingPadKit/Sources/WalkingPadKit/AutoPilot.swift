import Foundation

public struct AutoPilotSettings: Equatable, Sendable, Codable {
    public var preferredSpeedEnabled: Bool
    public var preferredSpeedKmh: Double
    public var autoStopEnabled: Bool

    public init(preferredSpeedEnabled: Bool = true, preferredSpeedKmh: Double = 2.0, autoStopEnabled: Bool = true) {
        self.preferredSpeedEnabled = preferredSpeedEnabled
        self.preferredSpeedKmh = preferredSpeedKmh
        self.autoStopEnabled = autoStopEnabled
    }
}

/// Watches the belt and decides two things on David's behalf (spec « Pilotage du tapis »):
/// switch to his preferred speed once after each start, and stop the belt when nobody walks on it.
/// It never starts the belt.
public struct AutoPilot: Sendable {
    public var settings: AutoPilotSettings
    public private(set) var lastAutoStop: Date?

    private let settleDelay: TimeInterval = 2
    private let startGrace: TimeInterval = 15
    private let noStepTimeout: TimeInterval = 10
    private let reconnectWindow: TimeInterval = 30
    private let speedTolerance = 0.05

    /// Speed of the previous frame; nil right after a (re)connection, whose first frame is never a start.
    private var lastSpeed: Double?
    private var startedAt: Date?
    private var speedApplied = false
    private var graceFrom: Date?
    private var lastStepAt: Date?
    private var lastSteps: Int?
    private var stopSent = false

    public init(settings: AutoPilotSettings) {
        self.settings = settings
    }

    public mutating func connected(at date: Date) {
        lastSpeed = nil
        lastSteps = nil
        graceFrom = date
        let startStillPending = startedAt.map { !speedApplied && date.timeIntervalSince($0) < reconnectWindow } ?? false
        if !startStillPending { startedAt = nil }
    }

    public mutating func observe(_ sample: TreadmillSample) -> [PadCommand] {
        defer { lastSpeed = sample.speedKmh }
        guard sample.speedKmh > 0 else {
            beltStopped(sample)
            return []
        }
        if lastSpeed == 0 { beltStarted(at: sample.timestamp) }
        trackSteps(sample)
        return [preferredSpeedCommand(sample), stopCommand(sample)].compactMap { $0 }
    }

    private mutating func beltStopped(_ sample: TreadmillSample) {
        startedAt = nil
        speedApplied = false
        stopSent = false
        lastSteps = sample.steps
    }

    private mutating func beltStarted(at date: Date) {
        startedAt = date
        speedApplied = false
        stopSent = false
        graceFrom = date
        lastStepAt = date
    }

    private mutating func trackSteps(_ sample: TreadmillSample) {
        if graceFrom == nil { graceFrom = sample.timestamp }
        if lastStepAt == nil { lastStepAt = sample.timestamp }
        guard let steps = sample.steps else { return }
        if let previous = lastSteps, steps != previous, steps > 0 { lastStepAt = sample.timestamp }
        lastSteps = steps
    }

    private mutating func preferredSpeedCommand(_ sample: TreadmillSample) -> PadCommand? {
        guard settings.preferredSpeedEnabled, !speedApplied, let startedAt,
              sample.timestamp.timeIntervalSince(startedAt) >= settleDelay else { return nil }
        speedApplied = true
        let preferred = settings.preferredSpeedKmh
        return abs(sample.speedKmh - preferred) >= speedTolerance ? .setSpeed(preferred) : nil
    }

    private mutating func stopCommand(_ sample: TreadmillSample) -> PadCommand? {
        guard settings.autoStopEnabled, !stopSent, sample.steps != nil,
              let graceFrom, let lastStepAt,
              sample.timestamp.timeIntervalSince(graceFrom) >= startGrace,
              sample.timestamp.timeIntervalSince(lastStepAt) >= noStepTimeout else { return nil }
        stopSent = true
        lastAutoStop = sample.timestamp
        return .stop
    }
}
