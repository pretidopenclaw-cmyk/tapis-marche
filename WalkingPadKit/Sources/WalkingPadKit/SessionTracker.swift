import Foundation

/// Turns a stream of treadmill samples into walk sessions (see spec « Règles de séance »).
public struct SessionTracker: Sendable {
    private let idleTimeout: TimeInterval
    private let gapThreshold: TimeInterval
    private let minActiveSeconds: Int
    private let minDistanceM: Int

    private var last: TreadmillSample?
    private var current: Accumulator?

    public init(idleTimeout: TimeInterval = 180, gapThreshold: TimeInterval = 10,
                minActiveSeconds: Int = 120, minDistanceM: Int = 100) {
        self.idleTimeout = idleTimeout
        self.gapThreshold = gapThreshold
        self.minActiveSeconds = minActiveSeconds
        self.minDistanceM = minDistanceM
    }

    /// Live view of the session in progress, if any.
    public var openSession: WalkSession? { current?.session }

    /// Feeds one sample; returns a session it just closed, if that session is worth keeping.
    public mutating func ingest(_ sample: TreadmillSample) -> WalkSession? {
        var closed: WalkSession?
        if let last, sample.timestamp.timeIntervalSince(last.timestamp) >= idleTimeout {
            closed = close()
        }
        let interval = last.map { sample.timestamp.timeIntervalSince($0.timestamp) }
        // A negative interval (clock moved back) is a gap too: never credit time or distance across it.
        let contiguous = interval.map { (0...gapThreshold).contains($0) } ?? false
        if current == nil, sample.speedKmh > 0 {
            current = Accumulator(start: sample.timestamp)
        }
        if let previous = last, contiguous {
            current?.credit(from: previous, to: sample)
        }
        current?.observe(sample)
        last = sample
        if let current, sample.speedKmh == 0,
           sample.timestamp.timeIntervalSince(current.lastMovingAt) >= idleTimeout {
            closed = close()
        }
        return closed
    }

    /// Closes the open session when no frame arrived for `idleTimeout` (pad gone, Mac asleep).
    public mutating func tick(now: Date) -> WalkSession? {
        guard let last, now.timeIntervalSince(last.timestamp) >= idleTimeout else { return nil }
        return close()
    }

    private mutating func close() -> WalkSession? {
        defer { current = nil }
        guard let session = current?.session else { return nil }
        let tooSmall = session.totals.activeSeconds < minActiveSeconds && session.totals.distanceM < minDistanceM
        return tooSmall ? nil : session
    }
}

/// Running totals of the session in progress.
private struct Accumulator: Sendable {
    let id = UUID()
    let start: Date
    var lastMovingAt: Date
    var activeSeconds = 0.0
    var distanceM = 0
    var steps: Int?
    var energyKcal = 0
    var maxSpeedKmh = 0.0

    init(start: Date) {
        self.start = start
        self.lastMovingAt = start
    }

    mutating func credit(from previous: TreadmillSample, to sample: TreadmillSample) {
        if previous.speedKmh > 0 {
            activeSeconds += sample.timestamp.timeIntervalSince(previous.timestamp)
        }
        distanceM += Self.increment(previous.distanceM, sample.distanceM) ?? 0
        energyKcal += Self.increment(previous.energyKcal, sample.energyKcal) ?? 0
        if let stepIncrement = Self.increment(previous.steps, sample.steps) {
            steps = (steps ?? 0) + stepIncrement
        }
    }

    mutating func observe(_ sample: TreadmillSample) {
        if sample.steps != nil, steps == nil { steps = 0 }
        guard sample.speedKmh > 0 else { return }
        lastMovingAt = sample.timestamp
        maxSpeedKmh = max(maxSpeedKmh, sample.speedKmh)
    }

    /// Pad counters only grow, except when they reset to zero at a new belt start.
    static func increment(_ previous: Int?, _ current: Int?) -> Int? {
        guard let previous, let current else { return nil }
        return current >= previous ? current - previous : current
    }

    var session: WalkSession {
        let active = Int(activeSeconds.rounded())
        let avg = active > 0 ? Double(distanceM) / Double(active) * 3.6 : 0
        return WalkSession(id: id, start: start, end: lastMovingAt,
                           totals: SessionTotals(activeSeconds: active, distanceM: distanceM, steps: steps,
                                                 energyKcal: energyKcal, avgSpeedKmh: avg,
                                                 maxSpeedKmh: maxSpeedKmh))
    }
}
