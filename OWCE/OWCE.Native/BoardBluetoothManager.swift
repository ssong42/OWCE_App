import CoreBluetooth
import Foundation

@MainActor
final class BoardBluetoothManager: NSObject, ObservableObject {
    static let serviceID = CBUUID(string: "E659F300-EA98-11E3-AC10-0800200C9A66")

    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var boards: [CBPeripheral] = []
    @Published private(set) var connectedBoard: CBPeripheral?
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var rideMode: String?
    @Published private(set) var rideModeNumber: Int?
    @Published private(set) var rideModes: [(name: String, value: Int)] = []
    @Published private(set) var speed: Double?
    @Published private(set) var tripDistance: Double?
    @Published private(set) var lifetimeDistance: Double?
    @Published private(set) var batteryVoltage: Double?
    @Published private(set) var currentAmps: Double?
    @Published private(set) var motorTemperature: Int?
    @Published private(set) var controllerTemperature: Int?
    @Published private(set) var batteryTemperature: Int?
    @Published private(set) var safetyHeadroom: Int?
    @Published private(set) var firmwareRevision: Int?
    @Published private(set) var hardwareRevision: Int?
    @Published private(set) var serialNumber: Int?
    @Published private(set) var batterySerialNumber: Int?
    @Published private(set) var frontLightMode: Int?
    @Published private(set) var rearLightMode: Int?
    @Published private(set) var batteryCellVoltages: [Int: Double] = [:]
    @Published private(set) var characteristicValues: [String: String] = [:]
    @Published private(set) var boardType = "Onewheel"
    @Published private(set) var telemetryStatus = "Waiting for board data…"
    @Published private(set) var telemetryValuesReceived = 0
    @Published private(set) var keepAliveStatus = "Waiting for board firmware and ride mode…"
    @Published private(set) var latestCharacteristicUUID: String?
    @Published private(set) var latestCharacteristicData: Data?
    @Published private(set) var status = "Bluetooth is starting…"

    private var central: CBCentralManager!
    private var discovered: Set<UUID> = []
    private var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var activePeripheral: CBPeripheral?
    private var keepAliveTimer: Timer?
    private var keepAliveStarted = false
    private var rideModeValue: Int?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    var isScanning: Bool { central?.isScanning == true }

