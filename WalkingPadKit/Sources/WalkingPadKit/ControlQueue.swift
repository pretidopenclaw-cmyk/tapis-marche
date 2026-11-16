import Foundation

/// Control Point commands, one in flight at a time. A command denied for lack of control is retried
/// once after re-requesting control, then dropped; an answer is only accepted for the command in flight.
public struct ControlQueue: Sendable {
    private struct Item: Sendable {
        let command: PadCommand
        var retried = false
    }

    private var pending: [Item] = []
    private var inFlight: Item?

    public init() {}

    public mutating func enqueue(_ command: PadCommand) {
        pending.append(Item(command: command))
    }

    public mutating func takeControlFirst() {
        pending.insert(Item(command: .requestControl), at: 0)
    }

    /// The next command to write, or nil while one is awaiting its answer.
    public mutating func next() -> PadCommand? {
        guard inFlight == nil, !pending.isEmpty else { return nil }
        inFlight = pending.removeFirst()
        return inFlight?.command
    }

    /// Returns false (and changes nothing) when the answer is not for the command in flight.
    public mutating func receive(_ response: ControlResponse, range: SpeedRange) -> Bool {
        guard let item = inFlight, response.opcode == item.command.frame(in: range).first else { return false }
        inFlight = nil
        if response.result == .controlNotPermitted, item.command != .requestControl, !item.retried {
            pending.insert(contentsOf: [Item(command: .requestControl), Item(command: item.command, retried: true)], at: 0)
        }
        return true
    }

    public mutating func timedOut() {
        inFlight = nil
    }

    public mutating func reset() {
        pending.removeAll()
        inFlight = nil
    }
}

extension SpeedRange {
    /// What the app will ever ask of a walking pad, whatever the pad announces.
    public static let safeEnvelope = SpeedRange(minKmh: 0.5, maxKmh: 6.0, stepKmh: 0.1)

    /// The announced range intersected with `envelope`; nil when they do not overlap.
    public func bounded(by envelope: SpeedRange) -> SpeedRange? {
        let low = max(minKmh, envelope.minKmh), high = min(maxKmh, envelope.maxKmh)
        guard low <= high else { return nil }
        return SpeedRange(minKmh: low, maxKmh: high, stepKmh: stepKmh > 0 ? stepKmh : envelope.stepKmh)
    }
}
