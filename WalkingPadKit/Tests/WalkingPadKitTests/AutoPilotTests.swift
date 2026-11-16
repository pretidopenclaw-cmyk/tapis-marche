import Foundation
import Testing
@testable import WalkingPadKit

private let t0 = Date(timeIntervalSince1970: 1_794_000_000)

private func at(_ second: Int) -> Date { t0.addingTimeInterval(TimeInterval(second)) }

/// Feeds 1 Hz frames for seconds in `range`; returns (second, command) pairs.
@discardableResult
private func run(_ pilot: inout AutoPilot, _ range: ClosedRange<Int>,
                 speed: (Int) -> Double, steps: (Int) -> Int?) -> [(Int, PadCommand)] {
    range.flatMap { s in
        pilot.observe(TreadmillSample(timestamp: at(s), speedKmh: speed(s), steps: steps(s))).map { (s, $0) }
    }
}

private func stops(_ commands: [(Int, PadCommand)]) -> [Int] { commands.filter { $0.1 == .stop }.map(\.0) }

/// Idle until 9, belt started by the remote at 10 (1.0 km/h), David walking (1 step/s) until `walkUntil`.
private func remoteStart(_ pilot: inout AutoPilot, through end: Int, walkUntil: Int = .max,
                         speed: @escaping (Int) -> Double = { _ in 1.0 }) -> [(Int, PadCommand)] {
    run(&pilot, 0...9, speed: { _ in 0 }, steps: { _ in 0 })
        + run(&pilot, 10...end, speed: speed, steps: { min($0, walkUntil) - 10 })
}

@Test func remoteStartGetsPreferredSpeedAfterSettle() {
    var pilot = AutoPilot(settings: .init())
    let commands = remoteStart(&pilot, through: 40)
    #expect(commands.map(\.0) == [12])
    #expect(commands.map(\.1) == [.setSpeed(2.0)])
}

@Test func noOverrideAfterManualChange() {
    var pilot = AutoPilot(settings: .init())
    let commands = remoteStart(&pilot, through: 90, speed: { $0 < 13 ? 1.0 : ($0 < 21 ? 2.0 : 3.5) })
    #expect(commands.map(\.1) == [.setSpeed(2.0)])
}

@Test func alreadyAtPreferredSpeedSendsNothing() {
    var pilot = AutoPilot(settings: .init())
    #expect(remoteStart(&pilot, through: 40, speed: { _ in 2.0 }).isEmpty)
}

@Test func preferredSpeedDisabledSendsNothing() {
    var pilot = AutoPilot(settings: .init(preferredSpeedEnabled: false))
    #expect(remoteStart(&pilot, through: 40).isEmpty)
}

@Test func connectingToRunningBeltIsNotAStart() {
    var pilot = AutoPilot(settings: .init())
    pilot.connected(at: at(0))
    let commands = run(&pilot, 1...60, speed: { _ in 2.5 }, steps: { $0 })
    #expect(commands.isEmpty)
}

@Test func reconnectRightAfterStartStillAppliesSpeed() {
    var pilot = AutoPilot(settings: .init())
    _ = remoteStart(&pilot, through: 11)                  // start seen at 10, dropped before settle
    pilot.connected(at: at(15))
    let commands = run(&pilot, 16...30, speed: { _ in 1.0 }, steps: { $0 })
    #expect(commands.map(\.1) == [.setSpeed(2.0)])
}

@Test func reconnectLongAfterStartIsNotAStart() {
    var pilot = AutoPilot(settings: .init())
    _ = remoteStart(&pilot, through: 11)
    pilot.connected(at: at(50))
    #expect(run(&pilot, 51...70, speed: { _ in 1.0 }, steps: { $0 }).isEmpty)
}

@Test func stepOffStopsAfterTenSecondsWithoutSteps() {
    var pilot = AutoPilot(settings: .init())
    let commands = remoteStart(&pilot, through: 120, walkUntil: 60)
    #expect(stops(commands) == [70])
    #expect(pilot.lastAutoStop == at(70))
}

@Test func noStopDuringStartGrace() {
    var pilot = AutoPilot(settings: .init())
    let commands = remoteStart(&pilot, through: 24, walkUntil: 10)
    #expect(stops(commands).isEmpty)
}

@Test func emptyBeltAfterStartStopsWithinTwentyFiveSeconds() {
    var pilot = AutoPilot(settings: .init())
    let first = stops(remoteStart(&pilot, through: 60, walkUntil: 10)).first
    #expect(first == 25)
    #expect(first.map { $0 - 10 <= 25 } == true)
}

@Test func slowWalkingNeverStops() {
    var pilot = AutoPilot(settings: .init())
    _ = run(&pilot, 0...9, speed: { _ in 0 }, steps: { _ in 0 })
    let commands = run(&pilot, 10...310, speed: { _ in 1.0 }, steps: { ($0 - 10) / 4 })
    #expect(stops(commands).isEmpty)
}

@Test func graceRestartsOnReconnect() {
    var pilot = AutoPilot(settings: .init())
    _ = remoteStart(&pilot, through: 44, walkUntil: 40)
    pilot.connected(at: at(45))
    let commands = run(&pilot, 46...90, speed: { _ in 2.0 }, steps: { _ in 30 })
    #expect(stops(commands) == [60])
}

@Test func autoStopDisabledOrNoStepsNeverStops() {
    var disabled = AutoPilot(settings: .init(autoStopEnabled: false))
    #expect(stops(remoteStart(&disabled, through: 120, walkUntil: 10)).isEmpty)
    var noSteps = AutoPilot(settings: .init())
    _ = run(&noSteps, 0...9, speed: { _ in 0 }, steps: { _ in nil })
    #expect(stops(run(&noSteps, 10...120, speed: { _ in 1.0 }, steps: { _ in nil })).isEmpty)
}

@Test func neverEmitsStart() {
    var pilot = AutoPilot(settings: .init())
    var commands = remoteStart(&pilot, through: 100, walkUntil: 50)
    commands += run(&pilot, 101...120, speed: { _ in 0 }, steps: { _ in 0 })
    pilot.connected(at: at(121))
    commands += run(&pilot, 122...200, speed: { $0 % 7 == 0 ? 0 : 1.5 }, steps: { $0 % 3 == 0 ? nil : $0 })
    #expect(!commands.contains { $0.1 == .start })
}
