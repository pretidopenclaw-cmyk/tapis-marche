@preconcurrency import CoreBluetooth
import Foundation
import os
import WalkingPadKit

/// BLE link to the WalkingPad: finds a `KS-HD-*` pad advertising FTMS, subscribes to Treadmill Data
/// (0x2ACD), reconnects on its own, and sends FTMS Control Point (0x2AD9) commands one at a time.
/// The Control Point is the only thing ever written to the pad.
@MainActor
final class PadConnection: NSObject {
    var onPresence: (PadPresence) -> Void = { _ in }
    var onSample: (TreadmillSample) -> Void = { _ in }
    var onConnected: (Date) -> Void = { _ in }
    private(set) var speedRange = SpeedRange.z1
    var isReady: Bool { pad != nil && controlPoint != nil }

    private static let fitnessMachine = CBUUID(string: "1826")
    private static let treadmillData = CBUUID(string: "2ACD")
    private static let controlPointUUID = CBUUID(string: "2AD9")
    private static let speedRangeUUID = CBUUID(string: "2AD4")
    private static let writeSpacing: TimeInterval = 0.4
    private static let responseTimeout: Duration = .seconds(3)
    private static let namePrefix = "KS-HD-"
    private static let reconnectDelay: Duration = .seconds(5)
    /// A connection that has not delivered Treadmill Data by then is abandoned and retried.
    private static let connectTimeout: Duration = .seconds(20)

    private let log = Logger(subsystem: "ch.davidpreti.TapisMarche", category: "pad")
    private var central: CBCentralManager?
    private var pad: CBPeripheral?
    private var releasedUntil: Date?
    private var releaseTask: Task<Void, Never>?
    private var connectWatchdog: Task<Void, Never>?
    private var controlPoint: CBCharacteristic?
    private var queue: [PadCommand] = []
    private var inFlight: PadCommand?
    private var retriedAfterDenial = false
    private var lastWriteAt = Date.distantPast
    private var responseWatchdog: Task<Void, Never>?

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Lets KS Fit take the pad: disconnects and stops scanning for `duration`.
    func release(for duration: TimeInterval) {
        let until = Date.now.addingTimeInterval(duration)
        releasedUntil = until
        central?.stopScan()
        if let pad { central?.cancelPeripheralConnection(pad) }
        queue.removeAll()
        log.notice("released until \(until, privacy: .public)")
        onPresence(.released(until: until))
        releaseTask?.cancel()   // a second tap restarts the 15 minutes instead of being cut short by the first
        releaseTask = Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            releasedUntil = nil
            scan()
        }
    }

    /// Queues a Control Point command; ignored (and logged) when the pad is not ready.
    func send(_ command: PadCommand) {
        guard isReady else {
            log.notice("control ignored, pad not ready")
            return
        }
        queue.append(command)
        pump()
    }

    private func pump() {
        guard inFlight == nil, !queue.isEmpty, let pad, let controlPoint else { return }
        let wait = Self.writeSpacing - Date.now.timeIntervalSince(lastWriteAt)
        guard wait <= 0 else {
            Task {
                try? await Task.sleep(for: .seconds(wait))
                pump()
            }
            return
        }
        let command = queue.removeFirst()
        let frame = command.frame(in: speedRange)
        guard frame.first != 0xE8 else { return }   // OTA mode: never, whatever happens upstream
        inFlight = command
        lastWriteAt = .now
        pad.writeValue(frame, for: controlPoint, type: .withResponse)
        log.notice("control → \(frame.map { String(format: "%02x", $0) }.joined(separator: " "), privacy: .public)")
        responseWatchdog?.cancel()
        responseWatchdog = Task {
            try? await Task.sleep(for: Self.responseTimeout)
            guard !Task.isCancelled else { return }
            log.error("control ← no answer")
            inFlight = nil
            pump()
        }
    }

    private func handle(_ response: ControlResponse) {
        guard let command = inFlight else { return }
        responseWatchdog?.cancel()
        inFlight = nil
        log.notice("control ← \(String(describing: response.result), privacy: .public)")
        if response.result == .controlNotPermitted, command != .requestControl, !retriedAfterDenial {
            retriedAfterDenial = true
            queue.insert(contentsOf: [.requestControl, command], at: 0)
        } else {
            retriedAfterDenial = false
        }
        pump()
    }

    private func forgetPad() {
        pad = nil
        controlPoint = nil
        queue.removeAll()
        inFlight = nil
        responseWatchdog?.cancel()
    }

    private func scan() {
        guard let central, central.state == .poweredOn, releasedUntil == nil, pad == nil else { return }
        onPresence(.absent)
        central.scanForPeripherals(withServices: [Self.fitnessMachine])
        log.notice("scanning")
    }

    private func watchConnection(_ peripheral: CBPeripheral) {
        connectWatchdog?.cancel()
        connectWatchdog = Task {
            try? await Task.sleep(for: Self.connectTimeout)
            guard !Task.isCancelled, pad === peripheral else { return }
            log.error("connection timed out, retrying")
            central?.cancelPeripheralConnection(peripheral)
            forgetPad()
            scanLater()
        }
    }

    private func scanLater() {
        Task {
            try? await Task.sleep(for: Self.reconnectDelay)
            scan()
        }
    }
}

