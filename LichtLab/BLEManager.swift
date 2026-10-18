import Foundation
import CoreBluetooth

/// Bluetooth-LE-Verbindung zum OBD-Adapter (vLinker BM+ o. ä.).
/// Alle Delegate-Callbacks laufen auf der Main-Queue.
final class BLEManager: NSObject, ObservableObject, ELMTransport {
    enum Status: Equatable {
        case bluetoothOff
        case unauthorized
        case idle
        case scanning
        case connecting
        case ready
        case failed(String)

        var text: String {
            switch self {
            case .bluetoothOff: return "Bluetooth ist aus"
            case .unauthorized: return "Bluetooth-Zugriff nicht erlaubt"
            case .idle: return "Nicht verbunden"
            case .scanning: return "Suche Adapter …"
            case .connecting: return "Verbinde …"
            case .ready: return "Verbunden"
            case .failed(let message): return "Fehler: \(message)"
            }
        }
    }

    struct Device: Identifiable {
        let id: UUID
        let name: String
        var rssi: Int
        let peripheral: CBPeripheral

        var looksLikeOBDAdapter: Bool {
            let n = name.lowercased()
            return ["vlinker", "obd", "elm", "obdlink", "veepeak"].contains { n.contains($0) }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var devices: [Device] = []
    @Published private(set) var connectedName: String?

    var isReady: Bool { status == .ready }

    var onReceive: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onDisconnect: (() -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var usingPreferredService = false

    // UART-Services typischer ELM327-BLE-Adapter. vLinker nutzt 18F0 (2AF0 = Notify, 2AF1 = Write).
    private static let preferredServices: Set<CBUUID> = [CBUUID(string: "18F0"), CBUUID(string: "FFF0"), CBUUID(string: "FFE0")]
    private static let ignoredServices: Set<CBUUID> = [CBUUID(string: "1800"), CBUUID(string: "1801"), CBUUID(string: "180A"), CBUUID(string: "180F")]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else {
            updateStatusFromCentral()
            return
        }
        devices = []
        status = .scanning
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        if central.isScanning { central.stopScan() }
        if status == .scanning { status = .idle }
    }

    func connect(_ device: Device) {
        stopScan()
        peripheral = device.peripheral
        device.peripheral.delegate = self
        status = .connecting
        central.connect(device.peripheral)
    }

    func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
    }

    /// Schickt eine Zeile an den Adapter (ELM327 erwartet "\r" als Abschluss).
    func send(_ line: String) {
        guard let peripheral, let characteristic = writeCharacteristic else { return }
        let data = Data((line + "\r").utf8)
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        let chunkSize = max(20, peripheral.maximumWriteValueLength(for: type))
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            peripheral.writeValue(data.subdata(in: offset..<end), for: characteristic, type: type)
            offset = end
        }
    }

    private func updateStatusFromCentral() {
        switch central.state {
        case .poweredOn:
            if status == .bluetoothOff || status == .unauthorized { status = .idle }
        case .unauthorized:
            status = .unauthorized
        default:
            status = .bluetoothOff
        }
    }

    private func reset() {
        peripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        usingPreferredService = false
        connectedName = nil
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateStatusFromCentral()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard let name = peripheral.name ?? advertisedName, !name.isEmpty else { return }
        if let index = devices.firstIndex(where: { $0.id == peripheral.identifier }) {
            devices[index].rssi = RSSI.intValue
        } else {
            devices.append(Device(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral))
        }
        devices.sort { lhs, rhs in
            if lhs.looksLikeOBDAdapter != rhs.looksLikeOBDAdapter { return lhs.looksLikeOBDAdapter }
            return lhs.rssi > rhs.rssi
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedName = peripheral.name
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        reset()
        status = .failed(error?.localizedDescription ?? "Verbindung fehlgeschlagen")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        reset()
        status = error.map { .failed($0.localizedDescription) } ?? .idle
        onDisconnect?()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where !Self.ignoredServices.contains(service.uuid) {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard let notify = characteristics.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }),
              let write = characteristics.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) })
        else { return }

        let isPreferred = Self.preferredServices.contains(service.uuid)
        // Ein bekannter UART-Service gewinnt gegen einen zufällig passenden anderen.
        guard writeCharacteristic == nil || (isPreferred && !usingPreferredService) else { return }

        if let old = notifyCharacteristic, old != notify { peripheral.setNotifyValue(false, for: old) }
        writeCharacteristic = write
        notifyCharacteristic = notify
        usingPreferredService = isPreferred
        peripheral.setNotifyValue(true, for: notify)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notifyCharacteristic else { return }
        if let error {
            status = .failed(error.localizedDescription)
        } else if characteristic.isNotifying, status != .ready {
            status = .ready
            onReady?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic == notifyCharacteristic, let data = characteristic.value else { return }
        onReceive?(String(decoding: data, as: UTF8.self))
    }
}
