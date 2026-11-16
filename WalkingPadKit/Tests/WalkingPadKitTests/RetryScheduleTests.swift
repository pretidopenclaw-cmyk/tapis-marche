import Testing
@testable import WalkingPadKit

@Test func retryDelaysGrowThenCapAtFifteenMinutes() {
    #expect((1...6).map(RetrySchedule.delaySeconds(afterFailures:)) == [60, 120, 300, 900, 900, 900])
}

@Test func noDelayBeforeAnyFailure() {
    #expect(RetrySchedule.delaySeconds(afterFailures: 0) == 0)
}
