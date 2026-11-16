import Foundation
import Testing
@testable import WalkingPadKit

private func parse(_ link: String) throws(PadURLError) -> PadURLCommand {
    try PadURLCommand(url: URL(string: link)!)
}

@Test func parsesEveryLink() throws {
    #expect(try parse("tapismarche://demarrer") == .start)
    #expect(try parse("tapismarche://arreter") == .stop)
    #expect(try parse("tapismarche://vitesse/2.5") == .speed(2.5))
    #expect(try parse("tapismarche://plus-vite") == .faster)
    #expect(try parse("tapismarche://moins-vite") == .slower)
}

@Test func speedAcceptsFrenchDecimalComma() throws {
    #expect(try parse("tapismarche://vitesse/2,5") == .speed(2.5))
}

@Test func rejectsUnknownOrUnreadable() {
    #expect(throws: PadURLError.unknownCommand("danser")) { try parse("tapismarche://danser") }
    #expect(throws: PadURLError.unreadableSpeed("vite")) { try parse("tapismarche://vitesse/vite") }
    #expect(throws: PadURLError.unknownCommand("autre://demarrer")) { try parse("autre://demarrer") }
}

@Test func fasterSlowerFromCurrentSpeed() {
    #expect(PadURLCommand.faster.padCommand(currentSpeedKmh: 2.0, range: .z1) == .setSpeed(2.5))
    #expect(PadURLCommand.slower.padCommand(currentSpeedKmh: 1.2, range: .z1) == .setSpeed(1.0))
    #expect(PadURLCommand.speed(9).padCommand(currentSpeedKmh: 2.0, range: .z1) == .setSpeed(6.0))
    #expect(PadURLCommand.start.padCommand(currentSpeedKmh: 0, range: .z1) == .start)
}
