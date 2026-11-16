import Foundation
import Testing
@testable import WalkingPadKit

@Test func framesMatchTheValidatedSpike() {
    let z1 = SpeedRange.z1
    #expect(PadCommand.requestControl.frame(in: z1) == Data(hex: "00"))
    #expect(PadCommand.start.frame(in: z1) == Data(hex: "07"))
    #expect(PadCommand.stop.frame(in: z1) == Data(hex: "0801"))
    #expect(PadCommand.setSpeed(2.0).frame(in: z1) == Data(hex: "02c800"))
    #expect(PadCommand.setSpeed(1.0).frame(in: z1) == Data(hex: "026400"))
}

@Test func speedRangeDecodesTheZ1() {
    #expect(SpeedRange(data: Data(hex: "640058020a00")) == .z1)
    #expect(SpeedRange(data: Data(hex: "6400")) == nil)
}

@Test func fasterAndSlowerClampToRange() {
    let z1 = SpeedRange.z1
    #expect(z1.clamp(6.5) == 6.0)
    #expect(z1.clamp(0.5) == 1.0)
    #expect(z1.clamp(2.04) == 2.0)
    #expect(z1.clamp(2.06) == 2.1)
    #expect(PadCommand.setSpeed(9).frame(in: z1) == Data(hex: "025802"))
}

@Test func noFrameEverStartsWithE8() {
    let commands: [PadCommand] = [.requestControl, .start, .stop] + stride(from: 0.0, through: 10.0, by: 0.05).map { .setSpeed($0) }
    #expect(commands.allSatisfy { $0.frame(in: .z1).first != 0xE8 })
}

@Test func controlResponseDecodes() {
    #expect(ControlResponse(data: Data(hex: "800001")) == ControlResponse(opcode: 0x00, result: .success))
    #expect(ControlResponse(data: Data(hex: "800205")) == ControlResponse(opcode: 0x02, result: .controlNotPermitted))
    #expect(ControlResponse(data: Data(hex: "800709"))?.result == .unknown(9))
    #expect(ControlResponse(data: Data(hex: "7180")) == nil)
}

@Test func absurdSpeedsClampInsteadOfCrashing() {
    #expect(SpeedRange.z1.clamp(1e300) == 6.0)
    #expect(SpeedRange.z1.clamp(-.infinity) == 1.0)
    #expect(SpeedRange.z1.clamp(.nan) == 1.0)
    #expect(PadCommand.setSpeed(.infinity).frame(in: .z1) == Data(hex: "025802"))
}