    func scan() {
        guard state == .poweredOn else {
            status = state == .unauthorized ? "Allow Bluetooth access in Settings." : "Turn on Bluetooth to find your board."
            return
        }
        boards.removeAll()
        discovered.removeAll()
        status = "Searching for nearby Onewheels…"
        central.scanForPeripherals(withServices: [Self.serviceID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        status = "Connecting to \(peripheral.name ?? "Onewheel")…"
        central.connect(peripheral)
    }

    func disconnect() {
        guard let connectedBoard else { return }
        central.cancelPeripheralConnection(connectedBoard)
    }

    private func discoverValues(on peripheral: CBPeripheral) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else { return }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    private func decode(_ data: Data, characteristic: CBUUID) {
        guard data.count >= 2 else { return }
        // OWCE's iOS BLE implementation reverses the incoming bytes, then
        // reads the result as a little-endian UInt16. With the reversed
        // buffer below, the numeric value is first + (second << 8).
        let bytes = Array(data.reversed())
        latestCharacteristicUUID = characteristic.uuidString.uppercased()
        latestCharacteristicData = Data(bytes)
        let first = Int(bytes[0])
        let second = Int(bytes[1])
        let raw = first | (second << 8)
        characteristicValues[characteristic.uuidString.uppercased()] = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        switch characteristic {
        case CBUUID(string: "E659F301-EA98-11E3-AC10-0800200C9A66"):
            serialNumber = raw
        case CBUUID(string: "E659F306-EA98-11E3-AC10-0800200C9A66"):
            batterySerialNumber = raw
        case CBUUID(string: "E659F303-EA98-11E3-AC10-0800200C9A66"):
            batteryPercent = first > 0 ? first : (second > 0 ? second : batteryPercent)
        case CBUUID(string: "E659F302-EA98-11E3-AC10-0800200C9A66"):
            rideModeValue = raw
            rideModeNumber = raw
            rideMode = rideModeName(raw)
        case CBUUID(string: "E659F30A-EA98-11E3-AC10-0800200C9A66"):
            tripDistance = Double(raw) * wheelCircumference / 1_000_000
        case CBUUID(string: "E659F30B-EA98-11E3-AC10-0800200C9A66"):
            speed = 917.66 * Double(raw) * 0.00001666666667 * 2.23694
        case CBUUID(string: "E659F310-EA98-11E3-AC10-0800200C9A66"):
            motorTemperature = first
            controllerTemperature = second
        case CBUUID(string: "E659F311-EA98-11E3-AC10-0800200C9A66"):
            firmwareRevision = raw
        case CBUUID(string: "E659F30D-EA98-11E3-AC10-0800200C9A66"):
            frontLightMode = raw
        case CBUUID(string: "E659F30E-EA98-11E3-AC10-0800200C9A66"):
            rearLightMode = raw
        case CBUUID(string: "E659F312-EA98-11E3-AC10-0800200C9A66"):
            let signedValue = raw > 32767 ? raw - 65536 : raw
            currentAmps = Double(signedValue) * (hardwareRevision.map { $0 < 3000 ? 0.0009 : ($0 < 4000 ? 0.0018 : 0.002) } ?? 0.002)
        case CBUUID(string: "E659F315-EA98-11E3-AC10-0800200C9A66"):
            batteryTemperature = boardType == "V1" || boardType == "Plus" ? second : first
        case CBUUID(string: "E659F316-EA98-11E3-AC10-0800200C9A66"):
            batteryVoltage = Double(raw) / 10
        case CBUUID(string: "E659F317-EA98-11E3-AC10-0800200C9A66"):
            safetyHeadroom = raw
        case CBUUID(string: "E659F318-EA98-11E3-AC10-0800200C9A66"):
            hardwareRevision = raw
            boardType = Self.boardName(for: raw)
            rideModes = Self.availableRideModes(for: boardType)
            if let rideModeValue { rideMode = rideModeName(rideModeValue) }
        case CBUUID(string: "E659F319-EA98-11E3-AC10-0800200C9A66"):
            lifetimeDistance = Double(raw) * wheelCircumference / 1_000_000
        case CBUUID(string: "E659F31B-EA98-11E3-AC10-0800200C9A66"):
            if let firmwareRevision, firmwareRevision >= 4141 {
                let cellID = (raw & 0xF000) >> 12
                batteryCellVoltages[cellID] = Double(raw & 0x0FFF) * 0.0011
            } else {
                batteryCellVoltages[second] = Double(first) * 0.02
            }
        default: break
        }
        telemetryValuesReceived += 1
        if characteristic == CBUUID(string: "E659F302-EA98-11E3-AC10-0800200C9A66"), raw == 0,
           let firmwareRevision, firmwareRevision >= 4142 {
            telemetryStatus = "Board is not activated yet. Open the official Onewheel app, connect until a ride mode appears, force-quit it, then reconnect here."
        } else {
            telemetryStatus = "Receiving board data (\(telemetryValuesReceived) updates)."
        }
        startKeepAliveIfReady()
    }

    private func startKeepAliveIfReady() {
        guard !keepAliveStarted,
              let peripheral = activePeripheral,
              let firmwareRevision, firmwareRevision >= 4000,
              let hardwareRevision,
              let rideModeValue else { return }

        guard rideModeValue > 0 else {
            keepAliveStatus = "Ride mode is inactive. Activate the board in the official Onewheel app, then reconnect."
            return
        }
        guard hardwareRevision < 6000 || hardwareRevision >= 7000 else {
            keepAliveStatus = "Keepalive is not used for this board model."
            return
        }
        guard let characteristic = characteristics[CBUUID(string: "E659F311-EA98-11E3-AC10-0800200C9A66")] else {
            keepAliveStatus = "Firmware characteristic not found; keepalive unavailable."
            return
        }
        guard characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) else {
            keepAliveStatus = "Firmware characteristic is not writable; keepalive unavailable."
            return
        }

        keepAliveStarted = true
        keepAliveStatus = "Board session keepalive enabled."
        let firmwareBytes = Data([UInt8((firmwareRevision >> 8) & 0xff), UInt8(firmwareRevision & 0xff)])
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        let sendKeepAlive = { [weak peripheral] in
            guard let peripheral else { return }
            peripheral.writeValue(firmwareBytes, for: characteristic, type: writeType)
        }
        sendKeepAlive()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in sendKeepAlive() }
    }

