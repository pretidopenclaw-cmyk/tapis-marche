import Foundation

/// Supported Speed Range (0x2AD4), held in hundredths of km/h to avoid floating-point drift.
public struct SpeedRange: Equatable, Sendable {
    public var minKmh: Double
    public var maxKmh: Double
    public var stepKmh: Double

    /// What the Z1E announced: 1.0–6.0 km/h by 0.1.
    public static let z1 = SpeedRange(minKmh: 1.0, maxKmh: 6.0, stepKmh: 0.1)

    public init(minKmh: Double, maxKmh: Double, stepKmh: Double) {
        self.minKmh = minKmh
        self.maxKmh = maxKmh
        self.stepKmh = stepKmh
    }

    /// Three uint16 LE values in 0.01 km/h: minimum, maximum, increment.
    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 6 else { return nil }
        let value = { (i: Int) in Double(Int(bytes[i]) | Int(bytes[i + 1]) << 8) / 100 }
        self.init(minKmh: value(0), maxKmh: value(2), stepKmh: value(4))
    }

    /// Bounded to the range and snapped to the increment.
    public func clamp(_ kmh: Double) -> Double {
        Double(hundredths(kmh)) / 100
    }

    func hundredths(_ kmh: Double) -> Int {
        // Bound the Double first: Int(Double) traps on NaN, infinities and huge values.
        let kmh = kmh.isNaN ? minKmh : min(max(kmh, minKmh), maxKmh)
        let step = max(1, Int((stepKmh * 100).rounded()))
        let snapped = Int((kmh * 100 / Double(step)).rounded()) * step
        return min(max(snapped, Int((minKmh * 100).rounded())), Int((maxKmh * 100).rounded()))
    }
}

/// The only commands the app may write, to the FTMS Control Point (0x2AD9).
/// Every frame starts with 0x00, 0x02, 0x07 or 0x08 — never 0xE8 (OTA mode).
public enum PadCommand: Equatable, Sendable {
    case requestControl
    case start
    case stop
    case setSpeed(Double)

    public func frame(in range: SpeedRange) -> Data {
        switch self {
        case .requestControl: Data([0x00])
        case .start: Data([0x07])
        case .stop: Data([0x08, 0x01])
        case .setSpeed(let kmh):
            Data([0x02]) + withUnsafeBytes(of: UInt16(range.hundredths(kmh)).littleEndian) { Data($0) }
        }
    }
}

public enum ControlResult: Equatable, Sendable {
    case success, notSupported, invalidParameter, operationFailed, controlNotPermitted
    case unknown(UInt8)

    init(code: UInt8) {
        switch code {
        case 1: self = .success
        case 2: self = .notSupported
        case 3: self = .invalidParameter
        case 4: self = .operationFailed
        case 5: self = .controlNotPermitted
        default: self = .unknown(code)
        }
    }
}

/// Control Point indication: 0x80, the request opcode, the result code.
public struct ControlResponse: Equatable, Sendable {
    public var opcode: UInt8
    public var result: ControlResult

    public init(opcode: UInt8, result: ControlResult) {
        self.opcode = opcode
        self.result = result
    }

    public init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 3, bytes[0] == 0x80 else { return nil }
        self.init(opcode: bytes[1], result: ControlResult(code: bytes[2]))
    }
}
