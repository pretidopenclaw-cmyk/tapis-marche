import Foundation
import Testing
@testable import WalkingPadKit

private func reply(_ opcode: UInt8, _ result: ControlResult) -> ControlResponse {
    ControlResponse(opcode: opcode, result: result)
}

@Test func sendsOneCommandAtATimeInOrder() {
    var queue = ControlQueue()
    queue.enqueue(.start)
    queue.enqueue(.setSpeed(2.0))
    let sent1 = queue.next()
    #expect(sent1 == .start)
    let sent2 = queue.next()
    #expect(sent2 == nil)                       // waiting for the answer to start
    let accepted = queue.receive(reply(0x07, .success), range: .z1)
    #expect(accepted)
    let sent3 = queue.next()
    #expect(sent3 == .setSpeed(2.0))
}

@Test func takeControlGoesFirst() {
    var queue = ControlQueue()
    queue.enqueue(.start)
    queue.takeControlFirst()
    let sent1 = queue.next()
    #expect(sent1 == .requestControl)
}

@Test func deniedCommandIsRetriedOnceAfterRequestingControl() {
    var queue = ControlQueue()
    queue.enqueue(.setSpeed(2.0))
    _ = queue.next()
    _ = queue.receive(reply(0x02, .controlNotPermitted), range: .z1)
    let sent1 = queue.next()
    #expect(sent1 == .requestControl)
    _ = queue.receive(reply(0x00, .success), range: .z1)
    let sent2 = queue.next()
    #expect(sent2 == .setSpeed(2.0))
    _ = queue.receive(reply(0x02, .controlNotPermitted), range: .z1)   // denied again
    let sent3 = queue.next()
    #expect(sent3 == nil)                                        // dropped, no endless replay
}

@Test func lateAnswerToAnotherCommandIsIgnored() {
    var queue = ControlQueue()
    queue.enqueue(.stop)
    _ = queue.next()
    let late = queue.receive(reply(0x02, .success), range: .z1)   // late answer to an earlier set speed
    #expect(!late)
    let sent1 = queue.next()
    #expect(sent1 == nil)                                  // stop is still awaiting its own answer
    let own = queue.receive(reply(0x08, .success), range: .z1)
    #expect(own)
}

@Test func timeoutFreesTheQueueAndResetDropsEverything() {
    var queue = ControlQueue()
    queue.enqueue(.start)
    queue.enqueue(.stop)
    _ = queue.next()
    queue.timedOut()
    let sent1 = queue.next()
    #expect(sent1 == .stop)
    queue.reset()
    queue.enqueue(.start)
    let sent2 = queue.next()
    #expect(sent2 == .start)
}

@Test func announcedRangeIsBoundedBySafeEnvelope() {
    #expect(SpeedRange(minKmh: 0.1, maxKmh: 20, stepKmh: 0.1).bounded(by: .safeEnvelope)
            == SpeedRange(minKmh: 0.5, maxKmh: 6.0, stepKmh: 0.1))
    #expect(SpeedRange.z1.bounded(by: .safeEnvelope) == .z1)
    #expect(SpeedRange(minKmh: 7, maxKmh: 9, stepKmh: 0.1).bounded(by: .safeEnvelope) == nil)
    #expect(SpeedRange(minKmh: 1, maxKmh: 6, stepKmh: 0).bounded(by: .safeEnvelope)?.stepKmh == 0.1)
}