    private static let liveNotificationIDs = Set([
        "E659F302-EA98-11E3-AC10-0800200C9A66", // ride mode
        "E659F303-EA98-11E3-AC10-0800200C9A66", // battery percent
        "E659F30A-EA98-11E3-AC10-0800200C9A66", // trip odometer
        "E659F30B-EA98-11E3-AC10-0800200C9A66", // RPM
        "E659F30F-EA98-11E3-AC10-0800200C9A66", // status
        "E659F310-EA98-11E3-AC10-0800200C9A66", // temperatures
        "E659F312-EA98-11E3-AC10-0800200C9A66", // current
        "E659F313-EA98-11E3-AC10-0800200C9A66", // trip amp hours
        "E659F314-EA98-11E3-AC10-0800200C9A66", // regenerative amp hours
        "E659F315-EA98-11E3-AC10-0800200C9A66", // battery temperature
        "E659F316-EA98-11E3-AC10-0800200C9A66", // battery voltage
        "E659F31B-EA98-11E3-AC10-0800200C9A66"  // battery cells
    ].map { CBUUID(string: $0) })

    private var wheelCircumference: Double {
        boardType == "Pint" || boardType == "Pint X" ? 837.86 : 917.66
    }

    private static func boardName(for revision: Int) -> String {
        switch revision {
        case 1..<3000: "V1"
        case 3000..<4000: "Plus"
        case 4000..<5000: "XR"
        case 5000..<6000: "Pint"
        case 6000..<7000: "GT"
        case 7000..<8000: "Pint X"
        default: "Onewheel"
        }
    }

    private func rideModeName(_ raw: Int) -> String {
        switch boardType {
        case "V1": [1: "Classic", 2: "Extreme", 3: "Elevated"][raw] ?? "Mode \(raw)"
        case "Plus", "XR": [4: "Sequoia", 5: "Cruz", 6: "Mission", 7: "Elevated", 8: "Delirium", 9: "Custom"][raw] ?? "Mode \(raw)"
        case "Pint", "Pint X": [5: "Redwood", 6: "Pacific", 7: "Elevated", 8: "Skyline"][raw] ?? "Mode \(raw)"
        case "GT": [3: "Bay", 4: "Roam", 5: "Flow", 6: "Highline", 7: "Elevated", 8: "Apex", 9: "Custom"][raw] ?? "Mode \(raw)"
        default: "Mode \(raw)"
        }
    }

    private static func availableRideModes(for board: String) -> [(name: String, value: Int)] {
        switch board {
        case "V1": [("Classic", 1), ("Extreme", 2), ("Elevated", 3)]
        case "Plus", "XR": [("Sequoia", 4), ("Cruz", 5), ("Mission", 6), ("Elevated", 7), ("Delirium", 8), ("Custom", 9)]
        case "Pint", "Pint X": [("Redwood", 5), ("Pacific", 6), ("Elevated", 7), ("Skyline", 8)]
        case "GT": [("Bay", 3), ("Roam", 4), ("Flow", 5), ("Highline", 6), ("Elevated", 7), ("Apex", 8), ("Custom", 9)]
        default: []
        }
    }

    func changeRideMode(to mode: Int) {
        guard let peripheral = activePeripheral,
              let characteristic = characteristics[CBUUID(string: "E659F302-EA98-11E3-AC10-0800200C9A66")],
              characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) else {
            telemetryStatus = "This board does not currently allow ride-mode changes."
            return
        }
        guard rideModes.contains(where: { $0.value == mode }) else { return }
        let payload = Data([UInt8((mode >> 8) & 0xff), UInt8(mode & 0xff)])
        let type: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(payload, for: characteristic, type: type)
        telemetryStatus = "Ride-mode change sent. Verify the board display before riding."
    }
}

