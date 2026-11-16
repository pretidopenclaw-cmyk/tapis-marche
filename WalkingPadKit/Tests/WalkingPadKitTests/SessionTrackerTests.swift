import Foundation
import Testing
@testable import WalkingPadKit

private let t0 = Date(timeIntervalSince1970: 1_794_000_000)

/// Builds a 1 Hz timeline from (seconds, speed) segments. Moving seconds add 1 m and 2 steps.
private func timeline(_ segments: [(seconds: Int, speed: Double)], from start: Date = t0,
                      withSteps: Bool = true) -> [TreadmillSample] {
    var samples: [TreadmillSample] = []
    var distance = 0
    for (seconds, speed) in segments {
        for _ in 0..<seconds {
            let t = start.addingTimeInterval(TimeInterval(samples.count))
            samples.append(TreadmillSample(timestamp: t, speedKmh: speed, distanceM: distance,
                                           elapsedS: nil, energyKcal: 0, steps: withSteps ? distance * 2 : nil))
            if speed > 0 { distance += 1 }
        }
    }
    return samples
}

private func feed(_ tracker: inout SessionTracker, _ samples: [TreadmillSample]) -> [WalkSession] {
    samples.compactMap { tracker.ingest($0) }
}

private func sample(at second: Int, speed: Double, distance: Int) -> TreadmillSample {
    TreadmillSample(timestamp: t0.addingTimeInterval(TimeInterval(second)), speedKmh: speed, distanceM: distance)
}

@Test func opensOnFirstMovingSample() {
    var tracker = SessionTracker()
    _ = feed(&tracker, timeline([(2, 0), (1, 3.5)]))
    #expect(tracker.openSession?.start == t0.addingTimeInterval(2))
}

@Test func shortPauseStaysInSameSession() {
    var tracker = SessionTracker()
    let closed = feed(&tracker, timeline([(300, 3.6), (120, 0), (300, 3.6), (181, 0)]))
    #expect(closed.count == 1)
    #expect(closed.first?.totals.activeSeconds == 600)
    #expect(closed.first?.totals.distanceM == 600)
    #expect(closed.first?.totals.steps == 1200)
}

@Test func threeMinutesIdleClosesAtLastMovingSample() {
    var tracker = SessionTracker()
    let samples = timeline([(300, 3.6), (180, 0)])
    let closedBeforeLast = feed(&tracker, Array(samples.dropLast()))
    #expect(closedBeforeLast.isEmpty)
    let session = tracker.ingest(samples.last!)
    #expect(session?.start == t0)
    #expect(session?.end == t0.addingTimeInterval(299))
    #expect(tracker.openSession == nil)
}

@Test func counterResetIsAddedNotSubtracted() {
    var tracker = SessionTracker()
    let distances = [0, 200, 500, 0, 100]
    _ = feed(&tracker, distances.enumerated().map { sample(at: $0.offset, speed: 3.6, distance: $0.element) })
    let session = tracker.tick(now: t0.addingTimeInterval(4 + 180))
    #expect(session?.totals.distanceM == 600)
}

@Test func gapOverTenSecondsIsNotCredited() {
    var tracker = SessionTracker()
    let before = (0..<200).map { sample(at: $0, speed: 3.6, distance: $0) }      // credits 199 m
    let after = (0..<10).map { sample(at: 229 + $0, speed: 3.6, distance: 1000 + $0) } // 30 s gap, then 9 m
    _ = feed(&tracker, before + after)
    let session = tracker.tick(now: t0.addingTimeInterval(238 + 180))
    #expect(session?.totals.distanceM == 208)
    #expect(session?.totals.activeSeconds == 208)
}

@Test func tinySessionIsDiscarded() {
    var tracker = SessionTracker()
    let closed = feed(&tracker, timeline([(50, 3.0), (180, 0)]))
    #expect(closed.isEmpty)
    #expect(tracker.openSession == nil)
}

@Test func zeroOnlyFramesNeverOpenASession() {
    var tracker = SessionTracker()
    let closed = feed(&tracker, timeline([(4 * 3600, 0)]))
    #expect(closed.isEmpty)
    #expect(tracker.openSession == nil)
    #expect(tracker.tick(now: t0.addingTimeInterval(5 * 3600)) == nil)
}

@Test func tickAfterLongSleepClosesAtLastMovingSample() {
    var tracker = SessionTracker()
    _ = feed(&tracker, timeline([(600, 3.6)]))
    #expect(tracker.tick(now: t0.addingTimeInterval(599 + 60)) == nil)
    let session = tracker.tick(now: t0.addingTimeInterval(599 + 7200))
    #expect(session?.end == t0.addingTimeInterval(599))
    #expect(session?.totals.activeSeconds == 599)
    #expect(session?.totals.maxSpeedKmh == 3.6)
    #expect(session.map { abs($0.totals.avgSpeedKmh - 3.6) < 0.001 } == true)
}

@Test func stepsNilWhenPadNeverReportsThem() {
    var tracker = SessionTracker()
    let closed = feed(&tracker, timeline([(300, 3.6), (180, 0)], withSteps: false))
    #expect(closed.count == 1)
    #expect(closed.first?.totals.steps == nil)
}
