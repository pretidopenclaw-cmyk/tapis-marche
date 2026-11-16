import Foundation

/// One decoded reading from the treadmill, as received at `timestamp`.
/// Counters (`distanceM`, `elapsedS`, `energyKcal`, `steps`) are the pad's own cumulative values;
/// `nil` means the pad did not report that field in this frame.
public struct TreadmillSample: Equatable, Sendable, Codable {
    public var timestamp: Date
    public var speedKmh: Double
    public var distanceM: Int?
    public var elapsedS: Int?
    public var energyKcal: Int?
    public var steps: Int?

    public init(timestamp: Date, speedKmh: Double, distanceM: Int? = nil, elapsedS: Int? = nil,
                energyKcal: Int? = nil, steps: Int? = nil) {
        self.timestamp = timestamp
        self.speedKmh = speedKmh
        self.distanceM = distanceM
        self.elapsedS = elapsedS
        self.energyKcal = energyKcal
        self.steps = steps
    }
}