extension BoardBluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.state = central.state
            switch central.state {
            case .poweredOn: self.status = "Ready to scan for your Onewheel."
            case .poweredOff: self.status = "Bluetooth is off. Turn it on to connect."
            case .unauthorized: self.status = "Bluetooth permission is required."
            case .unsupported: self.status = "Bluetooth LE is not supported on this device."
            default: self.status = "Bluetooth is starting…"
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        Task { @MainActor in
            guard !self.discovered.contains(peripheral.identifier) else { return }
            self.discovered.insert(peripheral.identifier)
            self.boards.append(peripheral)
            self.boards.sort { ($0.name ?? "Onewheel") < ($1.name ?? "Onewheel") }
            self.status = "Found \(self.boards.count) board\(self.boards.count == 1 ? "" : "s")."
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedBoard = peripheral
            self.status = "Connected — reading board data…"
            self.telemetryStatus = "Discovering board characteristics…"
            self.telemetryValuesReceived = 0
            self.resetTelemetry()
            self.activePeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices([Self.serviceID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in self.status = "Couldn't connect. Move closer and try again." }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.connectedBoard = nil
            self.resetTelemetry()
            self.status = error == nil ? "Disconnected." : "Connection lost. Tap Scan to reconnect."
            self.telemetryStatus = "Connect to a board to receive telemetry."
        }
    }
}

extension BoardBluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in self.discoverValues(on: peripheral) }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil, let characteristics = service.characteristics else {
                self.telemetryStatus = error?.localizedDescription ?? "No board characteristics found."
                return
            }
            var readableCount = 0
            var notifiableCount = 0
            self.characteristics = Dictionary(uniqueKeysWithValues: characteristics.map { ($0.uuid, $0) })
            for characteristic in characteristics {
                if Self.liveNotificationIDs.contains(characteristic.uuid), (characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate)) {
                    peripheral.setNotifyValue(true, for: characteristic)
                    notifiableCount += 1
                }
                if characteristic.properties.contains(.read) {
                    peripheral.readValue(for: characteristic)
                    readableCount += 1
                }
            }
            self.status = "Connected to \(peripheral.name ?? "Onewheel")."
            self.telemetryStatus = "Found \(characteristics.count) characteristics · \(readableCount) readable · \(notifiableCount) subscribed. Waiting for data…"
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil, let data = characteristic.value else {
                self.telemetryStatus = error?.localizedDescription ?? "Board returned an empty value for \(characteristic.uuid)."
                return
            }
            self.decode(data, characteristic: characteristic.uuid)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let error else { return }
        Task { @MainActor in self.telemetryStatus = "Notification setup failed: \(error.localizedDescription)" }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == CBUUID(string: "E659F311-EA98-11E3-AC10-0800200C9A66") else { return }
        Task { @MainActor in
            self.keepAliveStatus = error.map { "Keepalive write failed: \($0.localizedDescription)" } ?? "Board session keepalive confirmed."
        }
    }

    private func resetTelemetry() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        keepAliveStarted = false
        keepAliveStatus = "Waiting for board firmware and ride mode…"
        activePeripheral = nil
        characteristics.removeAll()
        batteryPercent = nil
        rideMode = nil
        rideModeValue = nil
        rideModeNumber = nil
        rideModes = []
        speed = nil
        tripDistance = nil
        lifetimeDistance = nil
        batteryVoltage = nil
        currentAmps = nil
        motorTemperature = nil
        controllerTemperature = nil
        batteryTemperature = nil
        safetyHeadroom = nil
        firmwareRevision = nil
        hardwareRevision = nil
        serialNumber = nil
        batterySerialNumber = nil
        frontLightMode = nil
        rearLightMode = nil
        batteryCellVoltages = [:]
        characteristicValues = [:]
        boardType = "Onewheel"
    }
}
