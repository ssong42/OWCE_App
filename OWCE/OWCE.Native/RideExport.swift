import Foundation

enum RideExport {
    static let privateSerialUUIDs: Set<String> = [
        "E659F301-EA98-11E3-AC10-0800200C9A66", // board serial
        "E659F306-EA98-11E3-AC10-0800200C9A66"  // battery serial
    ]

    static func protobufEvents(for ride: RideRecord, removingIdentifiers: Bool) -> Data {
        var output = Data()
        for event in ride.rawEvents ?? [] {
            var message = Data()
            appendBytes(field: 1, value: Data(event.uuid.utf8), to: &message)
            message.append(0x10)
            appendVarint(UInt64(max(0, event.timestamp)), to: &message)
            let eventData = removingIdentifiers && privateSerialUUIDs.contains(event.uuid.uppercased()) ? Data(repeating: 0, count: event.data.count) : event.data
            appendBytes(field: 3, value: eventData, to: &message)
            appendVarint(UInt64(message.count), to: &output)
            output.append(message)
        }
        return output
    }

    static func csv(for ride: RideRecord) -> String {
        var lines = ["Timestamp,Property UUID,Property Name,Raw Data (hex)"]
        for event in ride.rawEvents ?? [] {
            let name = characteristicName(event.uuid).replacingOccurrences(of: "\"", with: "\"\"")
            let hex = event.data.map { String(format: "%02X", $0) }.joined(separator: "-")
            lines.append("\(event.timestamp),\(event.uuid),\"\(name)\",\(hex)")
        }
        return lines.joined(separator: "\n")
    }

    static func characteristicName(_ uuid: String) -> String {
        let index = uuid.uppercased().components(separatedBy: "-").first ?? ""
        let short = String(index.suffix(3))
        let names: [String: String] = [
            "301": "SerialNumber", "302": "RideMode", "303": "BatteryPercent", "304": "BatteryLow5", "305": "BatteryLow20",
            "306": "BatterySerial", "307": "Pitch", "308": "Roll", "309": "Yaw", "30A": "TripOdometer", "30B": "RPM",
            "30C": "LightMode", "30D": "LightsFront", "30E": "LightsBack", "30F": "StatusError", "310": "Temperature",
            "311": "FirmwareRevision", "312": "CurrentAmps", "313": "TripAmpHours", "314": "TripRegenAmpHours",
            "315": "BatteryTemperature", "316": "BatteryVoltage", "317": "SafetyHeadroom", "318": "HardwareRevision",
            "319": "LifetimeOdometer", "31A": "LifetimeAmpHours", "31B": "BatteryCells", "31C": "LastErrorCode"
        ]
        return names[short] ?? "Unknown"
    }

    static func writeCSV(_ ride: RideRecord) -> URL? {
        let safeName = (ride.name ?? "OWCE-Ride").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).csv")
        do {
            try Data(csv(for: ride).utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func appendBytes(field: UInt64, value: Data, to data: inout Data) {
        appendVarint((field << 3) | 2, to: &data)
        appendVarint(UInt64(value.count), to: &data)
        data.append(value)
    }

    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var remaining = value
        while remaining >= 0x80 {
            data.append(UInt8((remaining & 0x7f) | 0x80))
            remaining >>= 7
        }
        data.append(UInt8(remaining))
    }
}
