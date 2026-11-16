import Foundation
import Testing
@testable import WalkingPadKit

private let t0 = Date(timeIntervalSince1970: 1_794_000_000)

private func frames(_ segments: [(seconds: Int, speed: Double)], from offset: Int = 0) -> [TreadmillSample] {
    var out: [TreadmillSample] = []
    var distance = 0
    for (seconds, speed) in segments {
        for _ in 0..<seconds {
            out.append(TreadmillSample(timestamp: t0.addingTimeInterval(TimeInterval(offset + out.count)),
                                       speedKmh: speed, distanceM: distance, energyKcal: 0, steps: distance * 2))
            if speed > 0 { distance += 1 }
        }
    }
    return out
}

@Test func standbyFramesAreNotStored() throws {
    let store = try SessionStore(path: nil)
    var journal = try WalkJournal(store: store, now: t0)
    for frame in frames([(3600, 0)]) { _ = try journal.ingest(frame) }
    #expect(try store.samples(after: nil).isEmpty)
}

@Test func walkIsStoredFromFirstStepUntilItCloses() throws {
    let store = try SessionStore(path: nil)
    var journal = try WalkJournal(store: store, now: t0)
    var closed: [WalkSession] = []
    for frame in frames([(60, 0), (300, 3.6), (180, 0), (600, 0)]) {
        if let session = try journal.ingest(frame) { closed.append(session) }
    }
    #expect(closed.count == 1)
    #expect(try store.sessions(in: DateInterval(start: t0, duration: 3600)) == closed)
    #expect(try store.samples(after: nil).count == 480)   // 300 walking + 180 trailing idle, no standby
}

@Test func walkInterruptedByCrashIsRecoveredOnRelaunch() throws {
    let store = try SessionStore(path: nil)
    var journal = try WalkJournal(store: store, now: t0)
    for frame in frames([(60, 0), (300, 3.6)]) { _ = try journal.ingest(frame) }
    _ = try WalkJournal(store: store, now: t0.addingTimeInterval(359 + 240))   // relaunch after the crash
    let saved = try store.sessions(in: DateInterval(start: t0, duration: 3600))
    #expect(saved.count == 1)
    #expect(saved.first?.totals.distanceM == 299)
}

@Test func onDiskJournalUsesWAL() throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).sqlite").path
    defer { try? FileManager.default.removeItem(atPath: path) }
    #expect(try SessionStore(path: path).journalMode() == "wal")
}
