import Foundation

public struct SessionTotals: Equatable, Sendable, Codable {
    public var activeSeconds: Int
    public var distanceM: Int
    public var steps: Int?
    public var energyKcal: Int
    public var avgSpeedKmh: Double
    public var maxSpeedKmh: Double

    public init(activeSeconds: Int, distanceM: Int, steps: Int?, energyKcal: Int,
                avgSpeedKmh: Double, maxSpeedKmh: Double) {
        self.activeSeconds = activeSeconds
        self.distanceM = distanceM
        self.steps = steps
        self.energyKcal = energyKcal
        self.avgSpeedKmh = avgSpeedKmh
        self.maxSpeedKmh = maxSpeedKmh
    }
}

/// One walk on the pad: from the first moving sample to the last moving sample.
public struct WalkSession: Equatable, Sendable, Identifiable, Codable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var totals: SessionTotals

    public init(id: UUID = UUID(), start: Date, end: Date, totals: SessionTotals) {
        self.id = id
        self.start = start
        self.end = end
        self.totals = totals
    }
}
