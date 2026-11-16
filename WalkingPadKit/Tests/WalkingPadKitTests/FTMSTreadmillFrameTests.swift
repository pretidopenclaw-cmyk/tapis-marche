import Foundation
import Testing
@testable import WalkingPadKit

extension Data {
    /// Test helper: "8424ff" → [0x84, 0x24, 0xff].
    init(hex: String) {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        self.init(bytes)
    }
}

private let t0 = Date(timeIntervalSince1970: 0)

@Test func decodesIdleFrameFromRealPad() throws {
    let s = try FTMSTreadmillFrame.decode(Data(hex: "8424000000000000000000000000000000"), at: t0)
    #expect(s.speedKmh == 0 && s.distanceM == 0 && s.energyKcal == 0 && s.elapsedS == 0 && s.steps == 0)
}

@Test func decodesWalkingFrame() throws {
    // flags 0x2484: speed, distance(b2), energy(b7), elapsed(b10), KingSmith steps(b13)
    let s = try FTMSTreadmillFrame.decode(Data(hex: "84245e01fa00007800ffffff7800c80000"), at: t0)
    #expect(s.speedKmh == 3.5)
    #expect(s.distanceM == 250)
    #expect(s.energyKcal == 120)
    #expect(s.elapsedS == 120)
    #expect(s.steps == 200)
    #expect(s.timestamp == t0)
}

@Test func frameWithoutBit13HasNilSteps() throws {
    let s = try FTMSTreadmillFrame.decode(Data(hex: "84045e01fa00007800ffffff7800"), at: t0)
    #expect(s.steps == nil)
    #expect(s.elapsedS == 120)
}

@Test func truncatedFrameThrows() {
    #expect(throws: FTMSDecodeError.truncated(expected: 17, got: 5)) {
        try FTMSTreadmillFrame.decode(Data(hex: "84245e01fa"), at: t0)
    }
}
