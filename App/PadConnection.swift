@preconcurrency import CoreBluetooth
import Foundation
import os
import WalkingPadKit

/// Read-only BLE link to the WalkingPad: finds a `KS-HD-*` pad advertising FTMS, subscribes to
/// Treadmill Data (0x2ACD) and reconnects on its own. Never writes to the pad.
@MainActor
final class PadConnection: NSObject {
    var onPresence: (PadPresence) -> Void = { _ in }
    var onSample: (TreadmillSample) -> Void = { _ in }

    private static let fitnessMachine = CBUUID(string: "1826")
    private static let treadmillData = CBUUID(string: "2ACD")
    private static let namePrefix = "KS-HD-"
    private static let reconnectDelay: Duration = .seconds(5)

    private let log = Logger(subsystem: "ch.davidpreti.TapisMarche", category: "pad")
    private var central: CBCentralManager?
    private var pad: CBPeripheral?
    private var releasedUntil: Date?

    func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    /// Lets KS Fit take the pad: disconnects and stops scanning for `duration`.
    func release(for duration: TimeInterval) {
        let until = Date.now.addingTimeInterval(duration)
        releasedUntil = until
        central?.stopScan()
        if let pad { central?.cancelPeripheralConnection(pad) }
        log.notice("released until \(until, privacy: .public)")
        onPresence(.released(until: until))
        Task {
            try? await Task.sleep(for: .seconds(duration))
            releasedUntil = nil
            scan()
        }
    }

    private func scan() {
        guard let central, central.state == .poweredOn, releasedUntil == nil, pad == nil else { return }
        onPresence(.absent)
        central.scanForPeripherals(withServices: [Self.fitnessMachine])
        log.notice("scanning")
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
            pad = nil
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
        onPresence(.connecting)
        log.notice("connecting \(name, privacy: .public)")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.fitnessMachine])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("connect failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        pad = nil
        scanLater()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.notice("disconnected")
        pad = nil
        if releasedUntil == nil { onPresence(.absent) }
        scanLater()
    }
}

extension PadConnection: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.fitnessMachine {
            peripheral.discoverCharacteristics([Self.treadmillData], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.treadmillData {
            peripheral.setNotifyValue(true, for: characteristic)
            onPresence(.connected(speedKmh: 0))
            log.notice("connected \(peripheral.name ?? "?", privacy: .public)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
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
