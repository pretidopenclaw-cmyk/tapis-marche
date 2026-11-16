import Foundation

public enum FTMSDecodeError: Error, Equatable {
    case truncated(expected: Int, got: Int)
}

/// Decodes the Bluetooth SIG FTMS "Treadmill Data" characteristic (0x2ACD),
/// plus the KingSmith extension carried under flag bit 13 (steps, uint24 LE).
public enum FTMSTreadmillFrame {
    private enum Field {
        case speed, avgSpeed, distance, inclination, elevation, instantPace, avgPace
        case energy, heartRate, metabolicEquivalent, elapsed, remaining, forcePower, steps
    }

    private struct Slot {
        let field: Field
        let bit: Int
        let length: Int
        /// FTMS quirk: speed is present when its bit is *clear*.
        var presentWhenSet = true

        func isPresent(in flags: Int) -> Bool {
            (flags & (1 << bit) != 0) == presentWhenSet
        }
    }

    /// Field order and sizes as defined by FTMS; fields not stored are still consumed.
    private static let layout: [Slot] = [
        Slot(field: .speed, bit: 0, length: 2, presentWhenSet: false),
        Slot(field: .avgSpeed, bit: 1, length: 2),
        Slot(field: .distance, bit: 2, length: 3),
        Slot(field: .inclination, bit: 3, length: 4),
        Slot(field: .elevation, bit: 4, length: 4),
        Slot(field: .instantPace, bit: 5, length: 1),
        Slot(field: .avgPace, bit: 6, length: 1),
        Slot(field: .energy, bit: 7, length: 5),
        Slot(field: .heartRate, bit: 8, length: 1),
        Slot(field: .metabolicEquivalent, bit: 9, length: 1),
        Slot(field: .elapsed, bit: 10, length: 2),
        Slot(field: .remaining, bit: 11, length: 2),
        Slot(field: .forcePower, bit: 12, length: 4),
        Slot(field: .steps, bit: 13, length: 3),
    ]

    private static let flagsLength = 2

    public static func decode(_ data: Data, at timestamp: Date) throws -> TreadmillSample {
        let bytes = [UInt8](data)
        guard bytes.count >= flagsLength else {
            throw FTMSDecodeError.truncated(expected: flagsLength, got: bytes.count)
        }
        let flags = littleEndian(bytes[0..<flagsLength])
        let present = layout.filter { $0.isPresent(in: flags) }
        let expected = flagsLength + present.reduce(0) { $0 + $1.length }
        guard bytes.count >= expected else {
            throw FTMSDecodeError.truncated(expected: expected, got: bytes.count)
        }
        let values = readValues(present, from: bytes)
        return TreadmillSample(
            timestamp: timestamp,
            speedKmh: Double(values[.speed] ?? 0) / 100,
            distanceM: values[.distance],
            elapsedS: values[.elapsed],
            energyKcal: values[.energy],
            steps: values[.steps]
        )
    }

    private static func readValues(_ slots: [Slot], from bytes: [UInt8]) -> [Field: Int] {
        var values: [Field: Int] = [:]
        var offset = flagsLength
        for slot in slots {
            // Energy packs total (uint16) + per hour (uint16) + per minute (uint8): keep the total.
            let width = slot.field == .energy ? 2 : slot.length
            values[slot.field] = littleEndian(bytes[offset..<offset + width])
            offset += slot.length
        }
        return values
    }

    private static func littleEndian(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reversed().reduce(0) { ($0 << 8) | Int($1) }
    }
}