extension PadConnection: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.notice("bluetooth state \(central.state.rawValue, privacy: .public)")
        if central.state != .poweredOn {
            // Bluetooth off/reset invalidates peripherals without a disconnect callback: forget the pad
            // so the next power-on scans again instead of believing it is still connected.
            forgetPad()
            if releasedUntil == nil { onPresence(.absent) }
        }
        scan()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        guard name.hasPrefix(Self.namePrefix), pad == nil else { return }
        central.stopScan()
        pad = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
        watchConnection(peripheral)
        onPresence(.connecting)
        log.notice("connecting \(name, privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.fitnessMachine])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        forgetPad()
        scanLater()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.notice("disconnected")
        forgetPad()
        if releasedUntil == nil { onPresence(.absent) }
        scanLater()
    }
}

extension PadConnection: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.fitnessMachine {
            peripheral.discoverCharacteristics([Self.treadmillData, Self.controlPointUUID, Self.speedRangeUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case Self.treadmillData:
                peripheral.setNotifyValue(true, for: characteristic)
                connectWatchdog?.cancel()
                onPresence(.connected(speedKmh: 0))
                log.notice("connected \(peripheral.name ?? "?", privacy: .public)")
            case Self.controlPointUUID:
                peripheral.setNotifyValue(true, for: characteristic)   // indications carry the results
            case Self.speedRangeUUID:
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == Self.controlPointUUID, characteristic.isNotifying else { return }
        controlPoint = characteristic
        // Held control: the remote keeps working while the app holds it (spike 2026-11-16 20:38).
        queue.insert(.requestControl, at: 0)
        onConnected(.now)
        pump()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case Self.controlPointUUID:
            if let response = ControlResponse(data: data) { handle(response) }
            return
        case Self.speedRangeUUID:
            if let range = SpeedRange(data: data) {
                speedRange = range
                log.notice("speed range \(range.minKmh, privacy: .public)–\(range.maxKmh, privacy: .public) km/h")
            }
            return
        default:
            break
        }
        do {
            let sample = try FTMSTreadmillFrame.decode(data, at: .now)
            log.info("sample speed=\(sample.speedKmh, privacy: .public) dist=\(sample.distanceM ?? -1, privacy: .public) steps=\(sample.steps ?? -1, privacy: .public)")
            onPresence(.connected(speedKmh: sample.speedKmh))
            onSample(sample)
        } catch {
            log.error("bad frame \(data.map { String(format: "%02x", $0) }.joined(), privacy: .public)")
        }
    }
}
